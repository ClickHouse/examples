import { db, client } from "../src/lib/server/db";
import { user, links } from "../src/lib/server/schema";
try {
  await db
    .insert(user)
    .values({
      id: "seed-reader",
      name: "The reading team",
      email: "seed@example.invalid",
      emailVerified: false,
    })
    .onConflictDoNothing();
  await db
    .insert(links)
    .values([
      {
        id: "00000000-0000-4000-8000-000000000001",
        ownerId: "seed-reader",
        title: "Postgres full-text search",
        url: "https://www.postgresql.org/docs/current/textsearch.html",
        notes:
          "How Postgres turns text into searchable documents, with GIN indexes.",
        tags: ["postgres", "search"],
      },
      {
        id: "00000000-0000-4000-8000-000000000002",
        ownerId: "seed-reader",
        title: "SvelteKit form actions",
        url: "https://svelte.dev/docs/kit/form-actions",
        notes: "Server-side form handling and progressive enhancement.",
        tags: ["svelte", "web"],
      },
    ])
    .onConflictDoNothing();
  console.log("Seed complete (demo owner has no sign-in account)");
} finally {
  await client.end();
}
