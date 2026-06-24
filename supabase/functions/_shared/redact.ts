const BEARER_TOKEN_PATTERN = /Bearer\s+[A-Za-z0-9._~+/=-]+/gi;
const JWT_PATTERN = /eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/g;
const URL_PATTERN = /https?:\/\/\S+/g;
const UUID_PATTERN = /\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b/g;
const STORAGE_PATH_PATTERN = /\b[0-9a-fA-F-]{36}\/[0-9a-fA-F-]{36}\/[^\s]+/g;

export function redact(value: unknown): string {
  return String(value)
    .replaceAll(BEARER_TOKEN_PATTERN, "Bearer [REDACTED]")
    .replaceAll(JWT_PATTERN, "[REDACTED_JWT]")
    .replaceAll(URL_PATTERN, "[REDACTED_URL]")
    .replaceAll(STORAGE_PATH_PATTERN, "[REDACTED_STORAGE_PATH]")
    .replaceAll(UUID_PATTERN, "[REDACTED_ID]");
}

export function logInfo(message: string): void {
  console.log(redact(message));
}

export function logWarn(message: string): void {
  console.warn(redact(message));
}

export function logError(message: string, error?: unknown): void {
  const suffix = error === undefined ? "" : ` ${redact(error)}`;
  console.error(redact(message) + suffix);
}
