import Fastify, { type FastifyError } from 'fastify';
import { sql, type Kysely } from 'kysely';
import type { Database } from './database.js';
import { BadRequest, listProducts, type Query } from './catalogue.js';

export async function buildApp(db: Kysely<Database>, secret: string) {
  if (secret.length < 32) throw new Error('CURSOR_SECRET must contain at least 32 characters');
  const app = Fastify({ logger: false, bodyLimit: 4096,
    ajv: { customOptions: { removeAdditional: false, coerceTypes: true } } });
  app.setErrorHandler((error, _request, reply) => {
    const failure = error as FastifyError;
    if (error instanceof BadRequest || failure.validation) return reply.code(400).send({ error: error instanceof BadRequest ? error.message : 'Invalid request' });
    if (failure.statusCode && failure.statusCode < 500) return reply.code(failure.statusCode).send({ error: 'Invalid request' });
    console.error('Catalogue request failed');
    return reply.code(503).send({ error: 'Catalogue temporarily unavailable' });
  });
  app.get<{ Querystring: Query }>('/products', {
    schema: { querystring: { type: 'object', additionalProperties: false, properties: {
      q: { type: 'string', maxLength: 120 },
      category: { type: 'string', enum: ['camping', 'clothing', 'cycling'] },
      min_price: { type: 'integer', minimum: 0, maximum: 100000000 },
      max_price: { type: 'integer', minimum: 0, maximum: 100000000 },
      limit: { type: 'integer', minimum: 1, maximum: 100 },
      cursor: { type: 'string', minLength: 1, maxLength: 1024 },
    } } },
  }, request => listProducts(db, request.query, secret));
  app.get<{ Params: { id: string } }>('/products/:id', {
    schema: { params: { type: 'object', required: ['id'], additionalProperties: false,
      properties: { id: { type: 'string', pattern: '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' } } } },
  }, async (request, reply) => {
    const product = await db.selectFrom('products').select(['id','sku','name','description','category','price_pence'])
      .where('id', '=', request.params.id).where('active', '=', true).executeTakeFirst();
    return product ?? reply.code(404).send({ error: 'Product not found' });
  });
  app.get('/health', async () => { await sql`SELECT 1`.execute(db); return { status: 'ok' }; });
  app.addHook('onClose', async () => { await db.destroy(); });
  await sql`SELECT 1`.execute(db);
  return app;
}
