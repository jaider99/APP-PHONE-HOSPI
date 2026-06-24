import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { HttpError, readJsonObject, requireStringField } from "../_shared/request.ts";
import { checkRateLimit, rateLimitKey, rateLimitResponse } from "../_shared/rate_limit.ts";
import { logError, logInfo } from "../_shared/redact.ts";

const OPENROUTER_ENDPOINT = "https://openrouter.ai/api/v1/chat/completions";
const MODEL = "nvidia/nemotron-3-super-120b";
const MAX_JSON_BYTES = 24_000;
const MAX_RAW_TEXT_CHARS = 12_000;
const OPENROUTER_TIMEOUT_MS = 20_000;
const RATE_LIMIT_WINDOW_MS = 60_000;
const RATE_LIMIT_MAX_REQUESTS = 12;

const jsonHeaders = {
  "Content-Type": "application/json",
};

interface OpenRouterChatResponse {
  choices?: Array<{
    message?: {
      content?: unknown;
    };
  }>;
}

interface ClassificationExtraction {
  document_type?: unknown;
  confidence?: unknown;
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: jsonHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return jsonResponse({ error: "Missing authorization" }, 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });

  const { data: { user }, error: userError } = await userClient.auth.getUser();
  if (userError || !user) {
    return jsonResponse({ error: "Invalid or expired token" }, 401);
  }

  const rateLimit = checkRateLimit({
    key: rateLimitKey("classify-document-type", user.id),
    limit: RATE_LIMIT_MAX_REQUESTS,
    windowMs: RATE_LIMIT_WINDOW_MS,
  });
  if (!rateLimit.allowed) {
    return rateLimitResponse(rateLimit.retryAfterSeconds, jsonHeaders);
  }

  try {
    const body = await readJsonObject(req, {
      maxBytes: MAX_JSON_BYTES,
      allowedFields: ["rawText"],
    });
    const rawText = requireStringField(body, "rawText", {
      maxLength: MAX_RAW_TEXT_CHARS,
    });

    const apiKey = Deno.env.get("OPENROUTER_API_KEY");
    if (!apiKey) {
      throw new Error("OPENROUTER_API_KEY not configured");
    }

    logInfo(`[classify-document-type] calling model=${MODEL}`);
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), OPENROUTER_TIMEOUT_MS);
    let response: Response;
    try {
      response = await fetch(OPENROUTER_ENDPOINT, {
        method: "POST",
        signal: controller.signal,
        headers: {
          Authorization: `Bearer ${apiKey}`,
          "Content-Type": "application/json",
          "HTTP-Referer": "https://hospidash.app",
          "X-Title": "HospiDash Document Type Classifier",
        },
        body: JSON.stringify({
          model: MODEL,
          messages: [
            {
              role: "user",
              content: classificationPrompt(rawText),
            },
          ],
          max_tokens: 300,
          temperature: 0,
        }),
      });
    } finally {
      clearTimeout(timeoutId);
    }

    if (!response.ok) {
      await response.body?.cancel();
      throw new Error(`OpenRouter error ${response.status}`);
    }

    const json = await response.json() as OpenRouterChatResponse;
    const content = String(json?.choices?.[0]?.message?.content ?? "");
    const parsed = parseExtraction(content);
    if (!parsed) {
      throw new Error("Could not parse classifier response");
    }

    return jsonResponse(
      {
        document_type: normalizeDocumentType(parsed.document_type),
        confidence: normalizeConfidence(parsed.confidence),
      },
      200,
    );
  } catch (error) {
    if (error instanceof HttpError) {
      return jsonResponse({ error: error.message }, error.status);
    }

    const message = error instanceof Error ? error.message : String(error);
    logError(`[classify-document-type] ERROR: ${message}`);
    return jsonResponse({ error: "Classification failed" }, 500);
  }
});

function jsonResponse(body: Record<string, unknown>, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: jsonHeaders,
  });
}

function classificationPrompt(rawText: string): string {
  return `Classify this hospitality document from Spain.

Possible values:
- "invoice"
- "delivery_note"
- "expense_ticket"
- "unknown"

STRICT CLASSIFICATION RULES:
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

function parseExtraction(content: string): ClassificationExtraction | null {
  try {
    const clean = content
      .replace(/```json\s*/gi, "")
      .replace(/```\s*/g, "")
      .trim();

    const start = clean.indexOf("{");
    const end = clean.lastIndexOf("}");
    if (start === -1 || end === -1 || end <= start) return null;

    const parsed = JSON.parse(clean.slice(start, end + 1)) as unknown;
    if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) {
      return null;
    }

    return parsed as ClassificationExtraction;
  } catch {
    return null;
  }
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
