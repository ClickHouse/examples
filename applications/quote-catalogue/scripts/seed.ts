import { createDb } from "../src/server/db";
const db = createDb();
try {
  await db.transaction().execute(async (trx) => {
    await trx
      .insertInto("products")
      .values([
        {
          id: 1,
          name: "Cinema camera",
          category: "Camera",
          description:
            "A compact 4K body for interviews and short productions.",
          rate_minor: 6500,
        },
        {
          id: 2,
          name: "Portrait lens",
          category: "Camera",
          description:
            "A fast 50mm prime for crisp portraits and close details.",
          rate_minor: 2200,
        },
        {
          id: 3,
          name: "LED panel",
          category: "Lighting",
          description:
            "Soft adjustable light for a small studio or interview set.",
          rate_minor: 1800,
        },
        {
          id: 4,
          name: "Light stand",
          category: "Lighting",
          description:
            "Stable support with a sandbag for each mounted fixture.",
          rate_minor: 800,
        },
        {
          id: 5,
          name: "Shotgun microphone",
          category: "Audio",
          description: "Directional audio capture with a windshield and mount.",
          rate_minor: 1600,
        },
        {
          id: 6,
          name: "Audio recorder",
          category: "Audio",
          description:
            "Four inputs and a portable recorder for location sound.",
          rate_minor: 2400,
        },
        {
          id: 7,
          name: "Video tripod",
          category: "Support",
          description: "A fluid head for smooth pans and repeatable framing.",
          rate_minor: 1400,
        },
        {
          id: 8,
          name: "Portable power kit",
          category: "Support",
          description:
            "Charged batteries and adapters for a full field session.",
          rate_minor: 1200,
        },
      ])
      .onConflict((oc) => oc.column("id").doNothing())
      .execute();
    await trx
      .insertInto("quotes")
      .values([
        {
          id: 1,
          title: "Studio session",
          days: 1,
          revision: 0,
          updated_at: new Date().toISOString(),
        },
        {
          id: 2,
          title: "Field shoot",
          days: 1,
          revision: 0,
          updated_at: new Date().toISOString(),
        },
      ])
      .onConflict((oc) => oc.column("id").doNothing())
      .execute();
  });
  console.log("Seeded 8 products and 2 quotes without resetting drafts");
} finally {
  await db.destroy();
}
