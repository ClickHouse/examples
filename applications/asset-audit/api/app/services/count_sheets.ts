import db from '@adonisjs/lucid/services/db'
import Stocktake from '#models/stocktake'

export class SheetError extends Error {
  constructor(public status: number, public code: string, message: string) { super(message) }
}

export async function readSheet(id: number) {
  // Share the header lock with writers so revision and row counts form one view.
  return db.transaction(async (trx) => {
    const sheet = await Stocktake.query({ client: trx }).where('id', id).forShare().first()
    if (!sheet) throw new SheetError(404, 'missing', 'This count sheet does not exist.')
    const rows = await trx.from('asset_audit.count_rows as c')
      .join('asset_audit.items as i', 'i.id', 'c.item_id')
      .where('c.stocktake_id', id)
      .select('i.id as itemId', 'i.sku', 'i.name', 'i.category', 'c.expected_quantity as expected', 'c.counted_quantity as counted')
      .orderBy('i.id')
    return { id: sheet.id, name: sheet.name, location: sheet.location,
      status: sheet.status, revision: sheet.revision, finalizedAt: sheet.finalizedAt, rows }
  })
}

export async function changeSheet(id: number, revision: number,
  counts?: { itemId: number; counted: number | null }[]) {
  await db.transaction(async (trx) => {
    const sheet = await Stocktake.query({ client: trx }).where('id', id).forUpdate().first()
    if (!sheet) throw new SheetError(404, 'missing', 'This count sheet does not exist.')
    if (sheet.status === 'finalized') throw new SheetError(409, 'finalized', 'This count sheet has already been finalized.')
    if (sheet.revision !== revision) throw new SheetError(409, 'conflict', 'Someone saved a newer revision. Reload the sheet before editing again.')

    const existing = await trx.from('asset_audit.count_rows').where('stocktake_id', id).select('item_id', 'counted_quantity')
    if (counts) {
      const ids = new Set(counts.map((row) => row.itemId))
      if (ids.size !== counts.length || counts.length !== existing.length ||
          existing.some((row) => !ids.has(row.item_id))) {
        throw new SheetError(422, 'rows', 'Submit each item on this count sheet exactly once.')
      }
      for (const row of counts) {
        await trx.from('asset_audit.count_rows').where('stocktake_id', id).where('item_id', row.itemId)
          .update({ counted_quantity: row.counted })
      }
    } else {
      if (existing.some((row) => row.counted_quantity === null)) {
        throw new SheetError(422, 'incomplete', 'Count every item and save the draft before finalizing.')
      }
      sheet.status = 'finalized'
      // Set a database-compatible timestamp without a generated client date.
      sheet.finalizedAt = new Date().toISOString()
    }
    sheet.revision += 1
    await sheet.save()
  })
  return readSheet(id)
}
