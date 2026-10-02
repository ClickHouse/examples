import { randomUUID } from "node:crypto";
import { Scrypt } from "@adonisjs/hash/drivers/scrypt";
export async function seed(knex) {
  const password = process.env.DEMO_PASSWORD;
  if (!password || password.length < 16)
    throw new Error(
      "Provide DEMO_PASSWORD of at least 16 characters. Seed only a new fixture.",
    );
  if ((await knex("users").count("* as count"))[0].count !== "0")
    throw new Error("Seed expects an empty directory.");
  const hash = await new Scrypt({}).make(password);
  await knex.transaction(async (trx) => {
    await trx("skills").insert(
      [
        "Design",
        "Postgres",
        "TypeScript",
        "Python",
        "Operations",
        "Support",
        "Accessibility",
        "Writing",
      ].map((name, i) => ({ id: i + 1, name })),
    );
    await trx("users").insert([
      {
        id: "00000000-0000-4000-8000-000000000001",
        email: "alex@example.test",
        password_hash: hash,
        display_name: "Alex Chen",
        biography: "Builds practical tools for the team.",
        location: "London",
      },
      {
        id: "00000000-0000-4000-8000-000000000002",
        email: "sam@example.test",
        password_hash: hash,
        display_name: "Sam Rivera",
        biography: "Helps colleagues solve customer problems.",
        location: "Berlin",
      },
      ...Array.from({ length: 14 }, (_, i) => ({
        id: randomUUID(),
        email: `teammate${i + 1}@example.test`,
        password_hash: hash,
        display_name: `Teammate ${String(i + 1).padStart(2, "0")}`,
        location: i % 2 ? "Berlin" : "London",
      })),
    ]);
    await trx("user_skills").insert([
      { user_id: "00000000-0000-4000-8000-000000000001", skill_id: 2 },
      { user_id: "00000000-0000-4000-8000-000000000002", skill_id: 6 },
    ]);
  });
}
