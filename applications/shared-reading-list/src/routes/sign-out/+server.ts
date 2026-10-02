import { auth } from "$lib/server/auth";
export async function POST({ request }) {
  if (request.headers.get("origin") !== process.env.BETTER_AUTH_URL)
    return new Response("Invalid origin", { status: 403 });
  const response = await auth.api.signOut({
    headers: request.headers,
    asResponse: true,
  });
  const headers = new Headers(response.headers);
  headers.set("location", "/sign-in");
  return new Response(null, { status: 303, headers });
}
