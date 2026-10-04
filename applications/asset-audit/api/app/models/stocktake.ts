import { BaseModel, column } from '@adonisjs/lucid/orm'
export default class Stocktake extends BaseModel {
  static table = 'asset_audit.stocktakes'
  @column({ isPrimary: true }) declare id: number
  @column() declare name: string
  @column() declare location: string
  @column() declare status: 'draft' | 'finalized'
  @column() declare revision: number
  @column({ columnName: 'finalized_at' }) declare finalizedAt: string | null
}
