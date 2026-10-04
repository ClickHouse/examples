import { defineConfig } from '@adonisjs/core/app'
export default defineConfig({
  commands: [() => import('@adonisjs/core/commands'), () => import('@adonisjs/lucid/commands')],
  providers: [
    () => import('@adonisjs/core/providers/app_provider'),
    () => import('@adonisjs/core/providers/vinejs_provider'),
    () => import('@adonisjs/lucid/database_provider'),
    () => import('@adonisjs/static/static_provider'),
  ],
  preloads: [() => import('#start/routes'), () => import('#start/kernel')],
  metaFiles: [{ pattern: 'public/**', reloadServer: false }],
})
