import { createTRPCClient, httpLink } from "@trpc/client";
import type { AppRouter } from "../server/router";
export const client = createTRPCClient<AppRouter>({
  links: [
    httpLink({
      url: "/api/trpc",
      headers: () => ({ "X-Expense-Review": "1" }),
    }),
  ],
});
