import { ORPCError } from "@orpc/server";
import { getDb, type Database } from "./db";
import type { Transaction } from "kysely";
import type { Product, Quote, SaveInput } from "../lib/contract";
export async function catalogue(): Promise<Product[]> {
  const rows = await getDb()
    .selectFrom("products")
    .selectAll()
    .orderBy("id")
    .execute();
  return rows.map((p) => ({
    id: p.id,
    name: p.name,
    category: p.category,
    description: p.description,
    rateMinor: p.rate_minor,
  }));
}
async function read(trx: Transaction<Database>, id: number): Promise<Quote> {
  const header = await trx
    .selectFrom("quotes")
    .selectAll()
    .where("id", "=", id)
    .forShare()
    .executeTakeFirst();
  if (!header)
    throw new ORPCError("NOT_FOUND", { message: "This quote does not exist." });
  const rows = await trx
    .selectFrom("quote_lines as l")
    .innerJoin("products as p", "p.id", "l.product_id")
    .select(["p.id", "p.name", "l.quantity", "l.unit_minor"])
    .where("l.quote_id", "=", id)
    .orderBy("p.id")
    .execute();
  const lines = rows.map((r) => ({
    productId: r.id,
    name: r.name,
    quantity: r.quantity,
    unitMinor: r.unit_minor,
    lineMinor: r.unit_minor * r.quantity * header.days,
  }));
  return {
    id,
    title: header.title,
    days: header.days,
    revision: header.revision,
    currency: "GBP",
    totalMinor: lines.reduce((sum, r) => sum + r.lineMinor, 0),
    lines,
  };
}
export function getQuote(id: number) {
  return getDb()
    .transaction()
    .execute((trx) => read(trx, id));
}
export async function saveQuote(input: SaveInput) {
  return getDb()
    .transaction()
    .execute(async (trx) => {
      const header = await trx
        .selectFrom("quotes")
        .selectAll()
        .where("id", "=", input.id)
        .forUpdate()
        .executeTakeFirst();
      if (!header)
        throw new ORPCError("NOT_FOUND", {
          message: "This quote does not exist.",
        });
      if (header.revision !== input.revision)
        throw new ORPCError("CONFLICT", {
          message: "A newer quote was saved. Reload before editing again.",
        });
      const ids = input.lines.map((l) => l.productId);
      if (new Set(ids).size !== ids.length)
        throw new ORPCError("BAD_REQUEST", {
          message: "Include each product only once.",
        });
      const prices = await trx
        .selectFrom("products")
        .select(["id", "rate_minor"])
        .where("id", "in", ids)
        .orderBy("id")
        .execute();
      if (prices.length !== ids.length)
        throw new ORPCError("BAD_REQUEST", {
          message: "One of these products is not in the catalogue.",
        });
      const byId = new Map(prices.map((p) => [p.id, p.rate_minor]));
      await trx
        .deleteFrom("quote_lines")
        .where("quote_id", "=", input.id)
        .execute();
      await trx
        .insertInto("quote_lines")
        .values(
          input.lines.map((l) => ({
            quote_id: input.id,
            product_id: l.productId,
            quantity: l.quantity,
            unit_minor: byId.get(l.productId)!,
          })),
        )
        .execute();
      await trx
        .updateTable("quotes")
        .set({
          days: input.days,
          revision: header.revision + 1,
          updated_at: new Date().toISOString(),
        })
        .where("id", "=", input.id)
        .execute();
      return read(trx, input.id);
    });
}
