const { readFileSync } = require("node:fs");
const { join } = require("node:path");
const { createClickHouseClient } = require("../config");

async function setup(client) {
  const ddl = readFileSync(join(__dirname, "ddl.sql"), "utf8");
  for (const query of ddl.split(";").map((s) => s.trim()).filter(Boolean)) {
    await client.command({ query });
  }
}
module.exports = { setup };
if (require.main === module) {
  const client = createClickHouseClient();
  setup(client).then(() => console.log("Created trades and quotes tables"))
    .catch((error) => { console.error(error); process.exitCode = 1; })
    .finally(() => client.close());
}
