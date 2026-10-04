import { defineConfig } from '@adonisjs/core/http'
export const http = defineConfig({
  generateRequestId: true, allowMethodSpoofing: false, useAsyncLocalStorage: true,
  cookie: { domain: '', path: '/', maxAge: '2h', httpOnly: true, secure: false, sameSite: 'lax' },
})
