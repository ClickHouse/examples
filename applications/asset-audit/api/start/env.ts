import { Env } from '@adonisjs/core/env'
export default await Env.create(new URL('../', import.meta.url), {
  NODE_ENV: Env.schema.enum(['development', 'production', 'test'] as const),
  HOST: Env.schema.enum(['127.0.0.1', '::1'] as const),
  PORT: Env.schema.number(),
  LOG_LEVEL: Env.schema.string(),
  APP_KEY: Env.schema.secret(),
  APP_ORIGIN: Env.schema.string({ format: 'url', tld: false }),
  DB_HOST: Env.schema.string(), DB_PORT: Env.schema.number(),
  DB_DATABASE: Env.schema.string(), DB_USER: Env.schema.string(),
  DB_PASSWORD: Env.schema.secret(), PG_CA_CERT_PATH: Env.schema.string(),
})
