import type { HttpContext } from '@adonisjs/core/http'
import type { NextFn } from '@adonisjs/core/types/http'
import env from '#start/env'
export default class LocalOperatorMiddleware {
  async handle({ request, response }: HttpContext, next: NextFn) {
    response.header('Cache-Control', 'no-store')
    if (request.header('host') !== new URL(env.get('APP_ORIGIN')).host) {
      return response.forbidden({ error: { code: 'host', message: 'Use the workbench on its configured host.' } })
    }
    if (!['GET', 'HEAD'].includes(request.method())) {
      if (request.header('origin') !== env.get('APP_ORIGIN') ||
          request.header('x-asset-audit') !== '1' ||
          !request.header('content-type')?.startsWith('application/json')) {
        return response.forbidden({ error: { code: 'origin', message: 'Use the workbench on its configured origin.' } })
      }
    }
    return next()
  }
}
