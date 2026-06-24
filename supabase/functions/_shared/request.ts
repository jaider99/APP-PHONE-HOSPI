export type JsonObject = Record<string, unknown>;

export class HttpError extends Error {
  constructor(
    public readonly status: number,
    message: string,
  ) {
    super(message);
    this.name = "HttpError";
  }
}

export interface ReadJsonObjectOptions {
  maxBytes: number;
  allowedFields: readonly string[];
}

export async function readJsonObject(
  req: Request,
  options: ReadJsonObjectOptions,
): Promise<JsonObject> {
  const contentLength = req.headers.get("content-length");
  if (contentLength !== null) {
    const length = Number(contentLength);
    if (!Number.isFinite(length) || length < 0) {
      throw new HttpError(400, "Invalid content-length header");
    }
    if (length > options.maxBytes) {
      throw new HttpError(413, "Request body is too large");
    }
  }

  const bytes = await readBodyBytes(req, options.maxBytes);
  if (bytes.byteLength === 0) {
    throw new HttpError(400, "Request body is required");
  }

  let body: unknown;
  try {
    body = JSON.parse(new TextDecoder().decode(bytes));
  } catch {
    throw new HttpError(400, "Invalid JSON body");
  }

  if (body === null || typeof body !== "object" || Array.isArray(body)) {
    throw new HttpError(400, "Request body must be an object");
  }

  const object = body as JsonObject;
  const allowed = new Set(options.allowedFields);
  const unknownFields = Object.keys(object).filter((key) => !allowed.has(key));
  if (unknownFields.length > 0) {
    throw new HttpError(400, `Unsupported request fields: ${unknownFields.join(", ")}`);
  }

  return object;
}

async function readBodyBytes(req: Request, maxBytes: number): Promise<Uint8Array> {
  const reader = req.body?.getReader();
  if (!reader) {
    return new Uint8Array();
  }

  const chunks: Uint8Array[] = [];
  let total = 0;

  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      if (!value) continue;

      total += value.byteLength;
      if (total > maxBytes) {
        await reader.cancel();
        throw new HttpError(413, "Request body is too large");
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }

  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return bytes;
}

export function requireStringField(
  body: JsonObject,
  field: string,
  options: { maxLength?: number } = {},
): string {
  const value = body[field];
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new HttpError(400, `${field} is required`);
  }

  const trimmed = value.trim();
  if (options.maxLength !== undefined && trimmed.length > options.maxLength) {
    throw new HttpError(413, `${field} is too large`);
  }

  return trimmed;
}
