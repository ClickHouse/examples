import { BaseSeeder } from '@adonisjs/lucid/seeders'
import db from '@adonisjs/lucid/services/db'
export default class extends BaseSeeder {
  async run() {
    // Insert missing fixtures only: rerunning never resets an operator's count.
    await db.transaction(async (trx) => {
      await trx.table('items').insert([
        { id: 1, sku: 'AV-CAMERA', name: 'Conference cameras', category: 'AV', quantity: 12 },
        { id: 2, sku: 'AV-MIC', name: 'Wireless microphones', category: 'AV', quantity: 20 },
        { id: 3, sku: 'IT-DOCK', name: 'USB-C docks', category: 'IT', quantity: 36 },
        { id: 4, sku: 'IT-MONITOR', name: 'Desk monitors', category: 'IT', quantity: 48 },
        { id: 5, sku: 'IT-KEYBOARD', name: 'Keyboards', category: 'IT', quantity: 64 },
        { id: 6, sku: 'LAB-METER', name: 'Digital multimeters', category: 'Lab', quantity: 15 },
        { id: 7, sku: 'LAB-KIT', name: 'Sensor kits', category: 'Lab', quantity: 18 },
        { id: 8, sku: 'FAC-TOOL', name: 'Maintenance tool bags', category: 'Facilities', quantity: 9 },
      ]).onConflict('id').ignore()
      for (const sheet of [
        { id: 1, name: 'October equipment stocktake', location: 'North workshop' },
        { id: 2, name: 'Satellite room stocktake', location: 'South studio' },
      ]) {
        const inserted = await trx.table('stocktakes').insert(sheet).onConflict('id').ignore().returning('id')
        if (inserted.length) {
          await trx.rawQuery('INSERT INTO count_rows (stocktake_id, item_id, expected_quantity) SELECT ?, id, quantity FROM items', [sheet.id])
        }
      }
    })
  }
}
