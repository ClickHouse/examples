import { readFileSync } from 'node:fs'
import { defineConfig } from '@adonisjs/lucid'
import env from '#start/env'
// Separate fields avoid URL sslmode parsing overwriting the verified TLS options.
export default defineConfig({
  connection: 'postgres',
  connections: {
    postgres: {
      client: 'pg',
      connection: {
        host: env.get('DB_HOST'), port: env.get('DB_PORT'),
        database: env.get('DB_DATABASE'), user: env.get('DB_USER'),
        password: env.get('DB_PASSWORD').release(),
        ssl: {
          ca: readFileSync(env.get('PG_CA_CERT_PATH'), 'utf8'),
          rejectUnauthorized: true,
          servername: env.get('DB_HOST'),
        },
      },
      pool: { min: 0, max: 5 },
      migrations: { naturalSort: true, paths: ['database/migrations'] },
      seeders: { paths: ['database/seeders'] },
    },
  },
})
