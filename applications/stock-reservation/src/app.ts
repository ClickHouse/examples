import type { SQL } from "bun";
import { createHash, timingSafeEqual } from "node:crypto";
import { Hono } from "hono";

export const MAX_BODY_BYTES = 4096;
const SKU = /^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$/;
const IDEMPOTENCY_KEY = /^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export interface Reservation {
  id: string;
  sku: string;
  quantity: number;
  status: "active" | "released";
  created_at: string;
  released_at: string | null;
}

type ReservationRow = Omit<Reservation, "created_at" | "released_at"> & {
  created_at: Date | string;
  released_at: Date | string | null;
};

interface IdempotencyRow {
  request_sku: string;
  request_quantity: number;
  response_status: 201;
  response_body: Reservation;
}

export interface AppOptions {
  sql: SQL;
  apiKeys: ReadonlyMap<string, string>;
  onError?: (error: Error) => void;
}

class ApiError extends Error {
  constructor(readonly status: 400 | 401 | 404 | 409 | 413 | 415, readonly code: string, message: string) {
    super(message);
  }
}

function serialize(row: ReservationRow): Reservation {
  return {
    id: row.id,
    sku: row.sku,
    quantity: row.quantity,
    status: row.status,
    created_at: new Date(row.created_at).toISOString(),
    released_at: row.released_at === null ? null : new Date(row.released_at).toISOString(),
  };
}

async function readReservationBody(request: Request): Promise<{ sku: string; quantity: number }> {
  if (request.headers.get("content-type")?.split(";")[0]?.trim().toLowerCase() !== "application/json") {
    throw new ApiError(415, "unsupported_media_type", "Use Content-Type: application/json.");
  }
  const reader = request.body?.getReader();
  if (!reader) throw new ApiError(400, "invalid_json", "The request must contain JSON.");
  const chunks: Uint8Array[] = [];
  let length = 0;
  try {
    for (;;) {
      const { value, done } = await reader.read();
      if (done) break;
      length += value.byteLength;
      if (length > MAX_BODY_BYTES) {
        await reader.cancel();
        throw new ApiError(413, "body_too_large", `The request body must be at most ${MAX_BODY_BYTES} bytes.`);
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }
  const buffer = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) {
    buffer.set(chunk, offset);
    offset += chunk.byteLength;
  }
  let input: unknown;
  try {
    input = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(buffer));
  } catch {
    throw new ApiError(400, "invalid_json", "The request must contain valid UTF-8 JSON.");
  }
  if (!input || typeof input !== "object" || Array.isArray(input)) {
    throw new ApiError(400, "invalid_request", "Provide an object containing sku and quantity.");
  }
  const value = input as Record<string, unknown>;
  if (Object.keys(value).length !== 2 || typeof value.sku !== "string" || !SKU.test(value.sku) ||
    typeof value.quantity !== "number" || !Number.isInteger(value.quantity) || value.quantity < 1 || value.quantity > 1000) {
    throw new ApiError(400, "invalid_request", "Provide only sku (1–64 ASCII letters, digits, underscores, or hyphens) and quantity (integer 1–1000).");
  }
  return { sku: value.sku, quantity: value.quantity };
}

export function createApp({ sql, apiKeys, onError }: AppOptions) {
  const app = new Hono<{ Variables: { clientId: string } }>();
  const clients = Array.from(apiKeys, ([clientId, token]) => ({
    clientId,
    digest: createHash("sha256").update(token).digest(),
  }));

  app.use("*", async (c, next) => {
    c.header("Cache-Control", "no-store");
    c.header("X-Content-Type-Options", "nosniff");
    const authorization = c.req.header("Authorization") ?? "";
    const match = /^Bearer ([A-Za-z0-9._~-]{32,256})$/i.exec(authorization);
    if (!match?.[1]) throw new ApiError(401, "unauthorized", "A valid Bearer token is required.");
    const digest = createHash("sha256").update(match[1]).digest();
    const client = clients.find((entry) => timingSafeEqual(digest, entry.digest));
    if (!client) throw new ApiError(401, "unauthorized", "A valid Bearer token is required.");
    c.set("clientId", client.clientId);
    await next();
  });

  app.get("/inventory", async (c) => {
    const inventory = await sql`SELECT sku, name, available FROM stock_reservation.inventory ORDER BY sku`;
    return c.json({ inventory });
  });

  app.post("/reservations", async (c) => {
    const key = c.req.header("Idempotency-Key") ?? "";
    if (!IDEMPOTENCY_KEY.test(key)) {
      throw new ApiError(400, "invalid_idempotency_key", "Idempotency-Key must be 1–128 ASCII letters, digits, dots, underscores, colons, or hyphens.");
    }
    const { sku, quantity } = await readReservationBody(c.req.raw);
    const clientId = c.get("clientId");
    const response: Reservation = {
      id: crypto.randomUUID(), sku, quantity, status: "active",
      created_at: new Date().toISOString(), released_at: null,
    };

    const result = await sql.begin("ISOLATION LEVEL READ COMMITTED", async (tx) => {
      // The unique key is the lock: another transaction waits here until we commit or roll back.
      const claimed = await tx<IdempotencyRow[]>`
        INSERT INTO stock_reservation.idempotency_keys
          (client_id, key, request_sku, request_quantity, reservation_id, response_status, response_body)
        VALUES (${clientId}, ${key}, ${sku}, ${quantity}, ${response.id}, 201, ${response}::jsonb)
        ON CONFLICT (client_id, key) DO NOTHING
        RETURNING request_sku, request_quantity, response_status, response_body
      `;
      if (claimed.length === 0) {
        // A new READ COMMITTED statement sees the conflicting transaction's committed row.
        const [existing] = await tx<IdempotencyRow[]>`
          SELECT request_sku, request_quantity, response_status, response_body
          FROM stock_reservation.idempotency_keys WHERE client_id = ${clientId} AND key = ${key}
        `;
        if (!existing) throw new Error("The committed idempotency record is missing.");
        if (existing.request_sku !== sku || existing.request_quantity !== quantity) {
          throw new ApiError(409, "idempotency_conflict", "This idempotency key was already used for a different request.");
        }
        return { body: existing.response_body, replayed: true };
      }

      // The predicate and decrement run together under PostgreSQL's row lock.
      const changed = await tx`
        UPDATE stock_reservation.inventory SET available = available - ${quantity}
        WHERE sku = ${sku} AND available >= ${quantity} RETURNING sku
      `;
      if (changed.length === 0) {
        const exists = await tx`SELECT sku FROM stock_reservation.inventory WHERE sku = ${sku}`;
        if (exists.length === 0) throw new ApiError(404, "not_found", "The inventory item was not found.");
        throw new ApiError(409, "insufficient_inventory", "There is not enough inventory for this reservation.");
      }
      await tx`
        INSERT INTO stock_reservation.reservations (id, client_id, sku, quantity, status, created_at)
        VALUES (${response.id}, ${clientId}, ${sku}, ${quantity}, 'active', ${response.created_at}::timestamptz)
      `;
      // Always serialize the stored response, including the first response, so replay is identical.
      return { body: claimed[0]!.response_body, replayed: false };
    });
    c.header("Idempotency-Replayed", String(result.replayed));
    return c.json(result.body, 201);
  });

  app.get("/reservations/:id", async (c) => {
    const id = c.req.param("id");
    if (!UUID.test(id)) throw new ApiError(404, "not_found", "The reservation was not found.");
    const [reservation] = await sql<ReservationRow[]>`
      SELECT id, sku, quantity, status, created_at, released_at
      FROM stock_reservation.reservations WHERE id = ${id} AND client_id = ${c.get("clientId")}
    `;
    if (!reservation) throw new ApiError(404, "not_found", "The reservation was not found.");
    return c.json(serialize(reservation));
  });

  app.delete("/reservations/:id", async (c) => {
    const id = c.req.param("id");
    if (!UUID.test(id)) throw new ApiError(404, "not_found", "The reservation was not found.");
    const clientId = c.get("clientId");
    const reservation = await sql.begin("ISOLATION LEVEL READ COMMITTED", async (tx) => {
      const [current] = await tx<ReservationRow[]>`
        SELECT id, sku, quantity, status, created_at, released_at
        FROM stock_reservation.reservations WHERE id = ${id} AND client_id = ${clientId}
        FOR UPDATE
      `;
      if (!current) throw new ApiError(404, "not_found", "The reservation was not found.");
      if (current.status === "released") return current;
      await tx`
        UPDATE stock_reservation.inventory SET available = available + ${current.quantity}
        WHERE sku = ${current.sku}
      `;
      const [released] = await tx<ReservationRow[]>`
        UPDATE stock_reservation.reservations SET status = 'released', released_at = clock_timestamp()
        WHERE id = ${id} AND client_id = ${clientId}
        RETURNING id, sku, quantity, status, created_at, released_at
      `;
      if (!released) throw new Error("The locked reservation is missing.");
      return released;
    });
    return c.json(serialize(reservation));
  });

  app.notFound((c) => c.json({ error: { code: "not_found", message: "The route was not found." } }, 404));
  app.onError((error, c) => {
    if (error instanceof ApiError) {
      if (error.status === 401) c.header("WWW-Authenticate", "Bearer");
      return c.json({ error: { code: error.code, message: error.message } }, error.status);
    }
    // Connection errors can include credentials. The default log never includes the error object.
    onError?.(error);
    c.header("Retry-After", "1");
    return c.json({ error: {
      code: "database_unavailable",
      message: "The database could not complete this request. Retry with the same idempotency key.",
    } }, 503);
  });
  return app;
}
