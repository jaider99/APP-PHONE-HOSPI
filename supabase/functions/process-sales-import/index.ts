import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { encode as encodeBase64 } from "https://deno.land/std@0.177.0/encoding/base64.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { recordAuditEventDeferred } from "../_shared/audit.ts";
import {
  checkRateLimit,
  rateLimitKey,
  rateLimitResponse,
} from "../_shared/rate_limit.ts";
import {
  HttpError,
  readJsonObject,
  requireStringField,
} from "../_shared/request.ts";
import { logError, logInfo, logWarn } from "../_shared/redact.ts";
import {
  parseMoney,
  parseQuantity,
  roundMoney,
} from "../_shared/number_normalization.ts";

const OPENROUTER_ENDPOINT = "https://openrouter.ai/api/v1/chat/completions";
const MODEL = Deno.env.get("OPENROUTER_SALES_MODEL") ??
  "nvidia/nemotron-nano-12b-v2-vl:free";
const RATE_LIMIT_WINDOW_MS = 60_000;
const RATE_LIMIT_MAX_REQUESTS = 6;
const MAX_JSON_BYTES = 1_024;
const OPENROUTER_TIMEOUT_MS = 90_000;
const MAX_FILE_BYTES = 10 * 1024 * 1024;
const MAX_CSV_CHARS = 30_000;
const ALLOWED_SALES_CHANNELS = new Set(["dine_in", "takeaway", "delivery", "unknown"]);

const jsonHeaders = { "Content-Type": "application/json" };

type JsonObject = Record<string, unknown>;
type SupabaseEdgeClient = ReturnType<typeof createClient<any, "public", any>>;

interface SalesImportRow {
  id: string;
  company_id: string;
  file_path: string | null;
  status: string;
}

interface NormalizedItem {
  product_name: string;
  normalized_product_name: string | null;
  quantity: number | null;
  unit_price: number | null;
  total_amount: number | null;
  category: string | null;
  pos_product_id: string | null;
}

interface NormalizedSale {
  sale_date: string;
  sale_datetime: string | null;
  gross_amount: number;
  net_amount: number | null;
  tax_amount: number | null;
  discount_amount: number | null;
  tip_amount: number | null;
  payment_method: string | null;
  channel: string;
  pos_transaction_id: string | null;
  items: NormalizedItem[];
}

interface NormalizedSalesExtraction {
  period_start: string;
  period_end: string;
  currency: string;
  total_gross: number;
  total_net: number | null;
  total_tax: number | null;
  notes: string | null;
  transactions: NormalizedSale[];
}

type ProcessSalesImportStage =
  | "read_request"
  | "validate_access"
  | "rate_limit"
  | "mark_processing"
  | "download_storage"
  | "unsupported_pdf"
  | "configure_openrouter"
  | "call_openrouter"
  | "parse_vlm_response"
  | "normalize_extraction"
  | "validate_extraction"
  | "mark_flagged"
  | "replace_imported_sales"
  | "finalize_import"
  | "cleanup_failed_import";

class SalesImportStageError extends Error {
  constructor(
    public readonly stage: ProcessSalesImportStage,
    message: string,
    public readonly status = 500,
  ) {
    super(message);
    this.name = "SalesImportStageError";
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

  if (!authHeader) return jsonResponse({ error: "Missing authorization" }, 401);

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });

  const { data: { user }, error: userError } = await userClient.auth.getUser();
  if (userError || !user) {
    return jsonResponse({ error: "Invalid or expired token" }, 401);
  }

  const serviceClient = createClient<any, "public", any>(
    supabaseUrl,
    serviceRoleKey,
  );
  let salesImportId = "";
  let companyId = "";
  let stage: ProcessSalesImportStage = "read_request";

  try {
    const body = await readJsonObject(req, {
      maxBytes: MAX_JSON_BYTES,
      allowedFields: ["sales_import_id", "salesImportId"],
    });
    salesImportId = requireSalesImportId(body);
    logInfo(`[process-sales-import] START import=${salesImportId}`);

    stage = "validate_access";
    const { data: accessRow, error: accessError } = await userClient
      .from("sales_imports")
      .select("id, company_id, file_path, status")
      .eq("id", salesImportId)
      .maybeSingle<SalesImportRow>();

    if (accessError || !accessRow) {
      return jsonResponse({ error: "Sales import not found or access denied" }, 403);
    }
    if (!accessRow.file_path) {
      return jsonResponse({ error: "Sales import file is missing" }, 400);
    }

    companyId = accessRow.company_id;
    stage = "rate_limit";
    const rateLimit = checkRateLimit({
      key: rateLimitKey("process-sales-import", user.id, companyId),
      limit: RATE_LIMIT_MAX_REQUESTS,
      windowMs: RATE_LIMIT_WINDOW_MS,
    });
    if (!rateLimit.allowed) {
      recordAuditEventDeferred(userClient, {
        companyId,
        action: "security.ai.process_sales_import",
        entityType: "sales_import",
        entityId: salesImportId,
        outcome: "denied",
        metadata: { reason: "rate_limited" },
      });
      return rateLimitResponse(rateLimit.retryAfterSeconds, jsonHeaders);
    }

    stage = "mark_processing";
    await markImport(serviceClient, salesImportId, companyId, {
      status: "processing",
      notes: null,
    });

    stage = "download_storage";
    const prepared = await prepareInput(serviceClient, accessRow.file_path);
    if (prepared.kind === "unsupported_pdf") {
      stage = "unsupported_pdf";
      await markImport(serviceClient, salesImportId, companyId, {
        status: "flagged",
        notes: "PDF sales imports are not supported yet. Upload a sales screenshot/image or CSV export.",
      });
      return jsonResponse({ error: "PDF sales import rendering is not available yet", stage }, 422);
    }

    stage = "call_openrouter";
    const extraction = await extractSales(prepared);
    stage = "normalize_extraction";
    const normalized = normalizeExtraction(extraction);
    stage = "validate_extraction";
    const validation = validateExtraction(normalized);
    if (!validation.ok) {
      const responseStage = stage;
      stage = "mark_flagged";
      await markImport(serviceClient, salesImportId, companyId, {
        status: "flagged",
        notes: validation.message,
        extraction_raw: extraction,
        extraction_clean: { ...normalized, validation_results: validation },
      });
      return jsonResponse({ error: validation.message, stage: responseStage }, 422);
    }

    stage = "replace_imported_sales";
    await replaceImportedSales({
      serviceClient,
      companyId,
      salesImportId,
      userId: user.id,
      extraction: normalized,
    });

    stage = "finalize_import";
    await markImport(serviceClient, salesImportId, companyId, {
      status: "completed",
      imported_at: new Date().toISOString(),
      period_start: normalized.period_start,
      period_end: normalized.period_end,
      total_gross: normalized.total_gross,
      total_net: normalized.total_net,
      total_tax: normalized.total_tax,
      currency: normalized.currency,
      notes: normalized.notes,
      extraction_raw: extraction,
      extraction_clean: { ...normalized, validation_results: validation },
    });

    recordAuditEventDeferred(userClient, {
      companyId,
      action: "security.ai.process_sales_import",
      entityType: "sales_import",
      entityId: salesImportId,
      outcome: "success",
      metadata: {
        transaction_count: normalized.transactions.length,
        item_count: normalized.transactions.reduce(
          (count, sale) => count + sale.items.length,
          0,
        ),
      },
    });

    return jsonResponse({ ok: true, salesImportId });
  } catch (error) {
    const failure = salesImportFailure(error, stage);
    logError(`[process-sales-import] failed stage=${failure.stage} import=${salesImportId}`, error);
    if (salesImportId && companyId) {
      try {
        stage = "cleanup_failed_import";
        await cleanupFailedImport(serviceClient, salesImportId, companyId);
        await markImport(serviceClient, salesImportId, companyId, {
          status: "failed",
          notes: failure.message,
        });
      } catch (cleanupError) {
        logError(
          `[process-sales-import] cleanup failed import=${salesImportId}`,
          cleanupError,
        );
      }
    }

    return jsonResponse({ error: failure.message, stage: failure.stage }, failure.status);
  }
});

async function prepareInput(serviceClient: SupabaseEdgeClient, path: string) {
  const { data, error } = await serviceClient.storage
    .from("sales-imports")
    .download(path);
  if (error || !data) throw new Error("Could not download sales import file");

  const bytes = new Uint8Array(await data.arrayBuffer());
  if (bytes.byteLength > MAX_FILE_BYTES) throw new Error("Sales import file is too large");

  const mimeType = data.type || mimeTypeFromPath(path);
  if (mimeType === "application/pdf") return { kind: "unsupported_pdf" as const };
  if (mimeType === "text/csv" || path.toLowerCase().endsWith(".csv")) {
    return {
      kind: "text" as const,
      mimeType: "text/csv",
      text: new TextDecoder().decode(bytes).slice(0, MAX_CSV_CHARS),
    };
  }
  if (mimeType.startsWith("image/")) {
    const imageBuffer = bytes.buffer.slice(
      bytes.byteOffset,
      bytes.byteOffset + bytes.byteLength,
    );
    return {
      kind: "image" as const,
      mimeType,
      dataUrl: `data:${mimeType};base64,${encodeBase64(imageBuffer)}`,
    };
  }
  throw new Error(`Unsupported sales import file type: ${mimeType}`);
}

async function extractSales(
  prepared: { kind: "image"; mimeType: string; dataUrl: string } |
    { kind: "text"; mimeType: string; text: string },
): Promise<JsonObject> {
  const apiKey = Deno.env.get("OPENROUTER_API_KEY");
  if (!apiKey) {
    throw new SalesImportStageError(
      "configure_openrouter",
      "Sales extraction service is not configured.",
    );
  }

  const prompt = [
    "Extract hospitality sales from this report.",
    "Return JSON only, no markdown.",
    "Use these exact keys:",
    "period_start, period_end, currency, total_gross, total_net, total_tax, notes, transactions.",
    "Each transaction: sale_date, sale_datetime, gross_amount, net_amount, tax_amount, discount_amount, tip_amount, payment_method, channel, pos_transaction_id, items.",
    "Each item: product_name, normalized_product_name, quantity, unit_price, total_amount, category, pos_product_id.",
    "If the report is a daily aggregate, return one transaction for the aggregate total and include item rows only when visible.",
    "Keep European money formatting as strings if uncertain; the server normalizes values.",
  ].join("\n");

  const userContent = prepared.kind === "image"
    ? [
      { type: "text", text: prompt },
      { type: "image_url", image_url: { url: prepared.dataUrl } },
    ]
    : `${prompt}\n\nCSV/TEXT REPORT:\n${prepared.text}`;

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), OPENROUTER_TIMEOUT_MS);
  try {
    const response = await fetch(OPENROUTER_ENDPOINT, {
      method: "POST",
      signal: controller.signal,
      headers: {
        "Authorization": `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: MODEL,
        temperature: 0,
        max_tokens: 2500,
        messages: [
          { role: "system", content: "You extract sales data and return strict JSON only." },
          { role: "user", content: userContent },
        ],
      }),
    });

    if (!response.ok) {
      await response.text();
      logWarn(`[process-sales-import] OpenRouter failed status=${response.status}`);
      throw new SalesImportStageError(
        "call_openrouter",
        `Sales extraction service failed (${response.status}).`,
        response.status >= 500 ? 502 : 422,
      );
    }

    let data: JsonObject;
    try {
      data = await response.json() as JsonObject;
    } catch {
      throw new SalesImportStageError(
        "parse_vlm_response",
        "Sales extraction service returned an invalid response.",
        502,
      );
    }
    const content = (((data.choices as Array<JsonObject> | undefined)?.[0]
      ?.message as JsonObject | undefined)?.content) as unknown;
    if (typeof content !== "string") {
      throw new SalesImportStageError(
        "parse_vlm_response",
        "Sales extraction returned no JSON content.",
        502,
      );
    }
    try {
      return extractJsonObject(content);
    } catch {
      throw new SalesImportStageError(
        "parse_vlm_response",
        "Sales extraction response was not valid JSON.",
        502,
      );
    }
  } finally {
    clearTimeout(timeout);
  }
}

function normalizeExtraction(raw: JsonObject): NormalizedSalesExtraction {
  const periodStart = parseDate(raw.period_start) ?? todayDate();
  const periodEnd = parseDate(raw.period_end) ?? periodStart;
  const currency = firstString(raw.currency)?.toUpperCase() ?? "EUR";
  const totalGross = parseMoney(raw.total_gross);
  const totalNet = parseMoney(raw.total_net);
  const totalTax = parseMoney(raw.total_tax);
  const notes = firstString(raw.notes);
  const rawTransactions = Array.isArray(raw.transactions) ? raw.transactions : [];

  const transactions = rawTransactions
    .filter((entry): entry is JsonObject => entry !== null && typeof entry === "object" && !Array.isArray(entry))
    .map((entry) => normalizeSale(entry, periodEnd));

  if (transactions.length === 0 && totalGross !== null) {
    transactions.push({
      sale_date: periodEnd,
      sale_datetime: null,
      gross_amount: totalGross,
      net_amount: totalNet,
      tax_amount: totalTax,
      discount_amount: null,
      tip_amount: null,
      payment_method: null,
      channel: "unknown",
      pos_transaction_id: null,
      items: [],
    });
  }

  const derivedGross = roundMoney(
    transactions.reduce((sum, sale) => sum + sale.gross_amount, 0),
  ) ?? 0;

  return {
    period_start: periodStart,
    period_end: periodEnd,
    currency,
    total_gross: totalGross ?? derivedGross,
    total_net: totalNet,
    total_tax: totalTax,
    notes,
    transactions,
  };
}

function normalizeSale(raw: JsonObject, fallbackDate: string): NormalizedSale {
  const gross = parseMoney(raw.gross_amount) ?? parseMoney(raw.total_amount);
  const itemsRaw = Array.isArray(raw.items) ? raw.items : [];
  const items = itemsRaw
    .filter((entry): entry is JsonObject => entry !== null && typeof entry === "object" && !Array.isArray(entry))
    .map(normalizeItem)
    .filter((item) => item.product_name.trim().length > 0);
  const itemTotal = roundMoney(
    items.reduce((sum, item) => sum + (item.total_amount ?? 0), 0),
  );

  return {
    sale_date: parseDate(raw.sale_date) ?? fallbackDate,
    sale_datetime: parseDateTime(raw.sale_datetime),
    gross_amount: gross ?? itemTotal ?? 0,
    net_amount: parseMoney(raw.net_amount),
    tax_amount: parseMoney(raw.tax_amount),
    discount_amount: parseMoney(raw.discount_amount),
    tip_amount: parseMoney(raw.tip_amount),
    payment_method: firstString(raw.payment_method),
    channel: normalizeSalesChannel(raw.channel),
    pos_transaction_id: firstString(raw.pos_transaction_id),
    items,
  };
}

function normalizeItem(raw: JsonObject): NormalizedItem {
  return {
    product_name: firstString(raw.product_name) ?? "",
    normalized_product_name: firstString(raw.normalized_product_name),
    quantity: parseQuantity(raw.quantity),
    unit_price: parseMoney(raw.unit_price),
    total_amount: parseMoney(raw.total_amount),
    category: firstString(raw.category),
    pos_product_id: firstString(raw.pos_product_id),
  };
}

function validateExtraction(extraction: NormalizedSalesExtraction) {
  if (extraction.transactions.length === 0) {
    return { ok: false, message: "No sales transactions or aggregate total found." };
  }
  if (!Number.isFinite(extraction.total_gross) || extraction.total_gross <= 0) {
    return { ok: false, message: "Sales report total is missing or zero." };
  }
  const transactionGross = roundMoney(
    extraction.transactions.reduce((sum, sale) => sum + sale.gross_amount, 0),
  ) ?? 0;
  const variance = roundMoney(Math.abs(transactionGross - extraction.total_gross)) ?? 0;
  return {
    ok: true,
    message: "validated",
    total_gross: extraction.total_gross,
    transaction_gross: transactionGross,
    gross_variance: variance,
    transaction_count: extraction.transactions.length,
  };
}

async function replaceImportedSales(params: {
  serviceClient: SupabaseEdgeClient;
  companyId: string;
  salesImportId: string;
  userId: string;
  extraction: NormalizedSalesExtraction;
}) {
  const { serviceClient, companyId, salesImportId, userId, extraction } = params;

  await serviceClient
    .from("sales_items")
    .delete()
    .eq("company_id", companyId)
    .eq("sales_import_id", salesImportId);
  await serviceClient
    .from("sales")
    .delete()
    .eq("company_id", companyId)
    .eq("sales_import_id", salesImportId);

  for (const sale of extraction.transactions) {
    const { data: inserted, error } = await serviceClient
      .from("sales")
      .insert({
        company_id: companyId,
        sales_import_id: salesImportId,
        sale_date: sale.sale_date,
        sale_datetime: sale.sale_datetime,
        gross_amount: sale.gross_amount,
        net_amount: sale.net_amount,
        tax_amount: sale.tax_amount,
        discount_amount: sale.discount_amount,
        tip_amount: sale.tip_amount,
        currency: extraction.currency,
        payment_method: sale.payment_method,
        channel: sale.channel,
        pos_transaction_id: sale.pos_transaction_id,
        source_type: "vlm_import",
        total_amount: sale.gross_amount,
        tax_collected: sale.tax_amount,
        tips_amount: sale.tip_amount,
        discounts_amount: sale.discount_amount,
        transaction_count: 1,
        source: "api",
        created_by: userId,
      })
      .select("id")
      .single<{ id: string }>();

    if (error || !inserted) throw new Error(`Could not insert sale: ${error?.message ?? "unknown"}`);
    if (sale.items.length === 0) continue;

    const { error: itemError } = await serviceClient.from("sales_items").insert(
      sale.items.map((item) => ({
        company_id: companyId,
        sale_id: inserted.id,
        sales_import_id: salesImportId,
        product_name: item.product_name,
        normalized_product_name: item.normalized_product_name,
        quantity: item.quantity,
        unit_price: item.unit_price,
        total_amount: item.total_amount,
        category: item.category,
        pos_product_id: item.pos_product_id,
        metadata: { source_type: "vlm_import" },
      })),
    );
    if (itemError) throw new Error(`Could not insert sales items: ${itemError.message}`);
  }
}

async function cleanupFailedImport(
  serviceClient: SupabaseEdgeClient,
  salesImportId: string,
  companyId: string,
) {
  await serviceClient.from("sales_items").delete()
    .eq("company_id", companyId)
    .eq("sales_import_id", salesImportId);
  await serviceClient.from("sales").delete()
    .eq("company_id", companyId)
    .eq("sales_import_id", salesImportId);
}

async function markImport(
  serviceClient: SupabaseEdgeClient,
  salesImportId: string,
  companyId: string,
  values: JsonObject,
) {
  const { error } = await serviceClient.from("sales_imports")
    .update(values)
    .eq("id", salesImportId)
    .eq("company_id", companyId);
  if (error) throw new Error(`Could not update sales import: ${error.message}`);
}

function requireSalesImportId(body: JsonObject): string {
  const hasSnakeCase = body.sales_import_id !== undefined;
  const hasCamelCase = body.salesImportId !== undefined;
  if (hasSnakeCase && hasCamelCase) {
    throw new HttpError(400, "Send either sales_import_id or salesImportId, not both");
  }
  return requireStringField(
    body,
    hasSnakeCase ? "sales_import_id" : "salesImportId",
    { maxLength: 64 },
  );
}

function salesImportFailure(
  error: unknown,
  fallbackStage: ProcessSalesImportStage,
): { stage: ProcessSalesImportStage; status: number; message: string } {
  if (error instanceof SalesImportStageError) {
    return { stage: error.stage, status: error.status, message: error.message };
  }
  if (error instanceof HttpError) {
    return { stage: fallbackStage, status: error.status, message: error.message };
  }
  return {
    stage: fallbackStage,
    status: 500,
    message: safeSalesImportFailureMessage(fallbackStage),
  };
}

function safeSalesImportFailureMessage(stage: ProcessSalesImportStage): string {
  switch (stage) {
    case "download_storage":
      return "Sales import file could not be downloaded from storage.";
    case "configure_openrouter":
      return "Sales extraction service is not configured.";
    case "call_openrouter":
      return "Sales extraction service could not process the report.";
    case "parse_vlm_response":
      return "Sales extraction response could not be parsed.";
    case "normalize_extraction":
    case "validate_extraction":
      return "Sales extraction result could not be validated.";
    case "mark_flagged":
    case "mark_processing":
    case "finalize_import":
      return "Sales import status could not be updated.";
    case "replace_imported_sales":
      return "Sales rows could not be saved.";
    default:
      return "Sales import failed.";
  }
}

function extractJsonObject(content: string): JsonObject {
  const withoutFence = content.trim().replace(/^```json/i, "").replace(/^```/, "").replace(/```$/, "").trim();
  const start = withoutFence.indexOf("{");
  const end = withoutFence.lastIndexOf("}");
  if (start < 0 || end <= start) throw new Error("Sales extraction response did not contain JSON");
  const parsed = JSON.parse(withoutFence.slice(start, end + 1)) as unknown;
  if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new Error("Sales extraction JSON must be an object");
  }
  return parsed as JsonObject;
}

function parseDate(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  const iso = /^\d{4}-\d{2}-\d{2}$/.test(trimmed) ? trimmed : null;
  if (iso) return iso;
  const numericDate = parseNumericDayFirstDate(trimmed);
  if (numericDate) return numericDate;
  const parsed = Date.parse(trimmed);
  if (!Number.isFinite(parsed)) return null;
  return new Date(parsed).toISOString().slice(0, 10);
}

function parseDateTime(value: unknown): string | null {
  if (typeof value !== "string" || value.trim().length === 0) return null;
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) ? new Date(parsed).toISOString() : null;
}

function parseNumericDayFirstDate(value: string): string | null {
  const match = value.match(/^(\d{1,2})[\/.-](\d{1,2})[\/.-](\d{2}|\d{4})$/);
  if (!match) return null;

  const day = Number.parseInt(match[1], 10);
  const month = Number.parseInt(match[2], 10);
  const rawYear = Number.parseInt(match[3], 10);
  const year = match[3].length === 2 ? 2000 + rawYear : rawYear;
  if (!isValidCalendarDate(year, month, day)) return null;

  return `${year.toString().padStart(4, "0")}-${month.toString().padStart(2, "0")}-${day.toString().padStart(2, "0")}`;
}

function isValidCalendarDate(year: number, month: number, day: number): boolean {
  if (year < 2000 || year > 2100 || month < 1 || month > 12 || day < 1 || day > 31) {
    return false;
  }
  const candidate = new Date(Date.UTC(year, month - 1, day));
  return candidate.getUTCFullYear() === year &&
    candidate.getUTCMonth() === month - 1 &&
    candidate.getUTCDate() === day;
}

function todayDate(): string {
  return new Date().toISOString().slice(0, 10);
}

function firstString(value: unknown): string | null {
  return typeof value === "string" && value.trim().length > 0 ? value.trim() : null;
}

function normalizeSalesChannel(value: unknown): string {
  const rawChannel = firstString(value)?.toLowerCase().replace(/[\s-]+/g, "_");
  if (!rawChannel) return "unknown";
  if (ALLOWED_SALES_CHANNELS.has(rawChannel)) return rawChannel;
  if (["eat_in", "in_house", "table_service", "restaurant", "dining"].includes(rawChannel)) {
    return "dine_in";
  }
  if (["takeout", "to_go", "pickup", "collection", "collect"].includes(rawChannel)) {
    return "takeaway";
  }
  if (["deliveroo", "uber_eats", "just_eat", "glovo"].includes(rawChannel)) {
    return "delivery";
  }
  return "unknown";
}

function mimeTypeFromPath(path: string): string {
  const lower = path.toLowerCase();
  if (lower.endsWith(".pdf")) return "application/pdf";
  if (lower.endsWith(".csv")) return "text/csv";
  if (lower.endsWith(".jpg") || lower.endsWith(".jpeg")) return "image/jpeg";
  if (lower.endsWith(".png")) return "image/png";
  if (lower.endsWith(".webp")) return "image/webp";
  return "application/octet-stream";
}

function jsonResponse(body: JsonObject, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: jsonHeaders });
}