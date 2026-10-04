import type { HttpContext } from '@adonisjs/core/http'
import Stocktake from '#models/stocktake'
import { readSheet, changeSheet, SheetError } from '#services/count_sheets'
import { draftValidator, finalizeValidator } from '#validators/count_sheet'

export default class StocktakesController {
  async index() {
    return Stocktake.query().select('id', 'name', 'location', 'status', 'revision').orderBy('id')
  }
  private id(value: string) {
    const id = Number(value)
    if (!Number.isSafeInteger(id) || id < 1) throw new SheetError(404, 'missing', 'This count sheet does not exist.')
    return id
  }
  private failure(error: unknown, { response, logger }: HttpContext) {
    if (error instanceof SheetError) return response.status(error.status).send({ error: { code: error.code, message: error.message } })
    if (typeof error === 'object' && error !== null && 'code' in error && error.code === 'E_VALIDATION_ERROR') {
      return response.unprocessableEntity({ error: { code: 'validation', message: 'Counts must be whole numbers from 0 to 1,000,000, or empty.' } })
    }
    logger.error({ event: 'count_sheet_failure' }, 'Count sheet operation failed')
    return response.internalServerError({ error: { code: 'database', message: 'The change could not be saved. Your draft remains unchanged.' } })
  }
  async show(ctx: HttpContext) {
    try { return await readSheet(this.id(ctx.params.id)) } catch (error) { return this.failure(error, ctx) }
  }
  async update(ctx: HttpContext) {
    try {
      const input = await ctx.request.validateUsing(draftValidator)
      return await changeSheet(this.id(ctx.params.id), input.revision, input.counts)
    } catch (error) { return this.failure(error, ctx) }
  }
  async finalize(ctx: HttpContext) {
    try {
      const input = await ctx.request.validateUsing(finalizeValidator)
      return await changeSheet(this.id(ctx.params.id), input.revision)
    } catch (error) { return this.failure(error, ctx) }
  }
}
