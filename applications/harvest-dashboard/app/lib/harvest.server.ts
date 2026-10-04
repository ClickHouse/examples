import { database } from './database.server';
import type { EntryInput, Filters } from './validation';

export type Lookup = { id: string; name: string };
export type Harvest = { id: string; crop_id: string; bed_id: string; crop: string; bed: string; harvested_on: string; grams: number; note: string; version: number };
export type Weekly = { week: string; grams: number };
export type CropTotal = { crop: string; grams: number };
export class RevisionConflict extends Error {}
export class InvalidReference extends Error {}

export async function loadDashboard(filters: Filters) {
  const connection = await database().connect();
  try {
    // Entries and both charts share a single consistent database snapshot.
    await connection.query('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY');
    const values = [filters.from, filters.to, filters.cropId || null];
    const predicate = 'h.harvested_on BETWEEN $1::date AND $2::date AND ($3::uuid IS NULL OR h.crop_id = $3::uuid)';
    const crops = await connection.query<Lookup>('SELECT id, name FROM harvest.crops ORDER BY name');
    const beds = await connection.query<Lookup>('SELECT id, name FROM harvest.beds ORDER BY name');
    const entries = await connection.query<Harvest>(
      `SELECT h.id, h.crop_id, h.bed_id, c.name AS crop, b.name AS bed,
       to_char(h.harvested_on, 'YYYY-MM-DD') AS harvested_on, h.grams, h.note, h.version
       FROM harvest.entries h JOIN harvest.crops c ON c.id=h.crop_id JOIN harvest.beds b ON b.id=h.bed_id
       WHERE ${predicate} ORDER BY h.harvested_on DESC, h.id LIMIT 200`, values);
    const weekly = await connection.query<Weekly>(
      `SELECT to_char(date_trunc('week', h.harvested_on::timestamp), 'YYYY-MM-DD') AS week,
       SUM(h.grams)::float8 AS grams FROM harvest.entries h WHERE ${predicate}
       GROUP BY 1 ORDER BY 1`, values);
    const cropTotals = await connection.query<CropTotal>(
      `SELECT c.name AS crop, SUM(h.grams)::float8 AS grams FROM harvest.entries h
       JOIN harvest.crops c ON c.id=h.crop_id WHERE ${predicate} GROUP BY c.name ORDER BY grams DESC, c.name`, values);
    const summary = await connection.query<{ count: number; grams: number }>(
      `SELECT COUNT(*)::int AS count, COALESCE(SUM(h.grams), 0)::float8 AS grams
       FROM harvest.entries h WHERE ${predicate}`, values);
    await connection.query('COMMIT');
    return { filters, crops: crops.rows, beds: beds.rows, entries: entries.rows, weekly: weekly.rows, cropTotals: cropTotals.rows, summary: summary.rows[0] };
  } catch (error) { await connection.query('ROLLBACK'); throw error; }
  finally { connection.release(); }
}
export async function createHarvest(input: EntryInput) {
  try {
    const result = await database().query<{ id: string }>(
      'INSERT INTO harvest.entries (crop_id, bed_id, harvested_on, grams, note) VALUES ($1, $2, $3::date, $4, $5) RETURNING id',
      [input.cropId, input.bedId, input.harvestedOn, input.grams, input.note]);
    return result.rows[0].id;
  } catch (error) { if ((error as { code?: string }).code === '23503') throw new InvalidReference(); throw error; }
}
export async function updateHarvest(id: string, version: number, input: EntryInput) {
  try {
    const result = await database().query(
      'UPDATE harvest.entries SET crop_id=$3, bed_id=$4, harvested_on=$5::date, grams=$6, note=$7, version=version+1 WHERE id=$1 AND version=$2 RETURNING id',
      [id, version, input.cropId, input.bedId, input.harvestedOn, input.grams, input.note]);
    if (!result.rowCount) throw new RevisionConflict();
  } catch (error) { if ((error as { code?: string }).code === '23503') throw new InvalidReference(); throw error; }
}
export async function deleteHarvest(id: string, version: number) {
  const result = await database().query('DELETE FROM harvest.entries WHERE id=$1 AND version=$2 RETURNING id', [id, version]);
  if (!result.rowCount) throw new RevisionConflict();
}
