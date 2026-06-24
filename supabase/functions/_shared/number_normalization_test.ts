import {
  parseMoney,
  parseQuantity,
} from "./number_normalization.ts";

Deno.test("parseMoney handles European and US formatted values", () => {
  const cases: Array<[unknown, number | null]> = [
    ["808,16€", 808.16],
    ["729,17", 729.17],
    ["1.506,21", 1506.21],
    ["1,506.21", 1506.21],
    ["34,1700", 34.17],
    ["29,04", 29.04],
    ["14,16", 14.16],
    ["80,27", 80.27],
    ["40,97", 40.97],
    ["1 506,21", 1506.21],
    ["€808,16", 808.16],
    ["1,234,567", 1234567],
  ];

  for (const [input, expected] of cases) {
    const actual = parseMoney(input);
    if (actual !== expected) {
      throw new Error(
        `parseMoney(${JSON.stringify(input)}) expected ${expected} but got ${actual}`,
      );
    }
  }
});

Deno.test("parseQuantity preserves decimal meaning for comma quantities", () => {
  const cases: Array<[unknown, number | null]> = [
    ["6,828", 6.828],
    ["1,000", 1],
    ["16,000", 16],
    ["5,240", 5.24],
    ["2,155", 2.155],
    ["1.250", 1.25],
    ["1,234,567", 1234567],
  ];

  for (const [input, expected] of cases) {
    const actual = parseQuantity(input);
    if (actual !== expected) {
      throw new Error(
        `parseQuantity(${JSON.stringify(input)}) expected ${expected} but got ${actual}`,
      );
    }
  }
});
