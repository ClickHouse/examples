import { oc } from "@orpc/contract";
import { type } from "arktype";
const id = "number.integer > 0";
const lineInput = type({
  productId: id,
  quantity: "1 <= number.integer <= 20",
});
export const saveInput = type({
  id,
  revision: "0 <= number.integer < 2147483647",
  days: "1 <= number.integer <= 14",
  lines: lineInput.array(),
})
  .onDeepUndeclaredKey("reject")
  .narrow(
    (input, ctx) =>
      (input.lines.length >= 1 && input.lines.length <= 10) ||
      ctx.mustBe("between 1 and 10 quote lines"),
  );
export const product = type({
  id,
  name: "string",
  category: "string",
  description: "string",
  rateMinor: "number.integer >= 0",
});
export const quote = type({
  id,
  title: "string",
  revision: "number.integer >= 0",
  days: "1 <= number.integer <= 14",
  currency: "'GBP'",
  totalMinor: "number.integer >= 0",
  lines: type({
    productId: id,
    name: "string",
    quantity: "1 <= number.integer <= 20",
    unitMinor: "number.integer >= 0",
    lineMinor: "number.integer >= 0",
  }).array(),
});
export const contract = {
  get: oc.input(type({ id }).onUndeclaredKey("reject")).output(quote),
  save: oc.input(saveInput).output(quote),
};
export type Product = typeof product.infer;
export type Quote = typeof quote.infer;
export type SaveInput = typeof saveInput.infer;
