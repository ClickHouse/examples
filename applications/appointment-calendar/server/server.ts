import express from "express";
import { fileURLToPath } from "node:url";
import { createExpressEndpoints, initServer } from "@ts-rest/express";
import { contract } from "../shared/contract.js";
import { readDay, updateAppointment, BookingError } from "./appointments.js";
import { getPool } from "./db.js";
const app = express();
const host = process.env.HOST ?? "127.0.0.1",
  port = Number(process.env.PORT ?? "4331");
const origin = process.env.APP_ORIGIN ?? `http://${host}:${port}`;
if (!["127.0.0.1", "::1"].includes(host))
  throw new Error("HOST must use loopback");
app.disable("x-powered-by");
app.use((req, res, next) => {
  if (req.headers.host !== new URL(origin).host)
    return void res.status(403).json({ message: "Invalid host." });
  if (
    !["GET", "HEAD"].includes(req.method) &&
    (req.headers.origin !== origin ||
      req.headers["x-workshop-calendar"] !== "1")
  )
    return void res
      .status(403)
      .json({ message: "Use the local same-origin client." });
  res.setHeader("Cache-Control", "no-store");
  next();
});
app.use(express.json({ limit: "16kb" }));
const s = initServer();
createExpressEndpoints(
  contract,
  s.router(contract, {
    day: async ({ query }) => {
      try {
        return { status: 200 as const, body: await readDay(query.date) };
      } catch (e) {
        if (e instanceof BookingError && e.status === 400)
          return { status: 400 as const, body: { message: e.message } };
        return {
          status: 500 as const,
          body: { message: "The saved calendar could not be loaded." },
        };
      }
    },
    update: async ({ params, body }) => {
      try {
        return {
          status: 200 as const,
          body: await updateAppointment(Number(params.id), body),
        };
      } catch (e) {
        if (e instanceof BookingError)
          return { status: e.status, body: { message: e.message } };
        return {
          status: 500 as const,
          body: { message: "The appointment could not be saved." },
        };
      }
    },
  }),
  app,
  {
    responseValidation: true,
    logInitialization: false,
    requestValidationErrorHandler: (_err, _req, res) =>
      res
        .status(400)
        .json({
          message:
            "Use a valid appointment request with explicit timestamp offset.",
        }),
  },
);
const publicDir = fileURLToPath(new URL("../ui/", import.meta.url));
app.use(express.static(publicDir));
app.get("*", (_req, res) => res.sendFile(publicDir + "index.html"));
app.use(
  (
    _err: unknown,
    _req: express.Request,
    res: express.Response,
    _next: express.NextFunction,
  ) => res.status(400).json({ message: "Invalid request." }),
);
const server = app.listen(port, host, () =>
  console.log("Workshop calendar ready"),
);
process.on("SIGTERM", () =>
  server.close(() => {
    void getPool()
      .end()
      .then(() => process.exit(0));
  }),
);
