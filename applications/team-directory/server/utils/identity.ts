import { database } from "../domain/database.mjs";
export async function activeIdentity(event: any) {
  const session = await getUserSession(event);
  if (!session.user?.id)
    throw createError({
      statusCode: 401,
      statusMessage: "Sign in to continue.",
    });
  const user = await database()("users")
    .select("id", "display_name")
    .where({ id: session.user.id, active: true })
    .first();
  if (!user) {
    await clearUserSession(event);
    throw createError({ statusCode: 401, statusMessage: "Sign in again." });
  }
  return user;
}
export async function apiResult(action: () => Promise<any>) {
  try {
    return await action();
  } catch (error: any) {
    if (error.statusCode)
      throw createError({
        statusCode: error.statusCode,
        statusMessage: error.message,
      });
    // No database re-query in the error path.
    console.error("Directory request failed", {
      code: error.code || "database-unavailable",
    });
    throw createError({
      statusCode: 503,
      statusMessage:
        "The directory is temporarily unavailable. Please try again.",
    });
  }
}
