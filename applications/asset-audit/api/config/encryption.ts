import env from '#start/env'
import { defineConfig, drivers } from '@adonisjs/core/encryption'
export default defineConfig({
  default: 'gcm',
  list: { gcm: drivers.aes256gcm({ keys: [env.get('APP_KEY')], id: 'gcm' }) },
})
