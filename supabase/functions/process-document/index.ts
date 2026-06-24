import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { encode as encodeBase64 } from "https://deno.land/std@0.177.0/encoding/base64.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { logError, logInfo, logWarn, redact } from "../_shared/redact.ts";
import {
  HttpError,
  readJsonObject,
  requireStringField,
} from "../_shared/request.ts";
import {
  checkRateLimit,
  rateLimitKey,
  rateLimitResponse,
} from "../_shared/rate_limit.ts";
import {
  recordAuditEvent,
  recordAuditEventDeferred,
} from "../_shared/audit.ts";
import {
  parseMoney,
  parseQuantity,
  roundMoney,
} from "../_shared/number_normalization.ts";

const OPENROUTER_ENDPOINT = "https://openrouter.ai/api/v1/chat/completions";
// NOTE 2026-06-02: routes through OpenRouter free vision model. Requires the
// account's privacy settings to allow free providers that may train on / publish
// prompts (https://openrouter.ai/settings/privacy), otherwise OpenRouter will
// return 404 "No endpoints found" for any :free slug.
const MODEL = "nvidia/nemotron-nano-12b-v2-vl:free";
const TEXT_CLASSIFIER_MODEL = "nvidia/nemotron-nano-12b-v2-vl:free";
const IMAGE_FETCH_TIMEOUT_MS = 15_000;
const OPENROUTER_REQUEST_TIMEOUT_MS = 90_000;
const MAX_IMAGE_BYTES = 8 * 1024 * 1024;
const MAX_IMAGES_PER_REQUEST = 3;
const MAX_IMAGES_PER_DOCUMENT = 6;
const MAX_JSON_BYTES = 4_096;
const MAX_OPENROUTER_ERROR_BODY_CHARS = 2_000;
const RATE_LIMIT_WINDOW_MS = 60_000;
const RATE_LIMIT_MAX_REQUESTS = 6;
const OPENROUTER_MAX_TOKENS = 2500;

const jsonHeaders = {
  "Content-Type": "application/json",
};

type JsonObject = Record<string, unknown>;
type SupabaseEdgeClient = ReturnType<typeof createClient<any, "public", any>>;

interface ProcessDocumentRequest {
  documentId: string;
}

interface DocumentAccessRow {
  id: string;
  company_id: string;
  file_path: string | null;
  rendered_image_url: string | null;
  file_url: string | null;
  currency: string | null;
  ocr_raw_data: unknown;
}

interface DocumentImageSource {
  url: string;
  pageNumber: number;
  source: "path" | "url" | "single";
}

interface PreparedDocumentImage extends DocumentImageSource {
  dataUrl: string;
  mime: string;
  bytes: number;
  base64Chars: number;
  dimensions: { width: number; height: number } | null;
}

interface NormalizedLineItem {
  description: string | null;
  quantity: number | null;
  unit: string | null;
  unit_price: number | null;
  line_total: number | null;
}

interface NormalizedExtraction {
  document_type: string;
  ai_document_type: string;
  supplier_name: string | null;
  document_number: string | null;
  document_date: string | null;
  document_date_raw: string | null;
  raw_text: string | null;
  line_items: NormalizedLineItem[];
  subtotal: number | null;
  tax_rate: number | null;
  tax_amount: number | null;
  total_amount: number | null;
  currency: string;
  notes: string | null;
  confidence: string | null;
  type_classification_source?: string;
  type_classifier_confidence?: string | null;
}

interface OpenRouterChatResponse extends JsonObject {
  choices?: Array<{
    finish_reason?: unknown;
    message?: {
      content?: unknown;
    };
  }>;
}

interface JsonParseFailureDebug {
  responsePreview: string;
  responseLength: number;
  repairAttempted: boolean;
  repairSucceeded: boolean;
  finishReason: string | null;
  contentType: string;
}

class JsonParseFailureError extends Error {
  constructor(
    message: string,
    public readonly debug: JsonParseFailureDebug,
  ) {
    super(message);
    this.name = "JsonParseFailureError";
  }
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: jsonHeaders });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const authHeader = req.headers.get("Authorization");

  if (!authHeader) {
    return jsonResponse({ error: "Missing authorization" }, 401);
  }

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });

  const {
    data: { user },
    error: userError,
  } = await userClient.auth.getUser();

  if (userError || !user) {
    return jsonResponse({ error: "Invalid or expired token" }, 401);
  }

  let documentId: string | undefined;
  let companyId: string | undefined;
  let serviceClient: SupabaseEdgeClient | undefined;

  try {
    const body = await readProcessDocumentRequest(req);
    documentId = body.documentId;

    logInfo(`[process-document] START doc=${documentId ?? "MISSING"}`);

    const { data: accessCheck, error: accessError } = await userClient
      .from("documents")
      .select(
        "id, company_id, file_path, rendered_image_url, file_url, currency, ocr_raw_data",
      )
      .eq("id", documentId)
      .maybeSingle<DocumentAccessRow>();

    if (accessError || !accessCheck) {
      return jsonResponse(
        { error: "Document not found or access denied" },
        403,
      );
    }

    const authorizedCompanyId = accessCheck.company_id;
    companyId = authorizedCompanyId;

    const rateLimit = checkRateLimit({
      key: rateLimitKey("process-document", user.id, authorizedCompanyId),
      limit: RATE_LIMIT_MAX_REQUESTS,
      windowMs: RATE_LIMIT_WINDOW_MS,
    });
    if (!rateLimit.allowed) {
      recordAuditEventDeferred(userClient, {
        companyId: authorizedCompanyId,
        action: "security.ai.process_document",
        entityType: "document",
        entityId: documentId,
        outcome: "denied",
        metadata: { reason: "rate_limited" },
      });
      return rateLimitResponse(rateLimit.retryAfterSeconds, jsonHeaders);
    }

    const currency = firstNonEmptyString(accessCheck.currency)?.toUpperCase() ??
      "EUR";
    serviceClient = createClient<any, "public", any>(
      supabaseUrl,
      serviceRoleKey,
    );

    const imageSources = await resolveDocumentImageSources({
      serviceClient,
      documentId,
      companyId: authorizedCompanyId,
      accessCheck,
    });

    if (imageSources.length === 0) {
      await markFlagged(
        serviceClient,
        documentId,
        authorizedCompanyId,
        "imageUrl missing. PDF render or image handoff failed.",
      );
      return jsonResponse({ error: "imageUrl is required" }, 400);
    }

    if (imageSources.length > MAX_IMAGES_PER_DOCUMENT) {
      throw new HttpError(
        413,
        `Too many document images (${imageSources.length}); maximum ${MAX_IMAGES_PER_DOCUMENT} pages are supported per extraction`,
      );
    }

    logInfo(
      `[process-document] authorized doc=${documentId} company=${companyId} pages=${imageSources.length}`,
    );
    recordAuditEventDeferred(userClient, {
      companyId: authorizedCompanyId,
      action: "security.ai.process_document",
      entityType: "document",
      entityId: documentId,
      outcome: "success",
      metadata: { model: MODEL, stage: "requested" },
    });

    const targetDocumentId = documentId;
    const targetServiceClient = serviceClient;

    const runExtraction = () =>
      runDocumentExtraction({
        serviceClient: targetServiceClient,
        supabaseUrl,
        anonKey,
        authHeader,
        documentId: targetDocumentId,
        companyId: authorizedCompanyId,
        currency,
        imageSources,
      });

    const queued = runInBackground(
      `process-document:${documentId}`,
      () =>
        runExtraction().catch(async (error) => {
          await handleDocumentProcessingFailure({
            error,
            documentId: targetDocumentId,
            companyId: authorizedCompanyId,
            serviceClient: targetServiceClient,
            userClient,
          });
        }),
    );

    if (queued) {
      return jsonResponse(
        {
          success: true,
          accepted: true,
          documentId: targetDocumentId,
        },
        202,
      );
    }

    const result = await runExtraction();
    return jsonResponse(
      {
        success: true,
        documentId: targetDocumentId,
        supplier: result.supplier,
      },
      200,
    );
  } catch (error) {
    const result = await handleDocumentProcessingFailure({
      error,
      documentId,
      companyId,
      serviceClient,
      userClient,
    });

    return jsonResponse(result.body, result.status);
  }
});

function jsonResponse(body: Record<string, unknown>, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: jsonHeaders,
  });
}

async function runDocumentExtraction({
  serviceClient,
  supabaseUrl,
  anonKey,
  authHeader,
  documentId,
  companyId,
  currency,
  imageSources,
}: {
  serviceClient: SupabaseEdgeClient;
  supabaseUrl: string;
  anonKey: string;
  authHeader: string;
  documentId: string;
  companyId: string;
  currency: string;
  imageSources: DocumentImageSource[];
}): Promise<{ supplier: string | null }> {
  const preparedImages: PreparedDocumentImage[] = [];
  for (const imageSource of imageSources) {
    const fetchedImage = await fetchImageBytes(imageSource.url);
    const imageBytes = fetchedImage.bytes;
    const imageMime = detectImageMime(
      imageSource.url,
      fetchedImage.contentType,
    );
    const base64 = encodeBase64(toArrayBuffer(imageBytes));
    const dimensions = detectImageDimensions(imageBytes, imageMime);

    preparedImages.push({
      ...imageSource,
      dataUrl: `data:${imageMime};base64,${base64}`,
      mime: imageMime,
      bytes: imageBytes.byteLength,
      base64Chars: base64.length,
      dimensions,
    });

    logInfo(
      `[process-document] page=${imageSource.pageNumber} source=${imageSource.source} mime=${imageMime} bytes=${imageBytes.byteLength} base64_chars=${base64.length} dimensions=${
        formatDimensions(dimensions)
      }`,
    );
  }

  const apiKey = Deno.env.get("OPENROUTER_API_KEY");
  if (!apiKey) {
    throw new Error("OPENROUTER_API_KEY not configured");
  }

  const extractionResult = await extractFromPreparedImages({
    preparedImages,
    currency,
    apiKey,
  });
  const extraction = extractionResult.extraction;
  const openRouterJson = extractionResult.rawResponse;

  const cleanExtraction = normalizeExtraction(extraction, currency);
  const resolvedType = await resolveDocumentType({
    apiKey,
    aiType: cleanExtraction.ai_document_type,
    confidence: cleanExtraction.confidence,
    rawText: cleanExtraction.raw_text,
  });
  cleanExtraction.document_type = resolvedType.documentType;
  cleanExtraction.type_classification_source = resolvedType.source;
  cleanExtraction.type_classifier_confidence = resolvedType.confidence;

  logInfo(
    `[process-document][type] ai=${
      cleanExtraction.ai_document_type ?? "unknown"
    } final=${resolvedType.documentType} source=${resolvedType.source}`,
  );

  const validLineItemRows = Array.isArray(cleanExtraction.line_items)
    ? cleanExtraction.line_items
      .filter((item) =>
        typeof item.description === "string" &&
        item.description.trim().length > 0
      )
      .map((item) => ({
        company_id: companyId,
        document_id: documentId,
        description: item.description,
        quantity: item.quantity,
        unit_type: item.unit,
        unit_price: item.unit_price,
        line_total: item.line_total,
      }))
    : [];

  const { error: deleteItemsError } = await serviceClient
    .from("document_items")
    .delete()
    .eq("document_id", documentId)
    .eq("company_id", companyId);

  if (deleteItemsError) {
    throw new Error(
      `Failed to clear previous document items: ${deleteItemsError.message}`,
    );
  }

  if (validLineItemRows.length === 0) {
    await markFlagged(
      serviceClient,
      documentId,
      companyId,
      "No line items extracted from PDF pages.",
    );
    logWarn(`[process-document] no line items extracted doc=${documentId}`);
    return { supplier: nullableString(cleanExtraction.supplier_name) };
  }

  const { error: insertItemsError } = await serviceClient
    .from("document_items")
    .insert(validLineItemRows);

  if (insertItemsError) {
    throw new Error(
      `Failed to save document items: ${insertItemsError.message}`,
    );
  }

  const { error: updateDocumentError } = await serviceClient
    .from("documents")
    .update({
      status: "completed",
      ocr_status: "completed",
      document_type: cleanExtraction.document_type ?? "unknown",
      document_number: cleanExtraction.document_number,
      document_date: cleanExtraction.document_date,
      subtotal: cleanExtraction.subtotal,
      tax_amount: cleanExtraction.tax_amount,
      total_amount: cleanExtraction.total_amount,
      currency: cleanExtraction.currency ?? currency,
      extraction_raw: openRouterJson,
      extraction_clean: cleanExtraction,
      notes: null,
    })
    .eq("id", documentId)
    .eq("company_id", companyId);

  if (updateDocumentError) {
    throw new Error(
      `Failed to finalize document extraction: ${updateDocumentError.message}`,
    );
  }

  logInfo(`[process-document] DONE doc=${documentId}`);

  runInBackground(
    `recognize-products:${documentId}`,
    () =>
      invokeRecognizeProducts({
        supabaseUrl,
        anonKey,
        authHeader,
        documentId,
      }),
  );

  return { supplier: nullableString(cleanExtraction.supplier_name) };
}

async function extractFromPreparedImages({
  preparedImages,
  currency,
  apiKey,
}: {
  preparedImages: PreparedDocumentImage[];
  currency: string;
  apiKey: string;
}): Promise<{ extraction: Record<string, unknown>; rawResponse: unknown }> {
  if (preparedImages.length <= MAX_IMAGES_PER_REQUEST) {
    return extractPreparedImageBatch({
      preparedImages,
      currency,
      apiKey,
      batchIndex: 0,
      batchCount: 1,
    });
  }

  const batchResults: Array<{
    extraction: Record<string, unknown>;
    rawResponse: unknown;
    pageNumbers: number[];
  }> = [];
  const batchCount = Math.ceil(preparedImages.length / MAX_IMAGES_PER_REQUEST);

  for (
    let index = 0;
    index < preparedImages.length;
    index += MAX_IMAGES_PER_REQUEST
  ) {
    const batch = preparedImages.slice(index, index + MAX_IMAGES_PER_REQUEST);
    const result = await extractPreparedImageBatch({
      preparedImages: batch,
      currency,
      apiKey,
      batchIndex: batchResults.length,
      batchCount,
    });

    batchResults.push({
      ...result,
      pageNumbers: batch.map((image) => image.pageNumber),
    });
  }

  return {
    extraction: mergeExtractionBatches(
      batchResults.map((result) => result.extraction),
      currency,
    ),
    rawResponse: {
      batched: true,
      batch_count: batchResults.length,
      batches: batchResults.map((result, index) => ({
        batch_number: index + 1,
        page_numbers: result.pageNumbers,
        response: result.rawResponse,
      })),
    },
  };
}

async function extractPreparedImageBatch({
  preparedImages,
  currency,
  apiKey,
  batchIndex,
  batchCount,
}: {
  preparedImages: PreparedDocumentImage[];
  currency: string;
  apiKey: string;
  batchIndex: number;
  batchCount: number;
}): Promise<{ extraction: Record<string, unknown>; rawResponse: unknown }> {
  const pageNumbers = preparedImages.map((image) => image.pageNumber).join(",");
  const prompt = batchCount > 1
    ? `${
      extractionPrompt(currency, preparedImages.length)
    }\n\nBatch context: this is batch ${
      batchIndex + 1
    } of ${batchCount}, containing page numbers ${pageNumbers}. Extract only what is visible in these pages; totals are usually on the last document page.`
    : extractionPrompt(currency, preparedImages.length);

  const openRouterContent = [
    ...preparedImages.map((image) => ({
      type: "image_url",
      image_url: { url: image.dataUrl },
    })),
    {
      type: "text",
      text: prompt,
    },
  ];
  const contentBlockTypes = openRouterContent.map((block) => block.type).join(
    ",",
  );

  const openRouterRequest = {
    model: MODEL,
    messages: [
      {
        role: "user",
        content: openRouterContent,
      },
    ],
    max_tokens: OPENROUTER_MAX_TOKENS,
    temperature: 0.05,
    reasoning: { exclude: true, effort: "minimal" },
    include_reasoning: false,
  };
  const openRouterPayload = JSON.stringify(openRouterRequest);

  logInfo(
    `[process-document] Calling OpenRouter model=${MODEL} batch=${
      batchIndex + 1
    }/${batchCount} pages=${preparedImages.length} page_numbers=${pageNumbers} content_blocks=${contentBlockTypes} payload_chars=${openRouterPayload.length} max_tokens=${OPENROUTER_MAX_TOKENS}`,
  );

  const openRouterController = new AbortController();
  const openRouterTimeoutId = setTimeout(
    () => openRouterController.abort(),
    OPENROUTER_REQUEST_TIMEOUT_MS,
  );

  let openRouterResponse: Response;
  try {
    openRouterResponse = await fetch(OPENROUTER_ENDPOINT, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
        "HTTP-Referer": "https://hospidash.app",
        "X-Title": "HospiDash Document Extraction",
      },
      body: openRouterPayload,
      signal: openRouterController.signal,
    });
  } catch (error) {
    if ((error as { name?: string })?.name === "AbortError") {
      throw new Error(
        `OpenRouter request timed out after ${OPENROUTER_REQUEST_TIMEOUT_MS}ms`,
      );
    }
    throw error;
  } finally {
    clearTimeout(openRouterTimeoutId);
  }

  logInfo(`[process-document] OpenRouter status=${openRouterResponse.status}`);

  if (!openRouterResponse.ok) {
    const errorBody = await readOpenRouterErrorBody(openRouterResponse);
    const errorDetails = parseOpenRouterErrorDetails(errorBody);
    logError(
      `[process-document] OpenRouter error status=${openRouterResponse.status} status_text=${openRouterResponse.statusText} model=${MODEL} code=${
        errorDetails.code ?? "unknown"
      } message=${errorDetails.message ?? "unknown"} provider=${
        errorDetails.providerName ?? "unknown"
      } request_id=${errorDetails.requestId ?? "unknown"} provider_message=${
        errorDetails.providerMessage ?? "none"
      } pages=${preparedImages.length} content_blocks=${contentBlockTypes} payload_chars=${openRouterPayload.length} image_bytes=${
        sumPreparedImageBytes(preparedImages)
      } image_base64_chars=${
        sumPreparedImageBase64Chars(preparedImages)
      } body=${truncateForLog(errorBody, MAX_OPENROUTER_ERROR_BODY_CHARS)}`,
    );
    throw new Error(
      `OpenRouter error ${openRouterResponse.status}: ${
        errorDetails.message ?? extractOpenRouterErrorMessage(errorBody)
      }`,
    );
  }

  const openRouterJson = await openRouterResponse
    .json() as OpenRouterChatResponse;
  const choice = openRouterJson?.choices?.[0];
  const assistantContent = choice?.message?.content;
  const finishReason = nullableString(choice?.finish_reason);
  const content = extractAssistantTextContent(assistantContent);
  const extraction = parseExtraction(content);

  if (!extraction) {
    const parseDebug = buildJsonParseFailureDebug({
      content,
      assistantContent,
      finishReason,
    });
    logWarn(
      `[process-document] unparseable extraction model=${MODEL} finish_reason=${
        finishReason ?? "unknown"
      } content_type=${parseDebug.contentType} response_length=${parseDebug.responseLength} preview=${parseDebug.responsePreview}`,
    );
    throw new JsonParseFailureError(
      "Could not parse extraction JSON",
      parseDebug,
    );
  }

  return { extraction, rawResponse: openRouterJson };
}

function mergeExtractionBatches(
  extractions: Record<string, unknown>[],
  fallbackCurrency: string,
): Record<string, unknown> {
  const normalized = extractions.map(normalizeExtractionAliases);
  const lineItems = dedupeLineItems(
    normalized.flatMap((extraction) =>
      Array.isArray(extraction.line_items) ? extraction.line_items : []
    ),
  );

  return {
    document_type:
      firstNonEmptyString(...normalized.map((item) => item.document_type)) ??
        "unknown",
    supplier_name:
      firstNonEmptyString(...normalized.map((item) => item.supplier_name)) ??
        null,
    document_number:
      firstNonEmptyString(...normalized.map((item) => item.document_number)) ??
        null,
    document_date:
      lastNonEmptyString(normalized.map((item) => item.document_date)) ?? null,
    document_date_raw:
      lastNonEmptyString(normalized.map((item) => item.document_date_raw)) ??
        null,
    raw_text: firstNonEmptyString(...normalized.map((item) => item.raw_text)) ??
      null,
    line_items: lineItems,
    subtotal: lastPresentValue(normalized.map((item) => item.subtotal)) ?? null,
    tax_rate: lastPresentValue(normalized.map((item) => item.tax_rate)) ?? null,
    tax_amount: lastPresentValue(normalized.map((item) => item.tax_amount)) ??
      null,
    total_amount:
      lastPresentValue(normalized.map((item) => item.total_amount)) ?? null,
    currency: firstNonEmptyString(...normalized.map((item) => item.currency)) ??
      fallbackCurrency,
    notes: firstNonEmptyString(...normalized.map((item) => item.notes)) ?? null,
    confidence: mergeConfidence(
      normalized.map((item) => nullableString(item.confidence)),
    ),
  };
}

function dedupeLineItems(items: unknown[]): unknown[] {
  const seen = new Set<string>();
  const result: unknown[] = [];

  for (const item of items) {
    if (item === null || typeof item !== "object" || Array.isArray(item)) {
      continue;
    }
    const row = item as JsonObject;
    const description = nullableString(row.description);
    if (!description) continue;

    const key = [
      description.toLowerCase().replace(/\s+/g, " ").trim(),
      String(row.quantity ?? ""),
      String(row.line_total ?? ""),
    ].join("|");

    if (seen.has(key)) continue;
    seen.add(key);
    result.push(row);
  }

  return result;
}

function lastNonEmptyString(values: unknown[]): string | undefined {
  for (let index = values.length - 1; index >= 0; index--) {
    const value = nullableString(values[index]);
    if (value) return value;
  }
  return undefined;
}

function lastPresentValue(values: unknown[]): unknown {
  for (let index = values.length - 1; index >= 0; index--) {
    if (values[index] !== null && values[index] !== undefined) {
      return values[index];
    }
  }
  return null;
}

function mergeConfidence(values: Array<string | null>): string {
  if (values.includes("low")) return "low";
  if (values.includes("medium")) return "medium";
  if (values.includes("high")) return "high";
  return "medium";
}

async function handleDocumentProcessingFailure({
  error,
  documentId,
  companyId,
  serviceClient,
  userClient,
}: {
  error: unknown;
  documentId: string | undefined;
  companyId: string | undefined;
  serviceClient: SupabaseEdgeClient | undefined;
  userClient: SupabaseEdgeClient;
}): Promise<{ body: Record<string, unknown>; status: number }> {
  const message = error instanceof Error ? error.message : String(error);
  logError(`[process-document] ERROR: ${message}`);

  if (documentId && companyId && serviceClient) {
    const flaggedReason = error instanceof JsonParseFailureError
      ? buildJsonParseFailureNote(error.debug)
      : `Extraction error: ${message}`;

    await markFlagged(serviceClient, documentId, companyId, flaggedReason);

    await recordAuditEvent(userClient, {
      companyId,
      action: "security.ai.process_document",
      entityType: "document",
      entityId: documentId,
      outcome: "failure",
      metadata: {
        error_code: error instanceof HttpError
          ? error.status
          : "processing_failed",
      },
    });
  }

  if (error instanceof JsonParseFailureError) {
    return {
      body: {
        error: "json_parse_failed",
        message,
        debug: error.debug,
      },
      status: 500,
    };
  }

  return {
    body: { error: message },
    status: error instanceof HttpError ? error.status : 500,
  };
}

function runInBackground(label: string, task: () => Promise<unknown>): boolean {
  const edgeRuntime = (globalThis as {
    EdgeRuntime?: { waitUntil?: (promise: Promise<unknown>) => void };
  }).EdgeRuntime;

  if (!edgeRuntime?.waitUntil) return false;

  edgeRuntime.waitUntil(
    task().catch((error) => {
      const message = error instanceof Error ? error.message : String(error);
      logWarn(`[${label}] background task failed: ${message}`);
    }),
  );
  return true;
}

async function invokeRecognizeProducts({
  supabaseUrl,
  anonKey,
  authHeader,
  documentId,
}: {
  supabaseUrl: string;
  anonKey: string;
  authHeader: string;
  documentId: string;
}): Promise<void> {
  try {
    const response = await fetch(
      `${supabaseUrl}/functions/v1/recognize-products`,
      {
        method: "POST",
        headers: {
          Authorization: authHeader,
          apikey: anonKey,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ document_id: documentId }),
      },
    );

    if (!response.ok) {
      const body = await readOpenRouterErrorBody(response);
      logWarn(
        `[process-document] recognize-products returned status=${response.status} body=${
          truncateForLog(body, 500)
        }`,
      );
    }
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    logWarn(`[process-document] recognize-products invoke failed: ${message}`);
  }
}

function firstNonEmptyString(...values: unknown[]): string | undefined {
  for (const value of values) {
    if (typeof value === "string" && value.trim().length > 0) {
      return value.trim();
    }
  }
  return undefined;
}

function toArrayBuffer(bytes: Uint8Array): ArrayBuffer {
  const buffer = new ArrayBuffer(bytes.byteLength);
  new Uint8Array(buffer).set(bytes);
  return buffer;
}

async function readProcessDocumentRequest(
  req: Request,
): Promise<ProcessDocumentRequest> {
  const body = await readJsonObject(req, {
    maxBytes: MAX_JSON_BYTES,
    allowedFields: ["documentId"],
  });
  return {
    documentId: requireStringField(body, "documentId", { maxLength: 80 }),
  };
}

async function fetchImageBytes(
  imageUrl: string,
): Promise<{ bytes: Uint8Array; contentType: string | null }> {
  const controller = new AbortController();
  const timeoutId = setTimeout(
    () => controller.abort(),
    IMAGE_FETCH_TIMEOUT_MS,
  );

  try {
    const response = await fetch(imageUrl, { signal: controller.signal });
    if (!response.ok) {
      throw new Error(`Image fetch failed: ${response.status}`);
    }

    const contentLength = response.headers.get("content-length");
    if (contentLength) {
      const expectedBytes = Number.parseInt(contentLength, 10);
      if (Number.isFinite(expectedBytes) && expectedBytes > MAX_IMAGE_BYTES) {
        throw new HttpError(413, "Image exceeds maximum allowed size");
      }
    }

    return {
      bytes: await readResponseBytes(response, MAX_IMAGE_BYTES),
      contentType: response.headers.get("content-type"),
    };
  } catch (error) {
    if (error instanceof DOMException && error.name === "AbortError") {
      throw new HttpError(408, "Image fetch timed out");
    }
    throw error;
  } finally {
    clearTimeout(timeoutId);
  }
}

async function readResponseBytes(
  response: Response,
  maxBytes: number,
): Promise<Uint8Array> {
  if (!response.body) {
    throw new Error("Image response body is empty");
  }

  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let totalBytes = 0;

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    if (!value) continue;

    totalBytes += value.byteLength;
    if (totalBytes > maxBytes) {
      await reader.cancel();
      throw new HttpError(413, "Image exceeds maximum allowed size");
    }

    chunks.push(value);
  }

  const bytes = new Uint8Array(totalBytes);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }

  return bytes;
}

async function markFlagged(
  supabase: SupabaseEdgeClient,
  documentId: string,
  companyId: string,
  reason: string,
): Promise<void> {
  const { error } = await supabase
    .from("documents")
    .update({
      status: "flagged",
      ocr_status: "failed",
      notes: reason,
    })
    .eq("id", documentId)
    .eq("company_id", companyId);

  if (error) {
    logError(`[process-document] Failed to mark flagged: ${error.message}`);
  }
}

function detectImageMime(imageUrl: string, contentType: string | null): string {
  if (contentType && contentType.startsWith("image/")) {
    return contentType;
  }

  const normalized = imageUrl.toLowerCase();
  if (normalized.includes(".png")) return "image/png";
  if (normalized.includes(".webp")) return "image/webp";
  return "image/jpeg";
}

async function resolveDocumentImageSources({
  serviceClient,
  documentId,
  companyId,
  accessCheck,
}: {
  serviceClient: SupabaseEdgeClient;
  documentId: string;
  companyId: string;
  accessCheck: DocumentAccessRow;
}): Promise<DocumentImageSource[]> {
  const pagePaths = extractDocumentPagePaths(
    accessCheck.ocr_raw_data,
    companyId,
    documentId,
  );

  if (pagePaths.length > 0) {
    const signedSources: DocumentImageSource[] = [];
    for (const page of pagePaths) {
      const { data, error } = await serviceClient.storage
        .from("documents")
        .createSignedUrl(page.path, 900);

      if (error || !data?.signedUrl) {
        logWarn(
          `[process-document] failed to sign page path page=${page.pageNumber} path=${page.path} error=${
            error?.message ?? "missing signed URL"
          }`,
        );
        continue;
      }

      signedSources.push({
        url: data.signedUrl,
        pageNumber: page.pageNumber,
        source: "path",
      });
    }

    if (signedSources.length > 0) return signedSources;
  }

  const directPath = firstNonEmptyString(accessCheck.file_path);
  if (
    directPath &&
    !directPath.toLowerCase().endsWith(".pdf") &&
    isSafeDocumentStoragePath(directPath, companyId, documentId)
  ) {
    const { data, error } = await serviceClient.storage
      .from("documents")
      .createSignedUrl(directPath, 900);

    if (error || !data?.signedUrl) {
      logWarn(
        `[process-document] failed to sign direct file path path=${directPath} error=${
          error?.message ?? "missing signed URL"
        }`,
      );
    } else {
      return [{ url: data.signedUrl, pageNumber: 1, source: "path" }];
    }
  }

  const pageUrls = extractDocumentPageUrls(accessCheck.ocr_raw_data);
  if (pageUrls.length > 0) {
    logInfo(
      `[process-document] using legacy page URL fallback doc=${documentId} pages=${pageUrls.length}`,
    );
    return pageUrls;
  }

  const imageUrl = firstNonEmptyString(
    accessCheck.rendered_image_url,
    accessCheck.file_url,
  );

  if (imageUrl) {
    const fallbackSource = accessCheck.rendered_image_url
      ? "rendered_image_url"
      : "file_url";
    logInfo(
      `[process-document] using legacy single-image URL fallback doc=${documentId} source=${fallbackSource}`,
    );
  }

  return imageUrl ? [{ url: imageUrl, pageNumber: 1, source: "single" }] : [];
}

function extractDocumentPagePaths(
  rawData: unknown,
  companyId: string,
  documentId: string,
): Array<{ path: string; pageNumber: number }> {
  return readPageEntries(rawData)
    .map((entry, index) => ({
      path: firstNonEmptyString(entry.file_path, entry.path) ?? "",
      pageNumber: readPageNumber(entry.page_number, index),
    }))
    .filter((entry) =>
      isSafeDocumentStoragePath(entry.path, companyId, documentId)
    )
    .sort((a, b) => a.pageNumber - b.pageNumber);
}

function extractDocumentPageUrls(rawData: unknown): DocumentImageSource[] {
  return readPageEntries(rawData)
    .map((entry, index) => ({
      url: firstNonEmptyString(entry.file_url, entry.url) ?? "",
      pageNumber: readPageNumber(entry.page_number, index),
      source: "url" as const,
    }))
    .filter((entry) => entry.url.length > 0)
    .sort((a, b) => a.pageNumber - b.pageNumber);
}

function readPageEntries(rawData: unknown): JsonObject[] {
  if (
    rawData === null || typeof rawData !== "object" || Array.isArray(rawData)
  ) {
    return [];
  }

  const pages = (rawData as JsonObject).pages;
  if (!Array.isArray(pages)) return [];

  return pages.filter(
    (page): page is JsonObject =>
      page !== null && typeof page === "object" && !Array.isArray(page),
  );
}

function readPageNumber(value: unknown, index: number): number {
  if (typeof value === "number" && Number.isFinite(value) && value > 0) {
    return Math.floor(value);
  }
  return index + 1;
}

function isSafeDocumentStoragePath(
  path: string,
  companyId: string,
  documentId: string,
): boolean {
  return path.startsWith(`${companyId}/${documentId}/`) && !path.includes("..");
}

function detectImageDimensions(
  bytes: Uint8Array,
  mime: string,
): { width: number; height: number } | null {
  if (mime === "image/png") return detectPngDimensions(bytes);
  if (mime === "image/jpeg" || mime === "image/jpg") {
    return detectJpegDimensions(bytes);
  }
  return null;
}

function detectPngDimensions(
  bytes: Uint8Array,
): { width: number; height: number } | null {
  if (bytes.byteLength < 24) return null;
  const pngSignature = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
  if (!pngSignature.every((byte, index) => bytes[index] === byte)) return null;

  return {
    width: readUint32(bytes, 16),
    height: readUint32(bytes, 20),
  };
}

function detectJpegDimensions(
  bytes: Uint8Array,
): { width: number; height: number } | null {
  if (bytes.byteLength < 4 || bytes[0] !== 0xff || bytes[1] !== 0xd8) {
    return null;
  }

  let offset = 2;
  while (offset + 9 < bytes.byteLength) {
    if (bytes[offset] !== 0xff) {
      offset++;
      continue;
    }

    const marker = bytes[offset + 1];
    const length = readUint16(bytes, offset + 2);
    if (length < 2 || offset + 2 + length > bytes.byteLength) return null;

    if (isJpegStartOfFrame(marker)) {
      return {
        height: readUint16(bytes, offset + 5),
        width: readUint16(bytes, offset + 7),
      };
    }

    offset += 2 + length;
  }

  return null;
}

function isJpegStartOfFrame(marker: number): boolean {
  return (
    marker >= 0xc0 &&
    marker <= 0xcf &&
    marker !== 0xc4 &&
    marker !== 0xc8 &&
    marker !== 0xcc
  );
}

function readUint16(bytes: Uint8Array, offset: number): number {
  return (bytes[offset] << 8) | bytes[offset + 1];
}

function readUint32(bytes: Uint8Array, offset: number): number {
  return (
    (bytes[offset] * 0x1000000) +
    ((bytes[offset + 1] << 16) | (bytes[offset + 2] << 8) | bytes[offset + 3])
  );
}

function formatDimensions(
  dimensions: { width: number; height: number } | null,
): string {
  return dimensions ? `${dimensions.width}x${dimensions.height}` : "unknown";
}

async function readOpenRouterErrorBody(response: Response): Promise<string> {
  try {
    return await response.text();
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return `Could not read OpenRouter error body: ${message}`;
  }
}

function parseOpenRouterErrorDetails(body: string): {
  code: string | null;
  message: string | null;
  providerMessage: string | null;
  providerName: string | null;
  requestId: string | null;
} {
  try {
    const parsed = JSON.parse(body) as JsonObject;
    const error = parsed.error;
    if (!error || typeof error !== "object" || Array.isArray(error)) {
      return emptyOpenRouterErrorDetails();
    }

    const object = error as JsonObject;
    const metadata = object.metadata;
    const metadataObject =
      metadata && typeof metadata === "object" && !Array.isArray(metadata)
        ? metadata as JsonObject
        : {};

    return {
      code: nullableLogString(object.code),
      message: nullableLogString(object.message),
      providerMessage: nullableLogString(metadataObject.raw),
      providerName: nullableLogString(metadataObject.provider_name),
      requestId: nullableLogString(metadataObject.request_id ?? parsed.id),
    };
  } catch (_) {
    return emptyOpenRouterErrorDetails();
  }
}

function emptyOpenRouterErrorDetails(): {
  code: string | null;
  message: string | null;
  providerMessage: string | null;
  providerName: string | null;
  requestId: string | null;
} {
  return {
    code: null,
    message: null,
    providerMessage: null,
    providerName: null,
    requestId: null,
  };
}

function nullableLogString(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.replace(/\s+/g, " ").trim();
  return trimmed.length > 0 ? truncateForLog(trimmed, 500) : null;
}

function sumPreparedImageBytes(images: PreparedDocumentImage[]): number {
  return images.reduce((sum, image) => sum + image.bytes, 0);
}

function sumPreparedImageBase64Chars(images: PreparedDocumentImage[]): number {
  return images.reduce((sum, image) => sum + image.base64Chars, 0);
}

function extractOpenRouterErrorMessage(body: string): string {
  try {
    const parsed = JSON.parse(body) as JsonObject;
    const error = parsed.error;
    if (error && typeof error === "object" && !Array.isArray(error)) {
      const object = error as JsonObject;
      const message = firstNonEmptyString(object.message, object.code);
      if (message) return truncateForLog(message, 500);
    }
  } catch (_) {
    // Fall through to plain text body.
  }

  return truncateForLog(body.replace(/\s+/g, " ").trim(), 500) ||
    "no response body";
}

function truncateForLog(value: string, maxChars: number): string {
  if (value.length <= maxChars) return value;
  return `${value.slice(0, maxChars)}...`;
}

function extractionPrompt(currency: string, imageCount = 1): string {
  const pageContext = imageCount > 1
    ? `You are analyzing ONE hospitality document split across ${imageCount} images/pages.`
    : "You are analyzing one hospitality document image.";

  return `${pageContext}

You are an OCR and structured-extraction engine for hospitality documents in Spain.
Do not reason. Do not explain. Do not describe the image. Return ONLY one JSON object.

Classify document_type using these rules:
- "invoice" (Factura): contains "Factura"/"Invoice", VAT (IVA) breakdown, "Total", "Base imponible", "IVA", or fiscal/tax info.
- "delivery_note" (Albaran): contains "Albaran"/"Delivery Note". Usually no VAT breakdown.
- "expense_ticket" (Ticket): small receipt, payment method, often POS.
- "unknown": only if none of the above match.

Hard rules:
- Treat all provided images/pages as ONE document.
- If "Albaran" or "Albarán" appears anywhere, document_type = "delivery_note".
- If a VAT breakdown exists, document_type = "invoice".
- Supplier usually appears on the first page; totals usually on the last page.
- Merge line items across pages. Do not duplicate products.
- If a field is not present, use null. If there are no line items, use [].

Then extract structured data from this document.
Return ONLY a valid JSON object with no markdown and no explanation.

OUTPUT BUDGET RULES (critical):
- Always emit a complete, valid, closed JSON object.
- Emit metadata fields and totals FIRST, then "line_items" LAST.
- If the document has many products and you are running low on space,
  prefer returning fewer line_items over producing invalid or truncated JSON.
- A valid partial extraction is better than invalid JSON.
- "raw_text" must be a SHORT header excerpt only (max ~200 chars), or null.
  Do NOT dump the full OCR text. Line items already capture the products.

{
  "document_type": "invoice"|"delivery_note"|"expense_ticket"|"unknown",
  "supplier_name": "string or null",
  "document_number": "string or null",
  "document_date": "YYYY-MM-DD or null",
  "document_date_raw": "exact visible date text or null",
  "raw_text": "short header excerpt (<=200 chars) or null",
  "line_items": [
    {
      "description": "string",
      "quantity": number or null,
      "unit": "string or null",
      "unit_price": number or null,
      "line_total": number or null
    }
  ],
  "subtotal": number or null,
  "tax_rate": number or null,
  "tax_amount": number or null,
  "total_amount": number or null,
  "currency": "ISO 4217 or null",
  "notes": "string or null",
  "confidence": "high"|"medium"|"low"
}

Date rules:
- If the visible document shows a short numeric date like 08-05-26, 08/05/26, or 08.05.26, that means day-month-year and must normalize to 2026-05-08.
- Always copy the exact visible date text into document_date_raw.
- Prefer the visible printed document date, not the upload date or current date.

Default currency if not visible: ${currency}
European invoice rules (critical):
- Spanish and European invoices often use comma decimals.
- Preserve the exact visible decimal meaning for all quantities and monetary values.
- Example: "808,16€" must become 808.16.
- Example: "1.506,21" must become 1506.21.
- Example: "34,1700" is a money value and must become 34.17.
- Example: quantity "6,828" must remain 6.828, not 6828.
- Example: quantity "1,000" must remain 1, not 1000.
- Never remove a decimal separator as if it were a thousands separator.

Return ONLY the JSON.`;
}

function buildJsonParseFailureDebug({
  content,
  assistantContent,
  finishReason,
}: {
  content: string;
  assistantContent: unknown;
  finishReason: string | null;
}): JsonParseFailureDebug {
  return {
    responsePreview: sanitizeAiPreview(content, 280),
    responseLength: content.length,
    repairAttempted: false,
    repairSucceeded: false,
    finishReason,
    contentType: describeContentType(assistantContent),
  };
}

function buildJsonParseFailureNote(debug: JsonParseFailureDebug): string {
  return truncateForLog(
    `Could not parse extraction JSON. AI response preview: ${debug.responsePreview}`,
    500,
  );
}

function sanitizeAiPreview(content: string, maxChars: number): string {
  let sanitized = redact(content)
    .replace(/\s+/g, " ")
    .trim();

  sanitized = sanitized
    .replace(/(:\s*)"([^"\\]*(?:\\.[^"\\]*)*)"/g, '$1"[REDACTED_TEXT]"')
    .replace(/(:\s*)-?\d+(?:\.\d+)?/g, "$10");

  return truncateForLog(sanitized, maxChars);
}

function parseExtraction(content: string): Record<string, unknown> | null {
  let cleaned = content
    .replace(/^[\uFEFF\u200B\u200C\u200D]+/, "")
    .trim();

  const codeBlockMatch = cleaned.match(/```(?:json)?\s*([\s\S]*?)\s*```/i);
  if (codeBlockMatch) {
    cleaned = codeBlockMatch[1].trim();
  }

  const jsonCandidate = extractFirstBalancedJsonObject(cleaned);
  if (!jsonCandidate) return null;

  const withoutTrailingCommas = jsonCandidate.replace(/,\s*([\]}])/g, "$1");
  const repairedControlChars = escapeControlCharsInJsonStrings(
    withoutTrailingCommas,
  );

  return parseJsonObject(jsonCandidate) ??
    parseJsonObject(withoutTrailingCommas) ??
    parseJsonObject(repairedControlChars);
}

function extractFirstBalancedJsonObject(content: string): string | null {
  const jsonStart = content.indexOf("{");
  if (jsonStart === -1) return null;

  let braceCount = 0;
  let inString = false;
  let escaped = false;

  for (let index = jsonStart; index < content.length; index++) {
    const char = content[index];

    if (escaped) {
      escaped = false;
      continue;
    }

    if (char === "\\") {
      escaped = inString;
      continue;
    }

    if (char === '"') {
      inString = !inString;
      continue;
    }

    if (inString) continue;

    if (char === "{") braceCount++;
    if (char === "}") {
      braceCount--;
      if (braceCount === 0) {
        return content.substring(jsonStart, index + 1);
      }
    }
  }

  return null;
}

function parseJsonObject(content: string): Record<string, unknown> | null {
  try {
    const parsed = JSON.parse(content) as unknown;
    if (
      parsed !== null && typeof parsed === "object" && !Array.isArray(parsed)
    ) {
      return parsed as Record<string, unknown>;
    }
  } catch {
    // Try the next parser repair candidate.
  }

  return null;
}

function escapeControlCharsInJsonStrings(content: string): string {
  let repaired = "";
  let inString = false;
  let escaped = false;

  for (const char of content) {
    if (escaped) {
      repaired += char;
      escaped = false;
      continue;
    }

    if (char === "\\") {
      repaired += char;
      escaped = inString;
      continue;
    }

    if (char === '"') {
      repaired += char;
      inString = !inString;
      continue;
    }

    if (inString) {
      if (char === "\n") {
        repaired += "\\n";
        continue;
      }
      if (char === "\r") {
        repaired += "\\r";
        continue;
      }
      if (char === "\t") {
        repaired += "\\t";
        continue;
      }
    }

    repaired += char;
  }

  return repaired;
}

function extractAssistantTextContent(content: unknown): string {
  if (typeof content === "string") return content.trim();

  if (Array.isArray(content)) {
    return content
      .map(extractAssistantTextPart)
      .filter((part) => part.length > 0)
      .join("\n")
      .trim();
  }

  return extractAssistantTextPart(content);
}

function extractAssistantTextPart(part: unknown): string {
  if (typeof part === "string") return part.trim();
  if (!part || typeof part !== "object" || Array.isArray(part)) return "";

  const object = part as JsonObject;
  const directText = firstNonEmptyString(
    object.text,
    object.output_text,
    object.content,
  );
  if (directText) return directText;

  const nestedContent = object.content;
  if (Array.isArray(nestedContent)) {
    return nestedContent
      .map((value) => extractAssistantTextPart(value))
      .filter((value) => value.length > 0)
      .join("\n")
      .trim();
  }

  return "";
}

function describeContentType(content: unknown): string {
  if (Array.isArray(content)) return "array";
  if (content === null) return "null";
  return typeof content;
}

function normalizeExtraction(
  extraction: Record<string, unknown>,
  fallbackCurrency: string,
): Record<string, unknown> {
  const normalized = normalizeExtractionAliases(extraction);

  const lineItems = Array.isArray(normalized.line_items)
    ? normalized.line_items
      .filter((item): item is Record<string, unknown> =>
        item !== null && typeof item === "object"
      )
      .map((item) => normalizeLineItem(item))
    : [];

  const lineItemsSubtotal = sumMoney(
    lineItems.map((item) => item.line_total ?? null),
  );

  let subtotal = normalizeDocumentMoneyField({
    field: "subtotal",
    rawValue: normalized.subtotal,
    anchor: lineItemsSubtotal,
  });

  if (subtotal === null && lineItemsSubtotal !== null) {
    subtotal = lineItemsSubtotal;
  }

  let totalAmount = normalizeDocumentMoneyField({
    field: "total_amount",
    rawValue: normalized.total_amount,
    anchor: subtotal ?? lineItemsSubtotal,
  });

  let taxAmount = normalizeDocumentMoneyField({
    field: "tax_amount",
    rawValue: normalized.tax_amount,
    anchor: totalAmount !== null && subtotal !== null
      ? roundMoney(totalAmount - subtotal)
      : null,
  });

  if (subtotal !== null && totalAmount !== null) {
    const derivedTax = roundMoney(totalAmount - subtotal);
    if (
      derivedTax !== null &&
      (taxAmount === null || isImplausibleMoney(taxAmount, derivedTax))
    ) {
      logAmountNormalization({
        field: "tax_amount",
        rawValue: normalized.tax_amount,
        normalizedValue: derivedTax,
        reason: taxAmount === null
          ? "derived_from_total_minus_subtotal"
          : "corrected_from_total_minus_subtotal",
      });
      taxAmount = derivedTax;
    }
  }

  if (subtotal !== null && taxAmount !== null && totalAmount === null) {
    totalAmount = roundMoney(subtotal + taxAmount);
  }

  ({ subtotal, taxAmount, totalAmount } = reconcileDocumentTotals({
    documentType: nullableString(normalized.document_type) ?? "unknown",
    lineItems,
    lineItemsSubtotal,
    rawSubtotal: normalized.subtotal,
    rawTaxAmount: normalized.tax_amount,
    rawTotalAmount: normalized.total_amount,
    subtotal,
    taxAmount,
    totalAmount,
  }));

  return {
    document_type: nullableString(normalized.document_type) ?? "unknown",
    ai_document_type: normalizeDocumentType(
      nullableString(normalized.document_type),
    ),
    supplier_name: nullableString(normalized.supplier_name),
    document_number: nullableString(normalized.document_number),
    document_date: normalizeDate(
      normalized.document_date_raw ?? normalized.document_date,
    ),
    document_date_raw: nullableString(normalized.document_date_raw),
    raw_text: nullableString(normalized.raw_text),
    line_items: lineItems,
    subtotal,
    tax_rate: parseNullableNumber(normalized.tax_rate),
    tax_amount: taxAmount,
    total_amount: totalAmount,
    currency: nullableString(normalized.currency) ?? fallbackCurrency,
    notes: nullableString(normalized.notes),
    confidence: normalizeConfidence(nullableString(normalized.confidence)),
  };
}

function normalizeLineItem(item: Record<string, unknown>): {
  description: string | null;
  quantity: number | null;
  unit: string | null;
  unit_price: number | null;
  line_total: number | null;
} {
  const description = nullableString(item.description);
  const quantityHint = parseQuantityFromDescription(description);
  const parsedQuantity = parseQuantity(item.quantity);
  const quantity = choosePreferredQuantity({
    rawValue: item.quantity,
    description,
    parsedQuantity,
    hintedQuantity: quantityHint,
  });
  const unitPrice = parseMoney(item.unit_price);
  const lineTotal = normalizeLineTotal({
    rawValue: item.line_total,
    quantity,
    unitPrice,
  });

  return {
    description,
    quantity,
    unit: nullableString(item.unit),
    unit_price: unitPrice,
    line_total: lineTotal,
  };
}

function choosePreferredQuantity({
  rawValue,
  description,
  parsedQuantity,
  hintedQuantity,
}: {
  rawValue: unknown;
  description: string | null;
  parsedQuantity: number | null;
  hintedQuantity: number | null;
}): number | null {
  if (hintedQuantity === null) {
    return parsedQuantity;
  }

  if (
    parsedQuantity === null ||
    Math.abs(parsedQuantity - hintedQuantity) > 0.0005
  ) {
    logAmountNormalization({
      field: "quantity",
      rawValue: rawValue ?? description,
      normalizedValue: hintedQuantity,
      reason: "description_quantity_hint",
    });
  }

  return hintedQuantity;
}

function normalizeLineTotal({
  rawValue,
  quantity,
  unitPrice,
}: {
  rawValue: unknown;
  quantity: number | null;
  unitPrice: number | null;
}): number | null {
  const parsed = parseMoney(rawValue);
  const expected = quantity !== null && unitPrice !== null
    ? roundMoney(quantity * unitPrice)
    : null;

  return chooseRescaledMoneyCandidate({
    field: "line_total",
    rawValue,
    parsed,
    anchor: expected,
  });
}

function normalizeDocumentMoneyField({
  field,
  rawValue,
  anchor,
}: {
  field: string;
  rawValue: unknown;
  anchor: number | null;
}): number | null {
  const parsed = parseMoney(rawValue);
  return chooseRescaledMoneyCandidate({
    field,
    rawValue,
    parsed,
    anchor,
  });
}

function chooseRescaledMoneyCandidate({
  field,
  rawValue,
  parsed,
  anchor,
}: {
  field: string;
  rawValue: unknown;
  parsed: number | null;
  anchor: number | null;
}): number | null {
  if (parsed === null) return null;
  if (anchor === null || anchor <= 0) return parsed;

  const candidates = uniqueMoneyCandidates(parsed);
  const rawDistance = Math.abs(parsed - anchor);
  let best = parsed;
  let bestDistance = rawDistance;

  for (const candidate of candidates) {
    const distance = Math.abs(candidate - anchor);
    if (distance < bestDistance) {
      best = candidate;
      bestDistance = distance;
    }
  }

  if (best !== parsed && shouldAcceptRescaledCandidate(parsed, best, anchor)) {
    logAmountNormalization({
      field,
      rawValue,
      normalizedValue: best,
      reason: "rescaled_to_anchor",
    });
    return best;
  }

  return parsed;
}

function reconcileDocumentTotals({
  documentType,
  lineItems,
  lineItemsSubtotal,
  rawSubtotal,
  rawTaxAmount,
  rawTotalAmount,
  subtotal,
  taxAmount,
  totalAmount,
}: {
  documentType: string;
  lineItems: Array<{ line_total: number | null }>;
  lineItemsSubtotal: number | null;
  rawSubtotal: unknown;
  rawTaxAmount: unknown;
  rawTotalAmount: unknown;
  subtotal: number | null;
  taxAmount: number | null;
  totalAmount: number | null;
}): {
  subtotal: number | null;
  taxAmount: number | null;
  totalAmount: number | null;
} {
  if (
    documentType !== "invoice" ||
    lineItemsSubtotal === null ||
    lineItems.length < 2
  ) {
    return { subtotal, taxAmount, totalAmount };
  }

  const taxBase = lineItemsSubtotal;
  const parsedRawSubtotal = parseMoney(rawSubtotal);
  const parsedRawTotal = parseMoney(rawTotalAmount);
  const parsedRawTax = parseMoney(rawTaxAmount);

  let reconciledSubtotal = subtotal;
  if (
    subtotal === null ||
    Math.abs(subtotal - lineItemsSubtotal) > 0.05
  ) {
    const plausibleTotalCandidates = [parsedRawSubtotal, parsedRawTotal]
      .filter((value): value is number => value !== null)
      .filter((value) => isPlausibleTotalFromSubtotal(value, taxBase));

    if (plausibleTotalCandidates.length > 0) {
      reconciledSubtotal = lineItemsSubtotal;
      logAmountNormalization({
        field: "subtotal",
        rawValue: rawSubtotal,
        normalizedValue: reconciledSubtotal,
        reason: "line_items_sum_as_base",
      });
    }
  }

  let reconciledTotal = totalAmount;
  const plausibleTotalCandidates = [parsedRawSubtotal, parsedRawTotal]
    .filter((value): value is number => value !== null)
    .filter((value) => isPlausibleTotalFromSubtotal(value, reconciledSubtotal));

  if (plausibleTotalCandidates.length > 0 && reconciledSubtotal !== null) {
    const smallestPlausibleTotal = plausibleTotalCandidates.sort((a, b) => a - b)[0];
    if (reconciledTotal === null || Math.abs(reconciledTotal - smallestPlausibleTotal) > 0.05) {
      logAmountNormalization({
        field: "total_amount",
        rawValue: rawTotalAmount,
        normalizedValue: smallestPlausibleTotal,
        reason: "smallest_plausible_total_from_raw_totals",
      });
      reconciledTotal = smallestPlausibleTotal;
    }
  }

  let reconciledTax = taxAmount;
  if (reconciledSubtotal !== null && reconciledTotal !== null) {
    const derivedTax = roundMoney(reconciledTotal - reconciledSubtotal);
    if (
      derivedTax !== null &&
      (reconciledTax === null || isImplausibleMoney(reconciledTax, derivedTax))
    ) {
      logAmountNormalization({
        field: "tax_amount",
        rawValue: rawTaxAmount,
        normalizedValue: derivedTax,
        reason: "derived_from_reconciled_total_minus_subtotal",
      });
      reconciledTax = derivedTax;
    }
  } else if (
    reconciledSubtotal !== null &&
    parsedRawTax !== null &&
    isPlausibleTaxAmount(parsedRawTax, reconciledSubtotal)
  ) {
    reconciledTax = parsedRawTax;
  }

  return {
    subtotal: reconciledSubtotal,
    taxAmount: reconciledTax,
    totalAmount: reconciledTotal,
  };
}

function isPlausibleTotalFromSubtotal(
  candidateTotal: number,
  subtotal: number | null,
): boolean {
  if (subtotal === null) return false;
  if (candidateTotal <= subtotal) return false;

  const delta = candidateTotal - subtotal;
  return delta <= subtotal * 0.35;
}

function isPlausibleTaxAmount(
  candidateTax: number,
  subtotal: number,
): boolean {
  return candidateTax >= 0 && candidateTax <= subtotal * 0.35;
}

function shouldAcceptRescaledCandidate(
  original: number,
  candidate: number,
  anchor: number,
): boolean {
  const originalDistance = Math.abs(original - anchor);
  const candidateDistance = Math.abs(candidate - anchor);
  const tolerance = Math.max(0.05, anchor * 0.2);

  if (candidateDistance <= tolerance) {
    return true;
  }

  return originalDistance > candidateDistance * 20;
}

function uniqueMoneyCandidates(value: number): number[] {
  const divisors = [1, 10, 100, 1000, 10000];
  const seen = new Set<number>();
  const candidates: number[] = [];

  for (const divisor of divisors) {
    const candidate = roundMoney(value / divisor);
    if (candidate === null || seen.has(candidate)) continue;
    seen.add(candidate);
    candidates.push(candidate);
  }

  return candidates;
}

function isImplausibleMoney(value: number, anchor: number): boolean {
  const threshold = Math.max(0.05, anchor * 0.2);
  return Math.abs(value - anchor) > threshold;
}

function sumMoney(values: Array<number | null>): number | null {
  const presentValues = values.filter((value): value is number => value !== null);
  if (presentValues.length === 0) return null;

  return roundMoney(
    presentValues.reduce((total, value) => total + value, 0),
  );
}

function parseQuantityFromDescription(description: string | null): number | null {
  if (!description) return null;
  const match = description.match(/\bU\s*:\s*(-?[0-9][0-9.,]*)\s*$/i);
  if (!match) return null;
  return parseQuantity(match[1]);
}

function logAmountNormalization({
  field,
  rawValue,
  normalizedValue,
  reason,
}: {
  field: string;
  rawValue: unknown;
  normalizedValue: number | null;
  reason: string;
}): void {
  logInfo(
    `[AmountNormalization] ${JSON.stringify({
      field,
      rawValue,
      normalizedValue,
      source: "process-document",
      reason,
    })}`,
  );
}

function normalizeExtractionAliases(
  extraction: Record<string, unknown>,
): Record<string, unknown> {
  return {
    document_type: firstNonEmptyString(
      extraction.document_type,
      extraction.type,
      extraction.doc_type,
    ),
    supplier_name: firstNonEmptyString(
      extraction.supplier_name,
      extraction.supplier,
      extraction.vendor,
      extraction.vendor_name,
    ),
    document_number: firstNonEmptyString(
      extraction.document_number,
      extraction.invoice_number,
      extraction.number,
    ),
    document_date: extraction.document_date ?? extraction.date,
    document_date_raw: extraction.document_date_raw ?? extraction.date_raw ??
      extraction.document_date ?? extraction.date,
    raw_text: firstNonEmptyString(
      extraction.raw_text,
      extraction.ocr_text,
      extraction.text,
    ),
    line_items: firstArrayValue(
      extraction.line_items,
      extraction.items,
      extraction.products,
    ) ?? [],
    subtotal: extraction.subtotal ?? extraction.base_amount,
    tax_rate: extraction.tax_rate ?? extraction.vat_rate,
    tax_amount: extraction.tax_amount ?? extraction.tax ?? extraction.vat ??
      extraction.vat_amount,
    total_amount: extraction.total_amount ?? extraction.total ??
      extraction.amount_total,
    currency: firstNonEmptyString(
      extraction.currency,
      extraction.currency_code,
    ),
    notes: firstNonEmptyString(extraction.notes, extraction.comment),
    confidence: firstNonEmptyString(extraction.confidence),
  };
}

function firstArrayValue(...values: unknown[]): unknown[] | undefined {
  for (const value of values) {
    if (Array.isArray(value)) return value;
  }
  return undefined;
}

async function resolveDocumentType({
  apiKey,
  aiType,
  confidence,
  rawText,
}: {
  apiKey: string;
  aiType: unknown;
  confidence: unknown;
  rawText: unknown;
}): Promise<
  { documentType: string; source: string; confidence: string | null }
> {
  const normalizedAiType = normalizeDocumentType(aiType);
  const normalizedConfidence = normalizeConfidence(confidence);
  const normalizedRawText = typeof rawText === "string" ? rawText.trim() : "";

  const heuristicType = detectDocumentType({
    aiType: normalizedAiType,
    rawText: normalizedRawText,
  });

  if (heuristicType !== "unknown" && heuristicType !== normalizedAiType) {
    return {
      documentType: heuristicType,
      source: "heuristic_override",
      confidence: normalizedConfidence,
    };
  }

  if (heuristicType !== "unknown" && normalizedConfidence !== "low") {
    return {
      documentType: heuristicType,
      source: heuristicType === normalizedAiType ? "ai" : "heuristic",
      confidence: normalizedConfidence,
    };
  }

  if (normalizedRawText) {
    try {
      const fallback = await classifyDocumentTypeFromText({
        apiKey,
        rawText: normalizedRawText,
      });
      const fallbackType = detectDocumentType({
        aiType: fallback.documentType,
        rawText: normalizedRawText,
      });

      if (fallbackType !== "unknown") {
        return {
          documentType: fallbackType,
          source: "text_fallback",
          confidence: fallback.confidence,
        };
      }
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      logError(
        `[process-document][type] fallback classifier failed: ${message}`,
      );
    }
  }

  return {
    documentType: heuristicType,
    source: heuristicType === normalizedAiType ? "ai" : "heuristic",
    confidence: normalizedConfidence,
  };
}

async function classifyDocumentTypeFromText({
  apiKey,
  rawText,
}: {
  apiKey: string;
  rawText: string;
}): Promise<{ documentType: string; confidence: string | null }> {
  const response = await fetch(OPENROUTER_ENDPOINT, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
      "HTTP-Referer": "https://hospidash.app",
      "X-Title": "HospiDash Document Type Classifier",
    },
    body: JSON.stringify({
      model: TEXT_CLASSIFIER_MODEL,
      messages: [
        {
          role: "user",
          content: textClassificationPrompt(rawText),
        },
      ],
      max_tokens: 300,
      temperature: 0,
    }),
  });

  if (!response.ok) {
    const errorBody = await readOpenRouterErrorBody(response);
    throw new Error(
      `Fallback classifier error ${response.status}: ${
        extractOpenRouterErrorMessage(errorBody)
      }`,
    );
  }

  const json = await response.json() as OpenRouterChatResponse;
  const assistantContent = json?.choices?.[0]?.message?.content;
  const content = extractAssistantTextContent(assistantContent);
  const parsed = parseExtraction(content);
  if (!parsed) {
    logWarn(
      `[process-document][type] unparseable fallback content model=${TEXT_CLASSIFIER_MODEL} content_type=${
        describeContentType(assistantContent)
      } preview=${truncateForLog(content, 300)}`,
    );
    throw new Error("Could not parse fallback classifier response");
  }

  return {
    documentType: normalizeDocumentType(nullableString(parsed.document_type)),
    confidence: normalizeConfidence(nullableString(parsed.confidence)),
  };
}

function textClassificationPrompt(rawText: string): string {
  return `Classify this hospitality document from Spain.

Possible values:
- "invoice"
- "delivery_note"
- "expense_ticket"
- "unknown"

Rules:
- If "Albaran" or "Albarán" appears anywhere, return "delivery_note"
- If the document contains VAT breakdown terms like "IVA", "Base imponible", and "Total", return "invoice"
- If it is a small POS receipt with payment method details, return "expense_ticket"
- Do not guess randomly

Return ONLY JSON:
{
  "document_type": "invoice"|"delivery_note"|"expense_ticket"|"unknown",
  "confidence": "high"|"medium"|"low"
}

Document text:
${rawText}`;
}

function detectDocumentType({
  aiType,
  rawText,
}: {
  aiType: unknown;
  rawText: string;
}): string {
  const normalizedAiType = normalizeDocumentType(aiType);
  const text = rawText
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase();

  if (text.includes("albaran")) {
    return "delivery_note";
  }

  if (text.includes("factura") || text.includes("invoice")) {
    return "invoice";
  }

  if (text.includes("iva") && text.includes("total") && text.includes("base")) {
    return "invoice";
  }

  if (
    text.includes("ticket") ||
    text.includes("efectivo") ||
    text.includes("tarjeta") ||
    text.includes("visa") ||
    text.includes("mastercard")
  ) {
    return normalizedAiType === "unknown" ? "expense_ticket" : normalizedAiType;
  }

  return normalizedAiType;
}

function normalizeDocumentType(value: unknown): string {
  if (typeof value !== "string") return "unknown";
  const trimmed = value.trim().toLowerCase();
  if (
    trimmed === "invoice" ||
    trimmed === "delivery_note" ||
    trimmed === "expense_ticket"
  ) {
    return trimmed;
  }
  return "unknown";
}

function normalizeConfidence(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim().toLowerCase();
  if (trimmed === "high" || trimmed === "medium" || trimmed === "low") {
    return trimmed;
  }
  return null;
}

function nullableString(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function parseNullableNumber(value: unknown): number | null {
  if (value === null || value === undefined) return null;
  if (typeof value === "number") return Number.isFinite(value) ? value : null;
  if (typeof value !== "string") return null;

  let cleaned = value.trim();
  if (!cleaned) return null;
  cleaned = cleaned.replace(/[€$£¥\s]/g, "");

  if (cleaned.includes(",") && cleaned.includes(".")) {
    if (cleaned.lastIndexOf(",") > cleaned.lastIndexOf(".")) {
      cleaned = cleaned.replace(/\./g, "").replace(",", ".");
    } else {
      cleaned = cleaned.replace(/,/g, "");
    }
  } else if (cleaned.includes(",")) {
    const decimals = cleaned.split(",").pop() ?? "";
    cleaned = decimals.length <= 2
      ? cleaned.replace(",", ".")
      : cleaned.replace(/,/g, "");
  }

  const parsed = Number.parseFloat(cleaned);
  return Number.isFinite(parsed) ? parsed : null;
}

function normalizeDate(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const raw = value.trim();
  if (!raw) return null;

  if (isValidIsoDate(raw)) return raw;

  const cleaned = raw
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[,]/g, " ")
    .replace(/\bde\b/g, " ")
    .replace(/\s+/g, " ")
    .trim();

  const numericMatch = cleaned.match(
    /^(\d{1,2})[\/\-.](\d{1,2})[\/\-.](\d{2,4})$/,
  );
  if (numericMatch) {
    const first = Number.parseInt(numericMatch[1], 10);
    const second = Number.parseInt(numericMatch[2], 10);
    const third = Number.parseInt(numericMatch[3], 10);

    const day = first;
    const month = second;
    const year = numericMatch[3].length === 2
      ? expandTwoDigitYear(third)
      : third;
    return toIsoDate(year, month, day);
  }

  const monthMap: Record<string, number> = {
    ene: 1,
    enero: 1,
    jan: 1,
    january: 1,
    feb: 2,
    febrero: 2,
    february: 2,
    mar: 3,
    marzo: 3,
    march: 3,
    abr: 4,
    abril: 4,
    apr: 4,
    april: 4,
    may: 5,
    mayo: 5,
    jun: 6,
    junio: 6,
    june: 6,
    jul: 7,
    julio: 7,
    july: 7,
    ago: 8,
    agosto: 8,
    aug: 8,
    august: 8,
    sep: 9,
    sept: 9,
    septiembre: 9,
    setiembre: 9,
    september: 9,
    oct: 10,
    octubre: 10,
    october: 10,
    nov: 11,
    noviembre: 11,
    november: 11,
    dic: 12,
    diciembre: 12,
    dec: 12,
    december: 12,
  };

  const dayMonthNameYear = cleaned.match(/^(\d{1,2})\s+([a-z]+)\s+(\d{2,4})$/);
  if (dayMonthNameYear) {
    const day = Number.parseInt(dayMonthNameYear[1], 10);
    const month = monthMap[dayMonthNameYear[2]];
    const yearValue = Number.parseInt(dayMonthNameYear[3], 10);
    const year = dayMonthNameYear[3].length === 2
      ? expandTwoDigitYear(yearValue)
      : yearValue;
    if (month) return toIsoDate(year, month, day);
  }

  const monthNameDayYear = cleaned.match(/^([a-z]+)\s+(\d{1,2})\s+(\d{2,4})$/);
  if (monthNameDayYear) {
    const month = monthMap[monthNameDayYear[1]];
    const day = Number.parseInt(monthNameDayYear[2], 10);
    const yearValue = Number.parseInt(monthNameDayYear[3], 10);
    const year = monthNameDayYear[3].length === 2
      ? expandTwoDigitYear(yearValue)
      : yearValue;
    if (month) return toIsoDate(year, month, day);
  }

  return null;
}

function isValidIsoDate(value: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const date = new Date(`${value}T12:00:00.000Z`);
  return !Number.isNaN(date.getTime()) && date.toISOString().startsWith(value);
}

function expandTwoDigitYear(year: number): number {
  return year >= 70 ? 1900 + year : 2000 + year;
}

function toIsoDate(year: number, month: number, day: number): string | null {
  if (year < 1900 || year > 2100) return null;
  if (month < 1 || month > 12) return null;
  if (day < 1 || day > 31) return null;

  const iso = `${String(year).padStart(4, "0")}-${
    String(month).padStart(2, "0")
  }-${String(day).padStart(2, "0")}`;
  return isValidIsoDate(iso) ? iso : null;
}
