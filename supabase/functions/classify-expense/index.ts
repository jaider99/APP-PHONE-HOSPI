import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { HttpError, readJsonObject, requireStringField } from "../_shared/request.ts";
import { checkRateLimit, rateLimitKey, rateLimitResponse } from "../_shared/rate_limit.ts";
import { recordAuditEventDeferred } from "../_shared/audit.ts";

const OPENROUTER_ENDPOINT = "https://openrouter.ai/api/v1/chat/completions";
const CLASSIFICATION_MODEL = "mistralai/mistral-7b-instruct:free";
const MAX_JSON_BYTES = 4_096;
const RATE_LIMIT_WINDOW_MS = 60_000;
const RATE_LIMIT_MAX_REQUESTS = 12;

// ─── CORS ────────────────────────────────────────────────────────────────────

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

function jsonResponse(
  body: unknown,
  status = 200
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...CORS_HEADERS },
  });
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

function openRouterHeaders(apiKey: string): Record<string, string> {
  return {
    Authorization: `Bearer ${apiKey}`,
    "Content-Type": "application/json",
    "HTTP-Referer": "https://hospidash.app",
    "X-Title": "HospiDash Expense Classification",
  };
}

function normalizeForMatch(value: string): string {
  return value.toLowerCase().replace(/\s+/g, " ").trim();
}

/**
 * Parse JSON from messy LLM output, handling markdown code blocks and stray text.
 * Copied and adapted from process-document edge function.
 */
function parseJsonFromResponse(content: string): Record<string, unknown> | null {
  let cleaned = content
    .replace(/^[\uFEFF\u200B\u200C\u200D]+/, "")
    .trim();

  const codeBlockMatch = cleaned.match(/```(?:json)?\s*([\s\S]*?)\s*```/);
  if (codeBlockMatch) {
    cleaned = codeBlockMatch[1].trim();
  }

  if (!cleaned.startsWith("{")) {
    const jsonStart = cleaned.indexOf("{");
    if (jsonStart === -1) return null;

    let braceCount = 0;
    for (let i = jsonStart; i < cleaned.length; i++) {
      if (cleaned[i] === "{") braceCount++;
      if (cleaned[i] === "}") {
        braceCount--;
        if (braceCount === 0) {
          cleaned = cleaned.substring(jsonStart, i + 1);
          break;
        }
      }
    }
  }

  try {
    return JSON.parse(cleaned);
  } catch {
    try {
      // Strip trailing commas before } or ] which some models produce
      const sanitized = cleaned.replace(/,\s*([\]}])/g, "$1");
      return JSON.parse(sanitized);
    } catch {
      console.error("JSON parse error, attempted:", cleaned.substring(0, 300));
      return null;
    }
  }
}

// ─── Classification ───────────────────────────────────────────────────────────

interface Category {
  id: string;
  name: string;
}

interface ClassificationResult {
  categoryName: string;
  confidence: "high" | "medium" | "low";
}

function buildPrompt(
  categories: Category[],
  supplierName: string | null,
  documentType: string | null,
  totalAmount: number | null,
  lineItems: Array<Record<string, unknown>>,
  hasMinimalData: boolean
): string {
  const categoryList = categories
    .map((c) => `"${c.name}"`)
    .join(", ");

  const itemLines = lineItems
    .filter((item) => item["description"])
    .map((item) => `- ${item["description"]}`)
    .join("\n");

  let prompt =
    `You are a financial assistant for a hospitality business.\n` +
    `Your task is to assign the most appropriate category to this expense.\n\n` +
    `Available categories: ${categoryList}\n\n` +
    `Document data:\n` +
    `Supplier: ${supplierName ?? "Unknown"}\n` +
    `Type: ${documentType ?? "Unknown"}\n` +
    `Total: ${totalAmount != null ? totalAmount.toString() : "Unknown"}\n` +
    `Items:\n${itemLines || "None"}\n\n`;

  if (hasMinimalData) {
    prompt += `Note: Limited information available. Use best guess based on minimal data.\n\n`;
  }

  prompt +=
    `Return ONLY JSON: { "category_name": "string", "confidence": "high"|"medium"|"low" }\n` +
    `Do NOT explain anything.`;

  return prompt;
}

async function callClassificationModel(
  prompt: string,
  apiKey: string
): Promise<ClassificationResult | null> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 30_000);

  try {
    const response = await fetch(OPENROUTER_ENDPOINT, {
      method: "POST",
      headers: openRouterHeaders(apiKey),
      signal: controller.signal,
      body: JSON.stringify({
        model: CLASSIFICATION_MODEL,
        messages: [{ role: "user", content: prompt }],
        max_tokens: 128,
        temperature: 0,
      }),
    });

    clearTimeout(timeout);

    if (!response.ok) {
      const body = await response.text().catch(() => "");
      console.error(`Classification API error: ${response.status} — ${body.substring(0, 300)}`);
      return null;
    }

    const data = await response.json() as Record<string, unknown>;
    const choices = data["choices"] as Array<Record<string, unknown>> | undefined;
    if (!choices || choices.length === 0) return null;

    const message = choices[0]["message"] as Record<string, unknown> | undefined;
    const content = message?.["content"] as string | undefined;
    if (!content) return null;

    const parsed = parseJsonFromResponse(content);
    if (!parsed) return null;

    const categoryName = typeof parsed["category_name"] === "string"
      ? parsed["category_name"].trim()
      : null;
    const rawConfidence = typeof parsed["confidence"] === "string"
      ? parsed["confidence"].toLowerCase()
      : "low";
    const confidence: "high" | "medium" | "low" =
      rawConfidence === "high" ? "high"
      : rawConfidence === "medium" ? "medium"
      : "low";

    if (!categoryName) return null;

    return { categoryName, confidence };
  } catch (e) {
    clearTimeout(timeout);
    console.error("callClassificationModel error:", e);
    return null;
  }
}

// ─── HTTP Handler ─────────────────────────────────────────────────────────────

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  // ── Auth ──────────────────────────────────────────────────────────────────
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return jsonResponse({ error: "Missing authorization" }, 401);
  }

  // ── Env ───────────────────────────────────────────────────────────────────
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const openRouterKey = Deno.env.get("OPENROUTER_API_KEY");

  if (!openRouterKey) {
    return jsonResponse({ error: "Server AI key not configured" }, 500);
  }

  // ── Parse body ────────────────────────────────────────────────────────────
  let documentId: string;
  try {
    const body = await readJsonObject(req, {
      maxBytes: MAX_JSON_BYTES,
      allowedFields: ["document_id"],
    });
    documentId = requireStringField(body, "document_id", { maxLength: 80 });
  } catch (error) {
    if (error instanceof HttpError) {
      return jsonResponse({ error: error.message }, error.status);
    }
    return jsonResponse({ error: "Invalid request body" }, 400);
  }

  // ── Verify caller identity & tenant access via RLS ────────────────────────
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });

  const { data: { user }, error: userError } = await userClient.auth.getUser();
  if (userError || !user) {
    console.error("Auth validation failed:", userError?.message);
    return jsonResponse({ error: "Invalid or expired token" }, 401);
  }

  // Confirm user can access this document (RLS will block if not)
  const { data: accessCheck, error: accessError } = await userClient
    .from("documents")
    .select("id, company_id")
    .eq("id", documentId)
    .maybeSingle();

  if (accessError || !accessCheck) {
    console.error(
      "Access denied for document:", documentId,
      "user:", user.id,
      "error:", accessError?.message
    );
    return jsonResponse({ error: "Document not found or access denied" }, 403);
  }

  // Derive company_id from DB — never trust client-supplied value
  const companyId = accessCheck.company_id as string;

  const rateLimit = checkRateLimit({
    key: rateLimitKey("classify-expense", user.id, companyId),
    limit: RATE_LIMIT_MAX_REQUESTS,
    windowMs: RATE_LIMIT_WINDOW_MS,
  });
  if (!rateLimit.allowed) {
    recordAuditEventDeferred(userClient, {
      companyId,
      action: "security.ai.classify_expense",
      entityType: "document",
      entityId: documentId,
      outcome: "denied",
      metadata: { reason: "rate_limited" },
    });
    return rateLimitResponse(rateLimit.retryAfterSeconds, CORS_HEADERS);
  }

  console.log(`[Classify][doc=${documentId}] user=${user.id} company=${companyId}`);
  recordAuditEventDeferred(userClient, {
    companyId,
    action: "security.ai.classify_expense",
    entityType: "document",
    entityId: documentId,
    outcome: "success",
    metadata: { model: CLASSIFICATION_MODEL, stage: "requested" },
  });

  // ── Load document data with service role (bypasses RLS for reads) ─────────
  const adminClient = createClient(supabaseUrl, serviceRoleKey);

  const { data: doc, error: docError } = await adminClient
    .from("documents")
    .select("id, company_id, expense_id, document_type, total_amount, extraction_clean")
    .eq("id", documentId)
    .eq("company_id", companyId)
    .single();

  if (docError || !doc) {
    console.error("Document fetch failed:", docError?.message);
    return jsonResponse({ success: false, error: "Document not found" });
  }

  const expenseId = doc.expense_id as string | null;
  if (!expenseId) {
    // No linked expense — classification will have nowhere to store the result
    console.log(`[Classify][doc=${documentId}] No expense_id — skipping`);
    return jsonResponse({ success: true, skipped: true, reason: "no_expense_linked" });
  }

  // ── Fetch company categories ──────────────────────────────────────────────
  const { data: categoriesRaw, error: catError } = await adminClient
    .from("categories")
    .select("id, name")
    .eq("company_id", companyId)
    .eq("is_active", true)
    .order("sort_order")
    .order("name");

  if (catError) {
    console.error("Categories fetch failed:", catError.message);
    return jsonResponse({ success: false, error: "Failed to fetch categories" });
  }

  const categories: Category[] = (categoriesRaw ?? []) as Category[];

  if (categories.length === 0) {
    console.log(`[Classify][doc=${documentId}] No categories for company ${companyId}`);
    return jsonResponse({ success: true, skipped: true, reason: "no_categories" });
  }

  // ── Build prompt from extraction data ────────────────────────────────────
  const extraction = (doc.extraction_clean as Record<string, unknown> | null) ?? {};
  const supplierName = typeof extraction["supplier_name"] === "string"
    ? extraction["supplier_name"]
    : null;
  const documentType = typeof doc.document_type === "string"
    ? doc.document_type
    : null;
  const totalAmount = typeof doc.total_amount === "number"
    ? doc.total_amount
    : null;
  const lineItems = Array.isArray(extraction["line_items"])
    ? (extraction["line_items"] as Array<Record<string, unknown>>)
    : [];

  const hasMinimalData = !supplierName && lineItems.length === 0;

  const prompt = buildPrompt(
    categories,
    supplierName,
    documentType,
    totalAmount,
    lineItems,
    hasMinimalData
  );

  console.log(`[Classify][doc=${documentId}] Calling ${CLASSIFICATION_MODEL}`);

  // ── Call OpenRouter ───────────────────────────────────────────────────────
  const classification = await callClassificationModel(prompt, openRouterKey);

  if (!classification) {
    console.error(`[Classify][doc=${documentId}] Model returned no usable result`);
    recordAuditEventDeferred(userClient, {
      companyId,
      action: "security.ai.classify_expense",
      entityType: "document",
      entityId: documentId,
      outcome: "failure",
      metadata: { reason: "no_usable_result" },
    });
    // Non-fatal — expense stays without category
    return jsonResponse({ success: false, error: "Classification model returned no result" });
  }

  console.log(
    `[Classify][doc=${documentId}] Result: "${classification.categoryName}" (${classification.confidence})`
  );

  // ── Match category name → category_id (case-insensitive) ─────────────────
  const normalizedResult = normalizeForMatch(classification.categoryName);
  const matched = categories.find(
    (c) => normalizeForMatch(c.name) === normalizedResult
  );

  const matchedCategoryId: string | null = matched?.id ?? null;

  if (!matched) {
    console.warn(
      `[Classify][doc=${documentId}] No match for "${classification.categoryName}" in company categories`
    );
  }

  // ── Update expense with classification ───────────────────────────────────
  const { error: updateError } = await adminClient
    .from("expenses")
    .update({
      category_id: matchedCategoryId,
      category_confidence: classification.confidence,
    })
    .eq("id", expenseId)
    .eq("company_id", companyId);

  if (updateError) {
    console.error(`[Classify][doc=${documentId}] Expense update failed:`, updateError.message);
    return jsonResponse({ success: false, error: "Failed to save classification" });
  }

  console.log(
    `[Classify][doc=${documentId}] Saved: category_id=${matchedCategoryId} confidence=${classification.confidence}`
  );

  return jsonResponse({
    success: true,
    category_id: matchedCategoryId,
    category_name: matched?.name ?? null,
    confidence: classification.confidence,
  });
});
