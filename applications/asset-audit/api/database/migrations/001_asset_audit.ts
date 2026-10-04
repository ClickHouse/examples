import { BaseSchema } from '@adonisjs/lucid/schema'
export default class extends BaseSchema {
  async up() {
    this.schema.createTable('items', (table) => {
      table.increments('id')
      table.string('sku', 40).notNullable().unique()
      table.string('name', 120).notNullable()
      table.string('category', 40).notNullable()
      table.integer('quantity').notNullable()
    })
    this.schema.createTable('stocktakes', (table) => {
      table.increments('id')
      table.string('name', 120).notNullable()
      table.string('location', 80).notNullable()
      table.string('status', 12).notNullable().defaultTo('draft')
      table.integer('revision').notNullable().defaultTo(0)
      table.timestamp('finalized_at', { useTz: true }).nullable()
    })
    this.schema.createTable('count_rows', (table) => {
      table.integer('stocktake_id').notNullable().references('id').inTable('stocktakes')
      table.integer('item_id').notNullable().references('id').inTable('items')
      table.integer('expected_quantity').notNullable()
      table.integer('counted_quantity').nullable()
      table.primary(['stocktake_id', 'item_id'])
    })
    this.defer(async (db) => {
      await db.rawQuery(`
        ALTER TABLE items ADD CHECK (quantity BETWEEN 0 AND 1000000);
        ALTER TABLE stocktakes ADD CHECK (revision >= 0),
          ADD CHECK (status IN ('draft', 'finalized')),
          ADD CHECK ((status = 'finalized') = (finalized_at IS NOT NULL));
        ALTER TABLE count_rows ADD CHECK (expected_quantity BETWEEN 0 AND 1000000),
          ADD CHECK (counted_quantity BETWEEN 0 AND 1000000);
        CREATE FUNCTION guard_finalized_sheet() RETURNS trigger LANGUAGE plpgsql
          SET search_path = asset_audit, pg_catalog AS $$
        BEGIN
          IF TG_TABLE_NAME = 'stocktakes' THEN
            IF OLD.status = 'finalized' THEN RAISE EXCEPTION 'Finalized sheets are immutable'; END IF;
            RETURN NEW;
          END IF;
          PERFORM 1 FROM asset_audit.stocktakes WHERE id = OLD.stocktake_id AND status = 'draft' FOR UPDATE;
          IF NOT FOUND THEN RAISE EXCEPTION 'Finalized sheets are immutable'; END IF;
          RETURN NEW;
        END;
        $$;
        CREATE TRIGGER immutable_sheet BEFORE UPDATE ON stocktakes
          FOR EACH ROW EXECUTE FUNCTION guard_finalized_sheet();
        CREATE TRIGGER immutable_count BEFORE UPDATE ON count_rows
          FOR EACH ROW EXECUTE FUNCTION guard_finalized_sheet();
      `)
    })
  }
  async down() {
    this.schema.dropTable('count_rows')
    this.schema.dropTable('stocktakes')
    this.schema.dropTable('items')
    this.defer(async (db) => { await db.rawQuery('DROP FUNCTION guard_finalized_sheet()') })
  }
}
