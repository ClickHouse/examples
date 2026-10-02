import { database } from './database.js';
import { buildApp } from './app.js';
const db = database();
try {
  const port = Number(process.env.PORT ?? '3000');
  if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('Invalid PORT');
  const app = await buildApp(db, process.env.CURSOR_SECRET ?? '');
  await app.listen({ host: '127.0.0.1', port });
  console.log(`Catalogue API listening on http://127.0.0.1:${port}`);
  for (const signal of ['SIGINT', 'SIGTERM']) process.once(signal, () => { void app.close(); });
} catch {
  await db.destroy();
  console.error('Startup failed; check database settings, CA and cursor secret');
  process.exitCode = 1;
}
