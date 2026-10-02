import { database } from "../../domain/database.mjs";
import { profileInput, profileId } from "../../domain/validation.mjs";
import { updateProfile } from "../../domain/profiles.mjs";
export default defineEventHandler((event) =>
  apiResult(async () => {
    const user = await activeIdentity(event);
    return updateProfile(
      database(),
      user.id,
      profileId(getRouterParam(event, "id")),
      profileInput(event.context.directoryBody),
    );
  }),
);
