import { auth } from "$lib/server/auth";
import { svelteKitHandler } from "better-auth/svelte-kit";
import { building } from "$app/environment";
export async function handle({ event, resolve }) {
  if (!building) {
    const result = await auth.api.getSession({
      headers: event.request.headers,
    });
    event.locals.user = result?.user;
  }
  return svelteKitHandler({ event, resolve, auth, building });
}
