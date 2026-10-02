import assert from "node:assert/strict";
import { InputError, parseSearch } from "../src/input.ts";
const params = (extra = "") =>
  new URLSearchParams(`longitude=0&latitude=0&radiusMeters=1200${extra}`);
Deno.test("finite coordinate bounds, meters and bounded default limit", () => {
  assert.deepEqual(parseSearch(params()), {
    longitude: 0,
    latitude: 0,
    radiusMeters: 1200,
    limit: 20,
  });
  assert.equal(
    parseSearch(new URLSearchParams("longitude=-180&latitude=90&radiusMeters=0&limit=50"))
      .longitude,
    -180,
  );
});
Deno.test("nonfinite, out-of-range, malformed, duplicate and extra parameters fail", () => {
  for (
    const query of [
      "longitude=NaN&latitude=0&radiusMeters=10",
      "longitude=1e999&latitude=0&radiusMeters=10",
      "longitude=181&latitude=0&radiusMeters=10",
      "longitude=0&latitude=-91&radiusMeters=10",
      "longitude=0&latitude=0&radiusMeters=-1",
      "longitude=0&latitude=0&radiusMeters=50001",
      "longitude=&latitude=0&radiusMeters=10",
      "longitude=0x10&latitude=0&radiusMeters=10",
    ]
  ) assert.throws(() => parseSearch(new URLSearchParams(query)), InputError);
  for (
    const extra of [
      "&limit=0",
      "&limit=51",
      "&limit=2.5",
      "&category=unknown",
      "&category=cafe%27%20OR%20true--",
      "&longitude=1",
      "&unexpected=1",
    ]
  ) assert.throws(() => parseSearch(params(extra)), InputError);
});
Deno.test("valid optional category and explicit integer limit retain input order", () => {
  assert.deepEqual(
    parseSearch(
      new URLSearchParams("longitude=12&latitude=45&radiusMeters=100&category=library&limit=2"),
    ),
    { longitude: 12, latitude: 45, radiusMeters: 100, category: "library", limit: 2 },
  );
});
