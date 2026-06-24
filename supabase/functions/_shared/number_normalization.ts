const CURRENCY_TOKENS = /(€|\$|£|¥|\bEUR\b|\bUSD\b|\bGBP\b|\bJPY\b)/gi;
const NBSP_REGEX = /[\u00A0\u202F]/g;

type NumericKind = "money" | "quantity";

export function parseMoney(value: unknown): number | null {
  const parsed = parseStructuredNumber(value, "money");
  return roundMoney(parsed);
}

export function parseQuantity(value: unknown): number | null {
  const parsed = parseStructuredNumber(value, "quantity");
  return parsed === null ? null : roundTo(parsed, 3);
}

export function roundMoney(value: number | null): number | null {
  return value === null ? null : roundTo(value, 2);
}

function parseStructuredNumber(
  value: unknown,
  kind: NumericKind,
): number | null {
  if (value === null || value === undefined) return null;
  if (typeof value === "number") {
    return Number.isFinite(value) ? value : null;
  }
  if (typeof value !== "string") return null;

  const cleaned = sanitizeNumericInput(value);
  if (!cleaned) return null;

  const normalized = normalizeNumericString(cleaned, kind);
  if (!normalized) return null;

  const parsed = Number.parseFloat(normalized);
  return Number.isFinite(parsed) ? parsed : null;
}

function sanitizeNumericInput(value: string): string {
  return value
    .trim()
    .replace(NBSP_REGEX, " ")
    .replace(CURRENCY_TOKENS, "")
    .replace(/\s+/g, "")
    .replace(/[^0-9,.-]/g, "");
}

function normalizeNumericString(
  input: string,
  kind: NumericKind,
): string | null {
  if (!input) return null;

  const sign = input.startsWith("-") ? "-" : "";
  const unsigned = input.replace(/-/g, "");
  if (!unsigned) return null;

  const hasComma = unsigned.includes(",");
  const hasDot = unsigned.includes(".");

  if (hasComma && hasDot) {
    return sign + normalizeMixedSeparators(unsigned);
  }

  if (hasComma) {
    return sign + normalizeSingleSeparator(unsigned, ",", kind);
  }

  if (hasDot) {
    return sign + normalizeSingleSeparator(unsigned, ".", kind);
  }

  return sign + unsigned;
}

function normalizeMixedSeparators(input: string): string {
  const lastComma = input.lastIndexOf(",");
  const lastDot = input.lastIndexOf(".");

  if (lastComma > lastDot) {
    const integerPart = input.slice(0, lastComma).replace(/[.,]/g, "");
    const decimalPart = input.slice(lastComma + 1).replace(/[.,]/g, "");
    return decimalPart.length > 0 ? `${integerPart}.${decimalPart}` : integerPart;
  }

  const integerPart = input.slice(0, lastDot).replace(/[.,]/g, "");
  const decimalPart = input.slice(lastDot + 1).replace(/[.,]/g, "");
  return decimalPart.length > 0 ? `${integerPart}.${decimalPart}` : integerPart;
}

function normalizeSingleSeparator(
  input: string,
  separator: "," | ".",
  kind: NumericKind,
): string {
  const escapedSeparator = separator === "." ? "\\." : separator;
  const repeatedThousandsPattern = new RegExp(
    `^\\d{1,3}(${escapedSeparator}\\d{3})+$`,
  );

  if (repeatedThousandsPattern.test(input)) {
    if (kind === "quantity" && input.split(separator).length === 2) {
      return normalizeDecimalSeparator(input, separator);
    }
    return input.split(separator).join("");
  }

  const parts = input.split(separator);
  const decimalDigits = parts[parts.length - 1] ?? "";

  if (kind === "quantity") {
    if (decimalDigits.length >= 1 && decimalDigits.length <= 3) {
      return normalizeDecimalSeparator(input, separator);
    }
    if (decimalDigits.length === 0) {
      return parts.join("");
    }
    return normalizeDecimalSeparator(input, separator);
  }

  if (decimalDigits.length >= 1 && decimalDigits.length <= 4) {
    const singleSeparatorThousandsPattern = new RegExp(
      `^\\d{1,3}${escapedSeparator}\\d{3}$`,
    );
    if (singleSeparatorThousandsPattern.test(input) && decimalDigits.length === 3) {
      return parts.join("");
    }
    return normalizeDecimalSeparator(input, separator);
  }

  return parts.join("");
}

function normalizeDecimalSeparator(
  input: string,
  separator: "," | ".",
): string {
  const parts = input.split(separator);
  const decimalPart = parts.pop() ?? "";
  const integerPart = parts.join("");
  return decimalPart.length > 0 ? `${integerPart}.${decimalPart}` : integerPart;
}

function roundTo(value: number, decimalPlaces: number): number {
  const factor = 10 ** decimalPlaces;
  return Math.round((value + Number.EPSILON) * factor) / factor;
}
