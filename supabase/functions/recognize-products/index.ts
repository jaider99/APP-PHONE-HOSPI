import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { HttpError, readJsonObject, requireStringField } from "../_shared/request.ts";
import { checkRateLimit, rateLimitKey, rateLimitResponse } from "../_shared/rate_limit.ts";
import { recordAuditEventDeferred } from "../_shared/audit.ts";

const OPENROUTER_ENDPOINT = "https://openrouter.ai/api/v1/chat/completions";
const NORMALIZATION_MODEL = "mistralai/mistral-7b-instruct:free";
const ANOMALY_MODEL = "mistralai/mistral-small-3.1-24b-instruct:free";
const STRONG_MATCH_THRESHOLD = 0.72;
const REVIEW_MATCH_THRESHOLD = 0.48;
const MAX_JSON_BYTES = 4_096;
const RATE_LIMIT_WINDOW_MS = 60_000;
const RATE_LIMIT_MAX_REQUESTS = 8;

type SupabaseAdminClient = ReturnType<typeof createClient<any, "public", any>>;

declare const EdgeRuntime: { waitUntil?: (promise: Promise<unknown>) => void } | undefined;

function runInBackground(label: string, task: () => Promise<unknown>): void {
  const promise = task().catch((e) => console.warn(`[${label}] Background task failed:`, e));
  if (typeof EdgeRuntime !== "undefined" && EdgeRuntime?.waitUntil) {
    EdgeRuntime.waitUntil(promise);
  }
}

// ─── CORS ─────────────────────────────────────────────────────────────────────

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...CORS_HEADERS },
  });
}

function openRouterHeaders(apiKey: string): Record<string, string> {
  return {
    Authorization: `Bearer ${apiKey}`,
    "Content-Type": "application/json",
    "HTTP-Referer": "https://hospidash.app",
    "X-Title": "HospiDash Product Recognition",
  };
}

// ─── Local Normalization (regex, no AI) ──────────────────────────────────────

/**
 * Lightweight normalization applied before the AI step.
 * Removes quantities, measurements, and cleans whitespace.
 */
function localNormalize(raw: string): string {
  return raw
    .toLowerCase()
    // Leading quantity + multiplier: "12x ", "6 x ", "2*"
    .replace(/^\d+\s*[×xX\*]\s*/u, "")
    // Leading standalone number: "3 chicken breasts"
    .replace(/^\d+\s+/, "")
    // Trailing measurements: " 500ml", " 1.5l", " 2kg", " 250g", etc.
    .replace(/\s+\d+(\.\d+)?\s*(ml|cl|dl|l|g|kg|oz|lb|fl\.?\s*oz)\b/gi, "")
    // Standalone trailing volume markers often arrive without explicit units: "0.7", "70", etc.
    .replace(/\s+\d+(?:[\.,]\d+)?\s*$/g, "")
    // Beverage ages are usually variant noise for canonical product names.
    .replace(/\b\d+\s*(anos|años|yrs?|years?)\b/gi, "")
    // Parenthesised sizes: "(1l)", "(500ml)", "(2x75cl)"
    .replace(/\s*\(\d[\w./×xX\s]*\)/gi, "")
    // Packaging at end: "x6", "x12", "x 6"
    .replace(/\s+x\s*\d+$/i, "")
    // Common packaging words that should not define the product identity.
    .replace(/\b(bottle|botella|btl|box|case|pack|caja|ud|uds|unitats|unidades|unitat|units)\b/gi, " ")
    // Remove most punctuation except hyphens and apostrophes
    .replace(/[^\w\s'\-]/g, " ")
    // Collapse spaces
    .replace(/\s+/g, " ")
    .trim();
}

// ─── AI Normalization (batch, single OpenRouter call) ─────────────────────────

/**
 * Batch-normalize product descriptions via OpenRouter.
 * Returns an array of cleaned names in the same order as input.
 * Falls back to localNormalize results if the call fails.
 */
async function aiNormalizeDescriptions(
  descriptions: string[],
  apiKey: string
): Promise<string[]> {
  if (descriptions.length === 0) return [];

  const inputJson = JSON.stringify(descriptions);
  const prompt =
    `You are a hospitality inventory assistant.\n` +
    `Normalize each product name: remove quantities, packaging, measurements.\n` +
    `Return ONLY a JSON array of strings, same count and order as input.\n\n` +
    `Examples:\n` +
    `Input: ["Campari 1L Bottle", "Olive Oil 500ml EVOO", "Chicken Breast 5kg Bag", "Prosecco DOC x6 75cl"]\n` +
    `Output: ["Campari", "Extra Virgin Olive Oil", "Chicken Breast", "Prosecco DOC"]\n\n` +
    `Input: ${inputJson}\n` +
    `Output:`;

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 25_000);

  try {
    const resp = await fetch(OPENROUTER_ENDPOINT, {
      method: "POST",
      headers: openRouterHeaders(apiKey),
      signal: controller.signal,
      body: JSON.stringify({
        model: NORMALIZATION_MODEL,
        messages: [{ role: "user", content: prompt }],
        max_tokens: 512,
        temperature: 0,
      }),
    });
    clearTimeout(timeout);

    if (!resp.ok) {
      console.warn(`[Normalize] OpenRouter ${resp.status} — skipping AI step`);
      return descriptions.map(localNormalize);
    }

    const data = await resp.json() as Record<string, unknown>;
    const choices = data["choices"] as Array<Record<string, unknown>> | undefined;
    const content = (choices?.[0]?.["message"] as Record<string, unknown> | undefined)?.["content"] as string | undefined;
    if (!content) return descriptions.map(localNormalize);

    // Extract JSON array from response
    const cleaned = content.replace(/^[\uFEFF\s]+/, "").trim();
    const match = cleaned.match(/\[[\s\S]*\]/);
    if (!match) return descriptions.map(localNormalize);

    const parsed = JSON.parse(match[0]) as unknown;
    if (!Array.isArray(parsed)) return descriptions.map(localNormalize);

    // Align output length with input length
    const result: string[] = descriptions.map((d, i) => {
      const ai = typeof parsed[i] === "string" ? (parsed[i] as string).trim() : "";
      return ai.length > 1 ? ai : localNormalize(d);
    });

    console.log("[Normalize] AI normalization successful");
    return result;
  } catch (e) {
    clearTimeout(timeout);
    console.warn("[Normalize] AI normalization failed, using regex fallback:", e);
    return descriptions.map(localNormalize);
  }
}

// ─── DB helpers: DB-level normalized key (mirrors generated column) ───────────

/**
 * Mirror the DB generated column logic:
 *   lower(trim(regexp_replace(immutable_unaccent(name), '[^a-zA-Z0-9]', '', 'g')))
 * Close enough for JS-side comparison; the canonical version is in Postgres.
 */
function jsNormalizeForDb(name: string): string {
  return name
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "") // strip diacritics
    .toLowerCase()
    .replace(/[^a-z0-9]/g, "")
    .trim();
}

function formatCanonicalProductName(name: string): string {
  return name
    .split(/\s+/)
    .filter((part) => part.trim().length > 0)
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1).toLowerCase())
    .join(" ");
}

function uniqueNonEmpty(values: Array<string | null | undefined>): string[] {
  const seen = new Set<string>();
  const result: string[] = [];

  for (const value of values) {
    const trimmed = value?.trim();
    if (!trimmed) continue;

    const key = trimmed.toLowerCase();
    if (!seen.has(key)) {
      seen.add(key);
      result.push(trimmed);
    }
  }

  return result;
}

interface ProductCandidate {
  product_id: string;
  product_name: string;
  alias_name: string | null;
  score: number;
  match_source: string;
}

interface AiCandidateChoice {
  product_id: string | null;
  confidence: number;
}

async function chooseCandidateWithAi(
  rawDescription: string,
  normalizedName: string,
  candidates: ProductCandidate[],
  apiKey: string
): Promise<AiCandidateChoice | null> {
  if (candidates.length === 0) return null;

  const prompt =
    `You match hospitality purchase line-items to an existing product catalogue.\n` +
    `Return ONLY JSON like {"product_id":"uuid"|null,"confidence":0.0-1.0}.\n` +
    `Choose null if none of the candidates is clearly the same product.\n\n` +
    `Raw line item: ${rawDescription}\n` +
    `Normalized item: ${normalizedName}\n\n` +
    `Candidates:\n${candidates
      .map((candidate, index) =>
        `${index + 1}. id=${candidate.product_id}; name=${candidate.product_name}; alias=${candidate.alias_name ?? "-"}; score=${candidate.score.toFixed(2)}; source=${candidate.match_source}`,
      )
      .join("\n")}`;

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 15_000);

  try {
    const resp = await fetch(OPENROUTER_ENDPOINT, {
      method: "POST",
      headers: openRouterHeaders(apiKey),
      signal: controller.signal,
      body: JSON.stringify({
        model: NORMALIZATION_MODEL,
        messages: [{ role: "user", content: prompt }],
        max_tokens: 120,
        temperature: 0,
      }),
    });
    clearTimeout(timeout);

    if (!resp.ok) {
      console.warn(`[Recognize] AI matcher returned ${resp.status}`);
      return null;
    }

    const data = await resp.json() as Record<string, unknown>;
    const choices = data["choices"] as Array<Record<string, unknown>> | undefined;
    const content = (choices?.[0]?.["message"] as Record<string, unknown> | undefined)?.["content"] as string | undefined;
    if (!content) return null;

    const cleaned = content.trim();
    const match = cleaned.match(/\{[\s\S]*\}/);
    if (!match) return null;

    const parsed = JSON.parse(match[0]) as Partial<AiCandidateChoice>;
    if (typeof parsed.confidence !== "number") return null;

    return {
      product_id: typeof parsed.product_id === "string" ? parsed.product_id : null,
      confidence: Math.max(0, Math.min(parsed.confidence, 1)),
    };
  } catch (e) {
    clearTimeout(timeout);
    console.warn("[Recognize] AI candidate disambiguation failed:", e);
    return null;
  }
}

async function ensureProductAliases(
  adminClient: SupabaseAdminClient,
  companyId: string,
  productId: string,
  aliases: string[]
): Promise<void> {
  for (const alias of aliases) {
    const { error } = await adminClient.from("product_aliases").insert({
      company_id: companyId,
      product_id: productId,
      raw_name: alias,
    });

    if (error && error.code !== "23505") {
      console.warn(`[Recognize] alias insert failed for ${productId}:`, error.message);
    }
  }
}

async function findExistingProductByNormalizedName(
  adminClient: SupabaseAdminClient,
  companyId: string,
  dbKey: string
): Promise<{ id: string; name: string } | null> {
  const { data, error } = await adminClient
    .from("products")
    .select("id, name, normalized_name, name_normalized")
    .eq("company_id", companyId)
    .eq("is_active", true)
    .or(`normalized_name.eq.${dbKey},name_normalized.eq.${dbKey}`)
    .limit(1)
    .maybeSingle();

  if (error) {
    console.warn("[Recognize] exact product lookup failed:", error.message);
    return null;
  }

  return data ? { id: data.id as string, name: data.name as string } : null;
}

// ─── Image generation ─────────────────────────────────────────────────────────

/**
 * Generate an AI product image via Pollinations.ai (free, no API key).
 * Downloads the PNG and uploads to Supabase Storage.
 * Fire-and-forget — errors are only logged, not propagated.
 */
async function generateAndStoreProductImage(
  adminClient: SupabaseAdminClient,
  companyId: string,
  productId: string,
  productName: string
): Promise<void> {
  try {
    const promptText = `studio product photo of ${productName}, clean white background, professional lighting, sharp detail, no text`;
    const encodedPrompt = encodeURIComponent(promptText);
    const imageUrl =
      `https://image.pollinations.ai/prompt/${encodedPrompt}` +
      `?width=512&height=512&model=flux&nologo=true`;

    console.log(`[Image][${productId}] Fetching from Pollinations: ${productName}`);

    const imgResp = await fetch(imageUrl, { signal: AbortSignal.timeout(45_000) });
    if (!imgResp.ok) {
      console.warn(`[Image][${productId}] Pollinations returned ${imgResp.status}`);
      return;
    }

    const imageBytes = new Uint8Array(await imgResp.arrayBuffer());
    const storagePath = `${companyId}/${productId}.jpg`;

    const { error: uploadError } = await adminClient.storage
      .from("products")
      .upload(storagePath, imageBytes, {
        contentType: "image/jpeg",
        upsert: true,
      });

    if (uploadError) {
      console.warn(`[Image][${productId}] Storage upload failed:`, uploadError.message);
      return;
    }

    // Get public URL
    const { data: urlData } = adminClient.storage
      .from("products")
      .getPublicUrl(storagePath);

    const publicUrl = urlData.publicUrl;

    const { error: updateError } = await adminClient
      .from("products")
      .update({ image_url: publicUrl })
      .eq("id", productId);

    if (updateError) {
      console.warn(`[Image][${productId}] products.image_url update failed:`, updateError.message);
      return;
    }

    console.log(`[Image][${productId}] ✓ Stored at ${publicUrl}`);
  } catch (e) {
    console.warn(`[Image][${productId}] Exception during image generation:`, e);
  }
}

// ─── Document item type ───────────────────────────────────────────────────────

interface DocumentItem {
  id: string;
  description: string | null;
  quantity: number | null;
  unit_price: number | null;
  unit_type: string | null;
  line_total: number | null;
  product_id: string | null;
}

interface DocumentAccessRow {
  id: string;
  company_id: string;
  provider_id: string | null;
  document_date: string | null;
  category_id: string | null;
  currency: string | null;
}

interface PriceObservation {
  productPriceId: string;
  productId: string;
  documentItemId: string;
  supplierId: string | null;
  price: number;
  quantity: number | null;
  unit: string | null;
  date: string | null;
  rawDescription: string | null;
  lineTotal: number | null;
}

interface HistoricalPriceRow {
  id: string;
  price: number;
  quantity: number | null;
  supplier_id: string | null;
  date: string | null;
  observed_at: string;
  providers?: { name?: string | null } | null;
}

interface ProductContextRow {
  id: string;
  name: string;
}

interface ProviderContextRow {
  id: string;
  name: string;
}

interface HeuristicAnomaly {
  anomaly_type: string;
  current_price: number | null;
  expected_price: number | null;
  deviation_percent: number | null;
  severity: "low" | "medium" | "high" | "critical";
  confidence_score: number;
  explanation: string;
  heuristic_details: Record<string, unknown>;
}

interface AiAnomalyReview {
  severity?: "low" | "medium" | "high" | "critical";
  confidence?: number;
  explanation?: string;
}

function clamp01(value: number): number {
  return Math.max(0, Math.min(1, value));
}

function average(values: number[]): number | null {
  const clean = values.filter((value) => Number.isFinite(value));
  if (clean.length === 0) return null;
  return clean.reduce((sum, value) => sum + value, 0) / clean.length;
}

function stddev(values: number[]): number {
  const avg = average(values);
  if (avg == null || values.length < 2) return 0;
  const variance = values.reduce((sum, value) => sum + Math.pow(value - avg, 2), 0) / (values.length - 1);
  return Math.sqrt(variance);
}

function deviationPercent(current: number, expected: number): number {
  if (!Number.isFinite(expected) || expected <= 0) return 0;
  return ((current - expected) / expected) * 100;
}

function severityFromDeviation(percent: number): "low" | "medium" | "high" | "critical" {
  if (percent >= 50) return "critical";
  if (percent >= 35) return "high";
  if (percent >= 20) return "medium";
  return "low";
}

function confidenceFromHistory(sampleCount: number, values: number[], aiConfidence?: number | null): number {
  const avg = average(values) ?? 0;
  const coefficientOfVariation = avg > 0 ? stddev(values) / avg : 1;
  const historicalConsistency = clamp01(1 - Math.min(coefficientOfVariation, 1));
  const frequency = clamp01(sampleCount / 10);
  const deterministicConfidence = (historicalConsistency * 0.45) + (frequency * 0.55);
  if (aiConfidence == null) return clamp01(deterministicConfidence);
  return clamp01((deterministicConfidence * 0.75) + (aiConfidence * 0.25));
}

function parsePurchaseDate(value: string | null, observedAt?: string): Date {
  const source = value ? `${value}T12:00:00.000Z` : observedAt;
  const parsed = source ? new Date(source) : new Date();
  return Number.isNaN(parsed.getTime()) ? new Date() : parsed;
}

async function askAiForAnomalyReview(
  anomaly: HeuristicAnomaly,
  productName: string,
  supplierName: string | null,
  recentPrices: number[],
  apiKey?: string,
): Promise<AiAnomalyReview | null> {
  if (!apiKey) return null;

  const payload = {
    product: productName,
    supplier: supplierName,
    anomaly_type: anomaly.anomaly_type,
    current_price: anomaly.current_price,
    expected_price: anomaly.expected_price,
    deviation_percent: anomaly.deviation_percent,
    heuristic_severity: anomaly.severity,
    heuristic_confidence: anomaly.confidence_score,
    recent_prices: recentPrices.slice(0, 10),
    heuristic_details: anomaly.heuristic_details,
  };

  const prompt =
    `You review deterministic hospitality purchasing anomaly detections.\n` +
    `Heuristics are source of truth. Do not invent new anomalies.\n` +
    `Return ONLY JSON: {"severity":"low|medium|high|critical","confidence":0.0-1.0,"explanation":"short user-facing sentence"}.\n\n` +
    `Detection:\n${JSON.stringify(payload)}`;

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 12_000);

  try {
    const resp = await fetch(OPENROUTER_ENDPOINT, {
      method: "POST",
      headers: openRouterHeaders(apiKey),
      signal: controller.signal,
      body: JSON.stringify({
        model: ANOMALY_MODEL,
        messages: [{ role: "user", content: prompt }],
        max_tokens: 180,
        temperature: 0,
      }),
    });
    clearTimeout(timeout);

    if (!resp.ok) {
      console.warn(`[AnomalyAI] OpenRouter returned ${resp.status}`);
      return null;
    }

    const data = await resp.json() as Record<string, unknown>;
    const choices = data["choices"] as Array<Record<string, unknown>> | undefined;
    const content = (choices?.[0]?.["message"] as Record<string, unknown> | undefined)?.["content"] as string | undefined;
    const match = content?.match(/\{[\s\S]*\}/);
    if (!match) return null;

    const parsed = JSON.parse(match[0]) as AiAnomalyReview;
    if (parsed.confidence != null) parsed.confidence = clamp01(parsed.confidence);
    return parsed;
  } catch (e) {
    clearTimeout(timeout);
    console.warn("[AnomalyAI] Review failed:", e);
    return null;
  }
}

async function insertAnomaly(
  adminClient: SupabaseAdminClient,
  companyId: string,
  documentId: string,
  observation: PriceObservation,
  anomaly: HeuristicAnomaly,
  productName: string,
  supplierName: string | null,
  recentPrices: number[],
  openRouterKey?: string,
): Promise<void> {
  const aiReview = await askAiForAnomalyReview(
    anomaly,
    productName,
    supplierName,
    recentPrices,
    openRouterKey,
  );

  const confidenceScore = confidenceFromHistory(
    Number(anomaly.heuristic_details["sample_count"] ?? recentPrices.length),
    recentPrices,
    aiReview?.confidence,
  );

  const { error } = await adminClient
    .from("price_anomalies")
    .upsert({
      company_id: companyId,
      product_id: observation.productId,
      supplier_id: observation.supplierId,
      document_id: documentId,
      document_item_id: observation.documentItemId,
      product_price_id: observation.productPriceId,
      anomaly_type: anomaly.anomaly_type,
      current_price: anomaly.current_price,
      expected_price: anomaly.expected_price,
      deviation_percent: anomaly.deviation_percent,
      severity: aiReview?.severity ?? anomaly.severity,
      confidence_score: confidenceScore,
      explanation: aiReview?.explanation ?? anomaly.explanation,
      heuristic_details: anomaly.heuristic_details,
      ai_confidence: aiReview?.confidence ?? null,
      ai_explanation: aiReview?.explanation ?? null,
    }, {
      onConflict: "company_id,product_price_id,anomaly_type",
    });

  if (error) {
    console.warn(`[Anomaly] insert failed type=${anomaly.anomaly_type} product=${observation.productId}:`, error.message);
  }
}

async function detectAnomaliesForPrice(
  adminClient: SupabaseAdminClient,
  companyId: string,
  documentId: string,
  observation: PriceObservation,
  openRouterKey?: string,
): Promise<void> {
  await adminClient.rpc("refresh_product_price_stats", {
    p_company_id: companyId,
    p_product_id: observation.productId,
  });

  const [{ data: product }, { data: supplier }, { data: history }] = await Promise.all([
    adminClient
      .from("products")
      .select("id, name")
      .eq("company_id", companyId)
      .eq("id", observation.productId)
      .maybeSingle(),
    observation.supplierId
      ? adminClient
          .from("providers")
          .select("id, name")
          .eq("company_id", companyId)
          .eq("id", observation.supplierId)
          .maybeSingle()
      : Promise.resolve({ data: null }),
    adminClient
      .from("product_prices")
      .select("id, price, quantity, supplier_id, date, observed_at, providers(name)")
      .eq("company_id", companyId)
      .eq("product_id", observation.productId)
      .neq("id", observation.productPriceId)
      .order("observed_at", { ascending: false })
      .limit(80),
  ]);

  const productName = ((product as ProductContextRow | null)?.name ?? observation.rawDescription ?? "Product");
  const supplierName = (supplier as ProviderContextRow | null)?.name ?? null;
  const rows = (history ?? []) as HistoricalPriceRow[];
  const historicalPrices = rows.map((row) => Number(row.price)).filter((value) => value > 0);
  const recentTen = historicalPrices.slice(0, 10);
  const anomalies: HeuristicAnomaly[] = [];

  if (recentTen.length >= 3) {
    const expected = average(recentTen);
    if (expected != null) {
      const deviation = deviationPercent(observation.price, expected);
      if (deviation >= 10) {
        anomalies.push({
          anomaly_type: "price_spike",
          current_price: observation.price,
          expected_price: expected,
          deviation_percent: deviation,
          severity: severityFromDeviation(deviation),
          confidence_score: confidenceFromHistory(recentTen.length, recentTen),
          explanation: `${productName} is ${deviation.toFixed(0)}% above its recent average.`,
          heuristic_details: {
            rule: "current price > average(last 10 purchases)",
            sample_count: recentTen.length,
            recent_average: expected,
            recent_prices: recentTen,
          },
        });
      }
    }
  }

  const supplierGroups = new Map<string, { name: string; prices: number[] }>();
  for (const row of rows) {
    if (!row.supplier_id || row.price == null || Number(row.price) <= 0) continue;
    const name = row.providers?.name ?? "Unknown supplier";
    const group = supplierGroups.get(row.supplier_id) ?? { name, prices: [] };
    group.prices.push(Number(row.price));
    supplierGroups.set(row.supplier_id, group);
  }
  if (observation.supplierId && observation.price > 0) {
    const group = supplierGroups.get(observation.supplierId) ?? { name: supplierName ?? "Current supplier", prices: [] };
    group.prices.unshift(observation.price);
    supplierGroups.set(observation.supplierId, group);
  }

  const supplierAverages = [...supplierGroups.entries()]
    .map(([supplierId, group]) => ({
      supplierId,
      supplierName: group.name,
      averagePrice: average(group.prices),
      purchaseCount: group.prices.length,
    }))
    .filter((entry): entry is { supplierId: string; supplierName: string; averagePrice: number; purchaseCount: number } =>
      entry.averagePrice != null && entry.purchaseCount > 0,
    )
    .sort((a, b) => a.averagePrice - b.averagePrice);

  if (observation.supplierId && supplierAverages.length >= 2) {
    const currentSupplier = supplierAverages.find((entry) => entry.supplierId === observation.supplierId);
    const cheapest = supplierAverages[0];
    if (currentSupplier && cheapest && currentSupplier.supplierId !== cheapest.supplierId) {
      const deviation = deviationPercent(currentSupplier.averagePrice, cheapest.averagePrice);
      if (deviation >= 10) {
        anomalies.push({
          anomaly_type: "supplier_overpricing",
          current_price: currentSupplier.averagePrice,
          expected_price: cheapest.averagePrice,
          deviation_percent: deviation,
          severity: severityFromDeviation(deviation),
          confidence_score: clamp01(Math.min(currentSupplier.purchaseCount, cheapest.purchaseCount) / 5),
          explanation: `${currentSupplier.supplierName} is ${deviation.toFixed(0)}% more expensive than ${cheapest.supplierName} for ${productName}.`,
          heuristic_details: {
            rule: "current supplier average > cheapest supplier average",
            sample_count: historicalPrices.length + 1,
            current_supplier: currentSupplier,
            cheapest_supplier: cheapest,
            supplier_averages: supplierAverages,
          },
        });
      }
    }
  }

  const currentDate = parsePurchaseDate(observation.date);
  const withCurrent = [
    { price: observation.price, date: currentDate },
    ...rows.map((row) => ({ price: Number(row.price), date: parsePurchaseDate(row.date, row.observed_at) })),
  ].filter((row) => row.price > 0);
  const recent30 = withCurrent
    .filter((row) => currentDate.getTime() - row.date.getTime() <= 30 * 24 * 60 * 60 * 1000)
    .map((row) => row.price);
  const prior30 = withCurrent
    .filter((row) => {
      const delta = currentDate.getTime() - row.date.getTime();
      return delta > 30 * 24 * 60 * 60 * 1000 && delta <= 60 * 24 * 60 * 60 * 1000;
    })
    .map((row) => row.price);
  const recent30Avg = average(recent30);
  const prior30Avg = average(prior30);
  if (recent30.length >= 3 && prior30.length >= 3 && recent30Avg != null && prior30Avg != null) {
    const trendDeviation = deviationPercent(recent30Avg, prior30Avg);
    if (trendDeviation >= 10) {
      anomalies.push({
        anomaly_type: "inflation_trend",
        current_price: recent30Avg,
        expected_price: prior30Avg,
        deviation_percent: trendDeviation,
        severity: severityFromDeviation(trendDeviation),
        confidence_score: confidenceFromHistory(recent30.length + prior30.length, [...recent30, ...prior30]),
        explanation: `${productName} has risen ${trendDeviation.toFixed(0)}% versus the prior 30-day period.`,
        heuristic_details: {
          rule: "30-day moving average > previous 30-day moving average",
          sample_count: recent30.length + prior30.length,
          recent_30_day_average: recent30Avg,
          prior_30_day_average: prior30Avg,
        },
      });
    }
  }

  const historicalQuantities = rows
    .map((row) => row.quantity == null ? null : Number(row.quantity))
    .filter((value): value is number => value != null && value > 0)
    .slice(0, 20);
  if (observation.quantity != null && historicalQuantities.length >= 3) {
    const expectedQuantity = average(historicalQuantities);
    if (expectedQuantity != null) {
      const quantityDeviation = deviationPercent(observation.quantity, expectedQuantity);
      if (quantityDeviation >= 100 || observation.quantity > expectedQuantity + (stddev(historicalQuantities) * 3)) {
        anomalies.push({
          anomaly_type: "quantity_anomaly",
          current_price: observation.quantity,
          expected_price: expectedQuantity,
          deviation_percent: quantityDeviation,
          severity: quantityDeviation >= 400 ? "critical" : quantityDeviation >= 250 ? "high" : "medium",
          confidence_score: confidenceFromHistory(historicalQuantities.length, historicalQuantities),
          explanation: `${productName} quantity is unusually high versus normal purchases.`,
          heuristic_details: {
            rule: "quantity > historical average by 100% or more / 3 stddev",
            sample_count: historicalQuantities.length,
            quantity_average: expectedQuantity,
            historical_quantities: historicalQuantities,
          },
        });
      }
    }
  }

  for (const anomaly of anomalies) {
    await insertAnomaly(
      adminClient,
      companyId,
      documentId,
      observation,
      anomaly,
      productName,
      supplierName,
      recentTen.length > 0 ? recentTen : historicalPrices.slice(0, 10),
      openRouterKey,
    );
  }
}

async function detectDuplicatePricePattern(
  adminClient: SupabaseAdminClient,
  companyId: string,
  documentId: string,
  supplierId: string | null,
  observations: PriceObservation[],
): Promise<void> {
  if (observations.length === 0) return;

  const parts = observations
    .map((obs) => `${obs.productId}:${(obs.quantity ?? 0).toFixed(3)}:${obs.price.toFixed(4)}`)
    .sort();
  const fingerprintInput = parts.join("|");
  const fingerprintBytes = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(fingerprintInput));
  const fingerprintHash = [...new Uint8Array(fingerprintBytes)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
  const totalPrice = observations.reduce((sum, obs) => sum + (obs.lineTotal ?? ((obs.quantity ?? 1) * obs.price)), 0);

  const { data: existing } = await adminClient
    .from("product_purchase_fingerprints")
    .select("document_id, created_at")
    .eq("company_id", companyId)
    .eq("fingerprint_hash", fingerprintHash)
    .neq("document_id", documentId)
    .order("created_at", { ascending: false })
    .limit(1);

  await adminClient
    .from("product_purchase_fingerprints")
    .upsert({
      company_id: companyId,
      document_id: documentId,
      supplier_id: supplierId,
      fingerprint_hash: fingerprintHash,
      line_count: observations.length,
      total_price: totalPrice,
      product_ids: observations.map((obs) => obs.productId),
    }, {
      onConflict: "company_id,document_id",
    });

  const duplicate = existing?.[0];
  if (!duplicate) return;

  const first = observations[0];
  await insertAnomaly(
    adminClient,
    companyId,
    documentId,
    first,
    {
      anomaly_type: "duplicate_price_pattern",
      current_price: totalPrice,
      expected_price: totalPrice,
      deviation_percent: 0,
      severity: "high",
      confidence_score: 0.95,
      explanation: `This document has the same product, quantity, and price pattern as a previous upload.`,
      heuristic_details: {
        rule: "same product fingerprint hash already exists for company",
        matching_document_id: duplicate.document_id,
        fingerprint_hash: fingerprintHash,
        line_count: observations.length,
      },
    },
    first.rawDescription ?? "Document products",
    null,
    observations.map((obs) => obs.price),
  );
}

async function runPriceAnomalyDetection(
  adminClient: SupabaseAdminClient,
  companyId: string,
  documentId: string,
  supplierId: string | null,
  observations: PriceObservation[],
  openRouterKey?: string,
): Promise<void> {
  if (observations.length === 0) return;

  await detectDuplicatePricePattern(adminClient, companyId, documentId, supplierId, observations);

  for (const observation of observations) {
    try {
      await detectAnomaliesForPrice(adminClient, companyId, documentId, observation, openRouterKey);
    } catch (e) {
      console.warn(`[Anomaly] detection failed price=${observation.productPriceId}:`, e);
    }
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
    return jsonResponse({ error: "Invalid or expired token" }, 401);
  }

  // RLS check: confirm user can access this document
  const { data: accessCheck, error: accessError } = await userClient
    .from("documents")
    .select("id, company_id, provider_id, document_date, category_id, currency")
    .eq("id", documentId)
    .maybeSingle();

  if (accessError || !accessCheck) {
    console.error(
      "[Recognize] Access denied for document:", documentId,
      "user:", user.id,
      "error:", accessError?.message
    );
    return jsonResponse({ error: "Document not found or access denied" }, 403);
  }

  // Derive company_id from DB — NEVER trust client-supplied value
  const companyId = accessCheck.company_id as string;
  const documentRow = accessCheck as DocumentAccessRow;

  const rateLimit = checkRateLimit({
    key: rateLimitKey("recognize-products", user.id, companyId),
    limit: RATE_LIMIT_MAX_REQUESTS,
    windowMs: RATE_LIMIT_WINDOW_MS,
  });
  if (!rateLimit.allowed) {
    recordAuditEventDeferred(userClient, {
      companyId,
      action: "security.ai.recognize_products",
      entityType: "document",
      entityId: documentId,
      outcome: "denied",
      metadata: { reason: "rate_limited" },
    });
    return rateLimitResponse(rateLimit.retryAfterSeconds, CORS_HEADERS);
  }

  console.log(`[Recognize][doc=${documentId}] user=${user.id} company=${companyId}`);
  recordAuditEventDeferred(userClient, {
    companyId,
    action: "security.ai.recognize_products",
    entityType: "document",
    entityId: documentId,
    outcome: "success",
    metadata: { uses_openrouter: openRouterKey != null, stage: "requested" },
  });

  const adminClient: SupabaseAdminClient = createClient(supabaseUrl, serviceRoleKey);

  // ── Fetch document_items ──────────────────────────────────────────────────
  const { data: items, error: itemsError } = await adminClient
    .from("document_items")
    .select("id, description, quantity, unit_price, unit_type, line_total, product_id")
    .eq("document_id", documentId)
    .eq("company_id", companyId);

  if (itemsError) {
    console.error("[Recognize] Failed to fetch document_items:", itemsError.message);
    recordAuditEventDeferred(userClient, {
      companyId,
      action: "security.ai.recognize_products",
      entityType: "document",
      entityId: documentId,
      outcome: "failure",
      metadata: { reason: "document_items_fetch_failed" },
    });
    return jsonResponse({ success: false, error: "Failed to fetch items" }, 500);
  }

  if (!items || items.length === 0) {
    console.log(`[Recognize][doc=${documentId}] No document_items found`);
    return jsonResponse({ success: true, matched: 0, created: 0, message: "No items" });
  }

  const workableItems = (items as DocumentItem[]).filter(
    (item) => item.description && item.description.trim().length > 1
  );

  if (workableItems.length === 0) {
    return jsonResponse({ success: true, matched: 0, created: 0, message: "No items with descriptions" });
  }

  // ── Step 1: Normalize descriptions ───────────────────────────────────────
  const rawDescriptions = workableItems.map((item) => item.description!.trim());

  let normalizedNames: string[];
  if (openRouterKey) {
    normalizedNames = await aiNormalizeDescriptions(rawDescriptions, openRouterKey);
  } else {
    console.warn("[Recognize] OPENROUTER_API_KEY not set — using regex normalization only");
    normalizedNames = rawDescriptions.map(localNormalize);
  }

  // ── Step 2: Match or create products ─────────────────────────────────────
  let matchedCount = 0;
  let createdCount = 0;
  const newProductIds: string[] = [];
  const priceObservations: PriceObservation[] = [];
  const productResolutionCache = new Map<string, {
    productId: string;
    matchedName: string | null;
    confidenceScore: number | null;
    matchedAutomatically: boolean;
  }>();

  for (let i = 0; i < workableItems.length; i++) {
    const item = workableItems[i];
    const cleanedName = normalizedNames[i];
    const dbKey = jsNormalizeForDb(cleanedName);
    const canonicalName = formatCanonicalProductName(cleanedName);

    if (!dbKey) {
      console.warn(`[Recognize] skipping item with empty normalized key: ${item.description}`);
      continue;
    }

    console.log(`[Recognize] Item "${item.description}" → normalized "${cleanedName}" → key "${dbKey}"`);

    // --- Exact alias/product hit first ---
    let productId: string | null = null;
    let matchedName: string | null = null;
    let confidenceScore: number | null = null;
    let matchedAutomatically = true;

    const cachedMatch = productResolutionCache.get(dbKey);
    if (cachedMatch) {
      productId = cachedMatch.productId;
      matchedName = cachedMatch.matchedName;
      confidenceScore = cachedMatch.confidenceScore;
      matchedAutomatically = cachedMatch.matchedAutomatically;
      matchedCount++;
      console.log(`[ProductMatching] CACHE "${item.description}" → "${matchedName ?? productId}"`);
    }

    if (!productId) {
      try {
        const { data: aliasMatch, error: aliasError } = await adminClient.rpc(
          "find_product_alias_match",
          {
            p_company_id: companyId,
            p_normalized_name: dbKey,
          },
        );

        if (aliasError) {
          console.warn("[Recognize] alias match RPC error:", aliasError.message);
        } else if (aliasMatch && aliasMatch.length > 0) {
          const best = aliasMatch[0] as {
            product_id: string;
            product_name: string;
          };
          productId = best.product_id;
          matchedName = best.product_name;
          confidenceScore = 0.99;
          matchedCount++;
          console.log(`[ProductMatching] EXACT alias "${item.description}" → "${matchedName}"`);
        }
      } catch (e) {
        console.warn("[Recognize] Alias match RPC exception:", e);
      }
    }

    if (!productId) {
      try {
        const { data: candidates, error: candidatesError } = await adminClient.rpc(
          "find_product_candidates",
          {
            p_company_id: companyId,
            p_normalized_name: dbKey,
            p_limit: 5,
          },
        );

        if (candidatesError) {
          console.warn("[Recognize] candidate RPC error:", candidatesError.message);
        } else if (candidates && candidates.length > 0) {
          const typedCandidates = (candidates as ProductCandidate[]).filter(
            (candidate) => typeof candidate.product_id === "string" && candidate.product_id.length > 0,
          );
          const best = typedCandidates[0];
          const secondBest = typedCandidates.length > 1 ? typedCandidates[1] : null;

          if (best &&
              (best.score >= STRONG_MATCH_THRESHOLD ||
                  (best.score >= 0.62 &&
                      (secondBest == null || best.score - secondBest.score >= 0.08)))) {
            productId = best.product_id;
            matchedName = best.product_name;
            confidenceScore = best.score;
            matchedCount++;
            console.log(`[Recognize] FUZZY match "${item.description}" → "${matchedName}" (score=${best.score.toFixed(2)})`);
          } else if (best && best.score >= REVIEW_MATCH_THRESHOLD && openRouterKey) {
            const aiChoice = await chooseCandidateWithAi(
              item.description ?? cleanedName,
              canonicalName,
              typedCandidates.slice(0, 3),
              openRouterKey,
            );

            if (aiChoice?.product_id && aiChoice.confidence >= 0.74) {
              const chosen = typedCandidates.find(
                (candidate) => candidate.product_id === aiChoice.product_id,
              );
              if (chosen) {
                productId = chosen.product_id;
                matchedName = chosen.product_name;
                confidenceScore = Math.max(chosen.score, aiChoice.confidence);
                matchedCount++;
                console.log(`[ProductMatching] AI "${item.description}" → "${matchedName}" (score=${confidenceScore.toFixed(2)})`);
              }
            } else if (aiChoice?.product_id) {
              matchedAutomatically = false;
            }
          }
        }
      } catch (e) {
        console.warn("[Recognize] candidate RPC exception:", e);
      }
    }

    if (!productId) {
      const exactProduct = await findExistingProductByNormalizedName(adminClient, companyId, dbKey);
      if (exactProduct) {
        productId = exactProduct.id;
        matchedName = exactProduct.name;
        confidenceScore = 0.95;
        matchedCount++;
        console.log(`[ProductMatching] EXACT product "${item.description}" → "${matchedName}"`);
      }
    }

    // --- Create new product if no match ---
    if (!productId) {
      const { data: newProduct, error: insertError } = await adminClient
        .from("products")
        .insert({
          company_id: companyId,
          name: canonicalName,
          category_id: documentRow.category_id,
          currency: documentRow.currency ?? "EUR",
          is_active: true,
        })
        .select("id, name")
        .single();

      if (insertError) {
        if (insertError.code === "23505") {
          const existing = await findExistingProductByNormalizedName(adminClient, companyId, dbKey);
          if (existing) {
            productId = existing.id;
            matchedName = existing.name;
            confidenceScore = 0.94;
            console.log(`[ProductMatching] EXISTING (conflict) "${canonicalName}" → ${productId}`);
            matchedCount++;
          }
        } else {
          console.error(`[Recognize] Product insert failed for "${canonicalName}":`, insertError.message);
          continue; // skip this item — don't block others
        }
      } else if (newProduct) {
        productId = newProduct.id as string;
        matchedName = newProduct.name as string;
        confidenceScore = 0.93;
        newProductIds.push(productId);
        createdCount++;
        console.log(`[ProductCreated] "${canonicalName}" → ${productId}`);
      }
    }

    if (!productId) continue;

    productResolutionCache.set(dbKey, {
      productId,
      matchedName,
      confidenceScore,
      matchedAutomatically,
    });

    await ensureProductAliases(
      adminClient,
      companyId,
      productId,
      uniqueNonEmpty([item.description, cleanedName, canonicalName]),
    );

    if (documentRow.category_id) {
      const { error: enrichError } = await adminClient
        .from("products")
        .update({ category_id: documentRow.category_id })
        .eq("id", productId)
        .eq("company_id", companyId)
        .is("category_id", null);
      if (enrichError) {
        console.warn(`[Recognize] category enrichment failed for ${productId}:`, enrichError.message);
      }
    }

    // --- Update document_item.product_id ---
    const { error: updateItemError } = await adminClient
      .from("document_items")
      .update({
        product_id: productId,
        normalized_description: dbKey,
        matched_automatically: matchedAutomatically,
        confidence_score: confidenceScore ?? (productId ? 0.9 : null),
        // Link item to the document's supplier so per-item supplier analytics
        // work without having to join through the parent document.
        supplier_id: documentRow.provider_id ?? null,
      })
      .eq("id", item.id);

    if (updateItemError) {
      console.warn(`[Recognize] document_items update failed for ${item.id}:`, updateItemError.message);
    } else {
      console.log(`[ProductLinked] item=${item.id} product=${productId}`);
    }

    // --- Insert product_prices record ---
    const unitPrice = item.unit_price ??
      (item.line_total != null && item.quantity != null && item.quantity > 0
        ? item.line_total / item.quantity
        : null);

    if (unitPrice != null && unitPrice > 0) {
      const observedAt = documentRow.document_date
        ? new Date(`${documentRow.document_date}T12:00:00.000Z`).toISOString()
        : new Date().toISOString();

      const { data: priceRow, error: priceError } = await adminClient
        .from("product_prices")
        .upsert({
          company_id: companyId,
          product_id: productId,
          document_id: documentId,
          document_item_id: item.id,
          supplier_id: documentRow.provider_id,
          price: unitPrice,
          quantity: item.quantity,
          unit: item.unit_type,
          date: documentRow.document_date,
          observed_at: observedAt,
        }, {
          onConflict: "document_item_id",
        })
        .select("id")
        .single();

      if (priceError) {
        console.warn(`[Recognize] product_prices insert failed:`, priceError.message);
      } else {
        console.log(`[Recognize] PRICE inserted product=${productId} price=${unitPrice}`);
        if (priceRow?.id) {
          priceObservations.push({
            productPriceId: priceRow.id as string,
            productId,
            documentItemId: item.id,
            supplierId: documentRow.provider_id,
            price: unitPrice,
            quantity: item.quantity,
            unit: item.unit_type,
            date: documentRow.document_date,
            rawDescription: item.description,
            lineTotal: item.line_total,
          });
        }
      }

      const { error: productPriceUpdateError } = await adminClient
        .from("products")
        .update({
          unit_price: unitPrice,
          currency: documentRow.currency ?? "EUR",
          unit_type: item.unit_type ?? "unit",
        })
        .eq("id", productId)
        .eq("company_id", companyId);

      if (productPriceUpdateError) {
        console.warn(`[Recognize] product snapshot update failed for ${productId}:`, productPriceUpdateError.message);
      }
    }
  }

  // ── Step 3: Generate images for new products (async, non-blocking) ────────
  if (newProductIds.length > 0) {
    // Kick off image generation asynchronously; failures are only logged
    runInBackground("Image", async () => {
      for (const productId of newProductIds) {
        // Look up the product name we just created
        const { data: prod } = await adminClient
          .from("products")
          .select("name")
          .eq("id", productId)
          .single();

        if (prod?.name) {
          await generateAndStoreProductImage(adminClient, companyId, productId, prod.name as string);
        }
      }
    });
  }

  // ── Step 4: Price anomaly detection (async, non-blocking) ────────────────
  if (priceObservations.length > 0) {
    runInBackground("Anomaly", async () => {
      await runPriceAnomalyDetection(
        adminClient,
        companyId,
        documentId,
        documentRow.provider_id,
        priceObservations,
        openRouterKey ?? undefined,
      );
    });
  }

  // ── Done ──────────────────────────────────────────────────────────────────
  console.log(
    `[Recognize][doc=${documentId}] Done — matched=${matchedCount} created=${createdCount} items=${workableItems.length}`
  );

  return jsonResponse({
    success: true,
    matched: matchedCount,
    created: createdCount,
    total_items: workableItems.length,
  });
});
