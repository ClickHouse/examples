export const CATEGORIES = ["cafe", "library", "park"] as const;
export type Category = typeof CATEGORIES[number];
export type Search = {
  longitude: number;
  latitude: number;
  radiusMeters: number;
  limit: number;
  category?: Category;
};
export class InputError extends Error {}
const decimal = /^-?(?:\d+(?:\.\d*)?|\.\d+)(?:e[+-]?\d+)?$/i;
export function parseSearch(params: URLSearchParams): Search {
  const allowed = new Set(["longitude", "latitude", "radiusMeters", "limit", "category"]);
  const seen = new Set<string>();
  for (const key of params.keys()) {
    if (!allowed.has(key) || seen.has(key)) throw new InputError("Unknown or repeated parameter");
    seen.add(key);
  }
  const number = (key: string, minimum: number, maximum: number): number => {
    const raw = params.get(key);
    if (raw === null || !decimal.test(raw)) throw new InputError(`Invalid ${key}`);
    const value = Number(raw);
    if (!Number.isFinite(value) || value < minimum || value > maximum) {
      throw new InputError(`${key} must be between ${minimum} and ${maximum}`);
    }
    return value;
  };
  const longitude = number("longitude", -180, 180);
  const latitude = number("latitude", -90, 90);
  const radiusMeters = number("radiusMeters", 0, 50_000);
  const rawLimit = params.get("limit") ?? "20";
  const limit = Number(rawLimit);
  if (!/^\d+$/.test(rawLimit) || !Number.isInteger(limit) || limit < 1 || limit > 50) {
    throw new InputError("limit must be an integer between 1 and 50");
  }
  const category = params.get("category");
  if (category !== null && !CATEGORIES.includes(category as Category)) {
    throw new InputError("category must be cafe, library or park");
  }
  return {
    longitude,
    latitude,
    radiusMeters,
    limit,
    ...(category ? { category: category as Category } : {}),
  };
}
