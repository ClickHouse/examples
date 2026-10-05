import { postgraphile } from "postgraphile";
import { makePgService } from "postgraphile/adaptors/pg";
import { PostGraphileAmberPreset } from "postgraphile/presets/amber";
import type {} from "postgraphile/grafserv/node";
import { GraphQLError } from "graphql";
import type { Pool } from "pg";
import type { IncomingMessage } from "node:http";
import type { Session } from "./sessions.ts";
export const verifiedSessions = new WeakMap<IncomingMessage, Session>();
export function createGraphile(pool: Pool) {
  const preset = {
    extends: [PostGraphileAmberPreset],
    pgServices: [
      makePgService({
        pool,
        schemas: ["tracker"],
        pubsub: false,
        pgSettingsForIntrospection: { role: "tracker_member" },
      }),
    ],
    grafast: {
      context(request) {
        const req = request.node?.req;
        const session = req && verifiedSessions.get(req);
        if (!session)
          throw new GraphQLError("Sign in required", {
            extensions: { code: "UNAUTHENTICATED" },
          });
        return {
          pgSettings: {
            role: "tracker_member",
            "app.workspace_id": session.workspaceId,
            statement_timeout: "5000",
          },
        };
      },
    },
  } satisfies GraphileConfig.Preset;
  return postgraphile(preset);
}
