import { database } from "../domain/database.mjs";
import { directoryInput } from "../domain/validation.mjs";
import { listDirectory } from "../domain/profiles.mjs";
export default defineEventHandler((event) =>
  apiResult(async () => {
    await activeIdentity(event);
    return listDirectory(database(), directoryInput(getQuery(event)));
  }),
);
