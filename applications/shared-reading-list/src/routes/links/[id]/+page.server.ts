import { fail, redirect, error } from "@sveltejs/kit";
import { getLink, updateLink, deleteLink } from "$lib/server/library";
import { linkInput, validId } from "$lib/server/input";
export async function load({ params, locals }) {
  if (!locals.user) redirect(303, "/sign-in");
  if (!validId(params.id)) error(404, { message: "Link not found" });
  const link = await getLink(params.id);
  if (!link) error(404, { message: "Link not found" });
  return { link, isOwner: link.ownerId === locals.user.id };
}
async function mutation(event, deleting) {
  if (!event.locals.user) return fail(401, { message: "Sign in first" });
  if (!validId(event.params.id))
    return fail(404, { message: "Link not found" });
  const data = Object.fromEntries(await event.request.formData());
  const version = Number(data.version);
  if (!Number.isSafeInteger(version) || version < 1)
    return fail(400, { message: "Invalid link version" });
  let input;
  if (!deleting)
    try {
      input = linkInput(data);
    } catch (e) {
      return fail(400, { message: e.message });
    }
  let result;
  try {
    result = deleting
      ? await deleteLink(event.params.id, event.locals.user.id, version)
      : await updateLink(event.params.id, event.locals.user.id, version, input);
  } catch (e) {
    if (e.cause?.code === "23505" || e.code === "23505")
      return fail(409, { message: "You already saved this URL" });
    throw e;
  }
  if (!result)
    return fail(409, {
      message:
        "This link changed or you do not own it. Refresh before trying again.",
    });
  redirect(303, deleting ? "/" : `/links/${event.params.id}`);
}
export const actions = {
  update: (event) => mutation(event, false),
  delete: (event) => mutation(event, true),
};
