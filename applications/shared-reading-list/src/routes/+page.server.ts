import { fail, redirect } from "@sveltejs/kit";
import { listLinks, createLink } from "$lib/server/library";
import { linkInput } from "$lib/server/input";
export async function load({ locals, url }) {
  if (!locals.user) redirect(303, "/sign-in");
  const q = (url.searchParams.get("q") ?? "").trim();
  const tag = (url.searchParams.get("tag") ?? "").trim().toLowerCase();
  if (q.length > 100 || (tag && !/^[a-z0-9][a-z0-9-]{0,29}$/.test(tag)))
    return {
      links: [],
      q,
      tag,
      filterError: "Use a search up to 100 characters and a valid tag",
    };
  return { links: await listLinks(q, tag), q, tag };
}
export const actions = {
  save: async ({ locals, request }) => {
    if (!locals.user) return fail(401, { message: "Sign in to save a link" });
    const data = Object.fromEntries(await request.formData());
    let input;
    try {
      input = linkInput(data);
    } catch (e) {
      return fail(400, { message: e.message, values: data });
    }
    let link;
    try {
      link = await createLink(locals.user.id, input);
    } catch (e) {
      if (e.cause?.code === "23505" || e.code === "23505")
        return fail(409, {
          message: "You already saved this URL",
          values: data,
        });
      throw e;
    }
    redirect(303, `/links/${link.id}`);
  },
};
