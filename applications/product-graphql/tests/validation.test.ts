import { test, expect } from "bun:test";
import { contents, page, title, revision } from "../src/server/validation";
test("pagination bounds and collection bounds", () => {
  expect(() => page(21, 0)).toThrow();
  expect(() => page(1, -1)).toThrow();
  expect(() => contents(Array(13).fill("x"))).toThrow();
  expect(() => contents(["x", "x"])).toThrow();
  expect(() => contents(["not-a-uuid"])).toThrow();
});
test("title and revision inputs", () => {
  expect(title("  Weekend  ")).toBe("Weekend");
  expect(() => title("   ")).toThrow();
  expect(() => revision(0)).toThrow();
  expect(() => revision(2147483647)).toThrow();
});
