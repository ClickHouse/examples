import { profileId } from "../../domain/validation.mjs";
import { database } from "../../domain/database.mjs";
import { readProfile } from "../../domain/profiles.mjs";
export default defineEventHandler((event) =>
  apiResult(async () => {
    await activeIdentity(event);
    const id = profileId(getRouterParam(event, "id"));
    return readProfile(database(), id);
  }),
);
