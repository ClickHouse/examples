import { createStart, createCsrfMiddleware, createServerOnlyFn } from "@tanstack/react-start";
import { clerkMiddleware } from "@clerk/tanstack-react-start/server";
import { runtimeEnvironment } from "./server/runtime";

const clerkOptions = createServerOnlyFn(() => ({
  // Read trusted configuration per request. This server-only boundary also
  // removes the Workers/Node request runtime from the browser bundle.
  authorizedParties: [
    new URL(runtimeEnvironment("APP_URL") || "http://localhost:4317").origin,
  ],
}));

export const startInstance = createStart(() => ({
  requestMiddleware: [
    createCsrfMiddleware({ filter: (ctx) => ctx.handlerType === "serverFn" }),
    clerkMiddleware(clerkOptions),
  ],
}));
