import { createORPCClient } from "@orpc/client";
import { RPCLink } from "@orpc/client/fetch";
import type { ContractRouterClient } from "@orpc/contract";
import type { contract } from "./contract";
export function quoteClient() {
  return createORPCClient<ContractRouterClient<typeof contract>>(
    new RPCLink({
      url: () => window.location.origin + "/rpc",
      headers: { "X-Quote-Catalogue": "1" },
    }),
  );
}
