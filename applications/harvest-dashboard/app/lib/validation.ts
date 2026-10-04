import { z } from 'zod';

export const dateOnly = z.iso.date().refine((value) => value >= '1900-01-01' && value <= '2100-12-31', 'Choose a date between 1900 and 2100.');
const positiveInteger = z.coerce.number().int('Use whole grams.').min(1, 'Weight must be positive.').max(1_000_000, 'Use at most 1,000,000 grams.');
export const entrySchema = z.object({
  cropId: z.uuid(), bedId: z.uuid(), harvestedOn: dateOnly, grams: positiveInteger,
  note: z.string().trim().max(500, 'Keep notes to 500 characters.'),
});
export const revisionSchema = z.object({ id: z.uuid(), version: z.coerce.number().int().min(1).max(2_000_000_000) });
export const filterSchema = z.object({
  from: dateOnly, to: dateOnly, cropId: z.union([z.literal(''), z.uuid()]),
}).refine((v) => v.from <= v.to, { message: 'The end date must follow the start date.', path: ['to'] })
  .refine((v) => (Date.parse(v.to) - Date.parse(v.from)) / 86_400_000 <= 366, { message: 'Choose a range of at most 366 days.', path: ['to'] });
export type EntryInput = z.infer<typeof entrySchema>;
export type Filters = z.infer<typeof filterSchema>;
export function fieldErrors(error: z.ZodError): Record<string, string> {
  return Object.fromEntries(error.issues.map((issue) => [String(issue.path[0] ?? 'form'), issue.message]));
}
export function parseFilters(url: URL): Filters {
  return filterSchema.parse({
    from: url.searchParams.get('from') ?? '2026-09-01',
    to: url.searchParams.get('to') ?? '2026-09-30',
    cropId: url.searchParams.get('cropId') ?? '',
  });
}
