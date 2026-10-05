import type { APIRoute } from "astro";
import { RPCHandler } from "@orpc/server/fetch";
import { router } from "../../server/router";
const handler = new RPCHandler(router);
export const ALL: APIRoute = async ({ request }) => {
  const { response } = await handler.handle(request, {
    prefix: "/rpc",
    context: {},
  });
  return response ?? new Response("Not found", { status: 404 });
};
