import { database } from "../domain/database.mjs";
export default defineEventHandler((event) =>
  apiResult(async () => {
    await activeIdentity(event);
    return database()("skills").select("id", "name").orderBy("name");
  }),
);
