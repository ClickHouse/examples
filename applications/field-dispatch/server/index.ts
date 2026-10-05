import { createApplication } from "./http";
import { closeDatabase } from "./database";
const port = Number(process.env.PORT ?? 3002);
if (!Number.isInteger(port) || port < 1 || port > 65535)
  throw new Error("Use a valid PORT.");
const server = createApplication();
server.listen(port, "127.0.0.1", () =>
  console.log(`Field dispatch at http://127.0.0.1:${port}`),
);
process.once("SIGTERM", () =>
  server.close(() => {
    void closeDatabase().then(() => process.exit(0));
  }),
);
process.once("SIGINT", () =>
  server.close(() => {
    void closeDatabase().then(() => process.exit(0));
  }),
);
