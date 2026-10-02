import { databaseConfig } from "./server/domain/database.mjs";
export default {
  ...databaseConfig(),
  migrations: {
    directory: "./migrations",
    extension: "mjs",
    loadExtensions: [".mjs"],
  },
  seeds: { directory: "./seeds", extension: "mjs", loadExtensions: [".mjs"] },
};
