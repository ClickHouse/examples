await import('reflect-metadata')
const { Ignitor, prettyPrintError } = await import('@adonisjs/core/ignitor')
const root = new URL('../', import.meta.url)
const importer = (path: string) => path.startsWith('.') ? import(new URL(path, root).href) : import(path)
new Ignitor(root, { importer }).tap((app) => {
  app.booting(async () => { await import('#start/env') })
}).ace().handle(process.argv.splice(2)).catch((error) => { process.exitCode = 1; prettyPrintError(error) })
