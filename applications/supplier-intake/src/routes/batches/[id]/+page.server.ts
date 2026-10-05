import { error, fail } from '@sveltejs/kit';
import { superValidate, message } from 'sveltekit-superforms';
import { zod4 } from 'sveltekit-superforms/adapters';
import { z } from 'zod';
import { mappingSchema } from '$lib/mapping';
import {
  getBatch,
  reviewBatch,
  promoteBatch,
  RevisionConflict,
} from '$lib/server/intake';
import { IntakeError } from '$lib/server/parsers';
import type { Actions, PageServerLoad } from './$types';
export const load: PageServerLoad = async ({ params }) => {
  if (!z.uuid().safeParse(params.id).success) error(404, 'Batch not found.');
  const data = await getBatch(params.id).catch((err) => {
    if (err instanceof IntakeError) error(404, 'Batch not found.');
    throw err;
  });
  const { batch } = data;
  const headers = batch.headers;
  const values = {
    batchId: batch.id,
    revision: batch.revision,
    supplier: batch.supplier || 'Harbor Supply',
    sku: headers[0],
    product: headers[1],
    price: headers[2],
    stock: headers[3],
    ...batch.mapping,
  };
  values.revision = batch.revision;
  return {
    ...data,
    form: await superValidate(values, zod4(mappingSchema), { errors: false }),
  };
};
export const actions: Actions = {
  review: async ({ request, params }) => {
    const form = await superValidate(request, zod4(mappingSchema));
    if (!form.valid) return fail(400, { form });
    if (form.data.batchId !== params.id)
      return message(form, 'Review the batch at this address.', { status: 400 });
    try {
      const result = await reviewBatch(form.data);
      form.data.revision = result.revision;
      return message(
        form,
        result.invalidCount
          ? `${result.invalidCount} ${result.invalidCount === 1 ? 'row needs' : 'rows need'} correction. Nothing has been promoted.`
          : 'Every row is valid. The batch is ready for promotion.',
      );
    } catch (err) {
      if (err instanceof IntakeError)
        return message(form, err.message, {
          status: err instanceof RevisionConflict ? 409 : 400,
        });
      console.error('Supplier review failed.');
      return message(form, 'Review could not be saved. Check the database connection.', {
        status: 503,
      });
    }
  },
  promote: async ({ request, params }) => {
    const form = await request.formData();
    const parsed = z
      .object({ revision: z.coerce.number().int().positive() })
      .safeParse(Object.fromEntries(form));
    if (!parsed.success || !z.uuid().safeParse(params.id).success)
      return fail(400, { promotion: 'Reload the batch before promoting.' });
    try {
      const result = await promoteBatch(params.id, parsed.data.revision);
      return {
        promotion: result.reused
          ? 'This batch was already imported; no duplicates were added.'
          : `${result.count} products promoted together.`,
      };
    } catch (err) {
      if (err instanceof IntakeError)
        return fail(err instanceof RevisionConflict ? 409 : 400, {
          promotion: err.message,
        });
      console.error('Supplier promotion failed.');
      return fail(503, { promotion: 'Promotion failed. No rows were imported.' });
    }
  },
};
