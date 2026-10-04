import { BaseCommand, flags } from '@adonisjs/core/ace'
import { lookup } from 'node:dns/promises'
import db from '@adonisjs/lucid/services/db'
import config from '#config/database'
export default class DbProbe extends BaseCommand {
  static commandName = 'db:probe'
  static description = 'Verify the Lucid connection (or deliberately test a wrong hostname)'
  static options = { startApp: true }
  @flags.string() declare servername: string | undefined
  async run() {
    if (this.servername) {
      const connection = config.connections!.postgres.connection as { host: string; ssl: { servername: string } }
      // pg supplies SNI from a DNS host, overriding ssl.servername. Connect to
      // the same service's resolved IP so this deliberate negative control
      // can send the incorrect TLS name without changing the destination.
      connection.host = (await lookup(connection.host)).address
      connection.ssl.servername = this.servername
      db.manager.patch('postgres', config.connections!.postgres)
    }
    try {
      const result = await db.rawQuery('SELECT current_user AS role, version() AS version')
      this.logger.info(JSON.stringify(result.rows[0]))
    } catch (error) {
      this.logger.error(error instanceof Error ? error.message : 'Database connection failed')
      this.exitCode = 1
    } finally { await db.manager.closeAll() }
  }
}
