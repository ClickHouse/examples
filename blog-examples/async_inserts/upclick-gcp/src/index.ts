import { MessagePublishedData } from '@google/events/cloud/pubsub/v1/MessagePublishedData';
import { cloudEvent } from '@google-cloud/functions-framework';
import { run } from './run';

cloudEvent('upclick', async (cloudevent: any) => {
  console.log('upclick function started...');

  // check the payload
  if (!cloudevent.data) {
    throw new Error('Invalid payload!');
  }

  const jsonPayload: MessagePublishedData = cloudevent.data;
  const base64Data = jsonPayload.message?.data;

  if (!base64Data) {
    throw new Error('Invalid data!');
  }
  const decodedData = Buffer.from(base64Data, 'base64').toString();
  const gcpPayload: { target: string } = JSON.parse(decodedData);

  // check task payload
  if (!gcpPayload.target) {
    throw new Error('Invalid payload!');
  }
  // run the logic on .target
  try {
    console.log(`Pub/Sub payload received: ${gcpPayload.target}`);
    await run(gcpPayload.target);
  } catch (err) {
    console.log(`Task aborted with:\n${JSON.stringify(err)}`);
    throw err;
  }
});
