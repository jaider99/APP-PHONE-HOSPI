import { logWarn } from "./redact.ts";

export interface RateLimitOptions {
  key: string;
  limit: number;
  windowMs: number;
}

export interface RateLimitResult {
  allowed: boolean;
  retryAfterSeconds: number;
}

interface Bucket {
  count: number;
  resetAt: number;
}

const buckets = new Map<string, Bucket>();

export function checkRateLimit(options: RateLimitOptions): RateLimitResult {
  const now = Date.now();
  const current = buckets.get(options.key);

  if (!current || current.resetAt <= now) {
    buckets.set(options.key, {
      count: 1,
      resetAt: now + options.windowMs,
    });
    return { allowed: true, retryAfterSeconds: 0 };
  }

  if (current.count >= options.limit) {
    const retryAfterSeconds = Math.max(1, Math.ceil((current.resetAt - now) / 1000));
    logWarn(`[rate-limit] exceeded key=${options.key} retryAfter=${retryAfterSeconds}s`);
    return {
      allowed: false,
      retryAfterSeconds,
    };
  }

  current.count += 1;
  return { allowed: true, retryAfterSeconds: 0 };
}

export function rateLimitResponse(
  retryAfterSeconds: number,
  headers: Record<string, string> = {},
): Response {
  return new Response(JSON.stringify({ error: "Too many requests" }), {
    status: 429,
    headers: {
      "Content-Type": "application/json",
      ...headers,
      "Retry-After": String(retryAfterSeconds),
    },
  });
}

export function rateLimitKey(
  functionName: string,
  userId: string,
  companyId?: string,
): string {
  return [functionName, userId, companyId ?? "no-company"].join(":");
}
