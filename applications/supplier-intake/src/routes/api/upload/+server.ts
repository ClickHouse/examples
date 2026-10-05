import { json } from '@sveltejs/kit';
import { stageUpload } from '$lib/server/intake';
import { IntakeError } from '$lib/server/parsers';
import type { RequestHandler } from './$types';
export const POST: RequestHandler = async ({ request }) => {
  try {
    const data = await request.formData();
    const file = data.get('file');
    if (!(file instanceof File) || data.getAll('file').length !== 1)
      return json({ error: 'Choose one CSV or XLSX file.' }, { status: 400 });
    const staged = await stageUpload(Buffer.from(await file.arrayBuffer()), file.name);
    return json(staged);
  } catch (error) {
    if (error instanceof IntakeError)
      return json({ error: error.message }, { status: 400 });
    console.error('Supplier upload failed.');
    return json(
      { error: 'The upload could not be staged. Check the database connection.' },
      { status: 503 },
    );
  }
};
