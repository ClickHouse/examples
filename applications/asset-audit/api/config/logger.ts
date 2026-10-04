import { defineConfig } from '@adonisjs/core/logger'
import env from '#start/env'
export default defineConfig({ default: 'app', loggers: { app: { enabled: true, name: 'asset-audit', level: env.get('LOG_LEVEL') } } })
