import { defineConfig } from '@adonisjs/core/bodyparser'
export default defineConfig({
  allowedMethods: ['POST', 'PUT', 'PATCH'],
  json: { limit: '32kb', types: ['application/json'] },
})
