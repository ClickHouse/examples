import { and, desc, eq, sql } from "drizzle-orm";
import { db } from "./db";
import { links, user } from "./schema";
import type { LinkInput } from "./input";
export async function listLinks(q = "", tag = "") {
  return db
    .select({
      id: links.id,
      title: links.title,
      url: links.url,
      notes: links.notes,
      tags: links.tags,
      ownerId: links.ownerId,
      ownerName: user.name,
      createdAt: links.createdAt,
    })
    .from(links)
    .innerJoin(user, eq(links.ownerId, user.id))
    .where(
      and(
        q
          ? sql`${links.search} @@ websearch_to_tsquery('english', ${q})`
          : undefined,
        tag ? sql`${links.tags} @> ARRAY[${tag}]::text[]` : undefined,
      ),
    )
    .orderBy(desc(links.createdAt), desc(links.id))
    .limit(100);
}
export async function getLink(id: string) {
  return (await db.select().from(links).where(eq(links.id, id)).limit(1))[0];
}
export async function createLink(
  ownerId: string,
  input: LinkInput,
) {
  return (
    await db
      .insert(links)
      .values({ ...input, ownerId })
      .returning()
  )[0];
}
export async function updateLink(
  id: string,
  ownerId: string,
  version: number,
  input: LinkInput,
) {
  return (
    await db
      .update(links)
      .set({
        ...input,
        version: sql`${links.version} + 1`,
        updatedAt: new Date(),
      })
      .where(
        and(
          eq(links.id, id),
          eq(links.ownerId, ownerId),
          eq(links.version, version),
        ),
      )
      .returning()
  )[0];
}
export async function deleteLink(id: string, ownerId: string, version: number) {
  return (
    await db
      .delete(links)
      .where(
        and(
          eq(links.id, id),
          eq(links.ownerId, ownerId),
          eq(links.version, version),
        ),
      )
      .returning()
  )[0];
}
