import { randomBytes, randomUUID } from "node:crypto";
import { z } from "zod";
import type { Pool, PoolClient } from "pg";
import {
  defaultQrStyle,
  linkInputSchema,
  mergeUtm,
  qrStyleSchema,
  requestDimensions,
  utmSchema,
} from "../lib/domain";
import type {
  ClickEvent,
  Folder,
  Link,
  LinkInput,
  QrStyle,
  UtmTemplate,
  UtmValues,
} from "../lib/types";
import { getPostgres, transaction } from "./db";
import { defaultLinkHostname, isCustomDomainHosted } from "./domain-routing";

export { flushOutbox } from "./outbox";

type Queryable = Pick<Pool | PoolClient, "query">;
export class NotFoundError extends Error {
  constructor() {
    super("This item was not found.");
    this.name = "NotFoundError";
  }
}
const uuid = z.string().uuid();

/** The caller must obtain clerkUserId from Clerk's verified server session. */
export async function getAccountId(
  clerkUserId: string,
  db: Queryable = getPostgres(),
): Promise<string> {
  if (!clerkUserId || clerkUserId.length > 255)
    throw new Error("Sign in to continue.");
  const result = await db.query(
    `INSERT INTO accounts (clerk_user_id) VALUES ($1)
     ON CONFLICT (clerk_user_id) DO UPDATE SET clerk_user_id = EXCLUDED.clerk_user_id RETURNING id`,
    [clerkUserId],
  );
  return result.rows[0].id;
}

function toLink(row: Record<string, any>): Link {
  return {
    id: row.id,
    slug: row.slug,
    domainId: row.domain_id ?? null,
    domainHostname: row.domain_hostname ?? null,
    title: row.title,
    destination: row.destination,
    resolvedUrl: row.resolved_url,
    utm: row.utm,
    tags: row.tags,
    folderId: row.folder_id ?? null,
    enabled: row.enabled,
    createdAt: new Date(row.created_at).toISOString(),
    updatedAt: new Date(row.updated_at).toISOString(),
    qrStyle: row.qr_style ?? { ...defaultQrStyle },
  };
}
const linkSelect =
  "SELECT l.*, q.style AS qr_style, lf.folder_id, d.hostname AS domain_hostname FROM links l LEFT JOIN qr_styles q ON q.link_id = l.id AND q.account_id = l.account_id LEFT JOIN link_folders lf ON lf.link_id = l.id AND lf.account_id = l.account_id LEFT JOIN custom_domains d ON d.id = l.domain_id AND d.account_id = l.account_id";

export async function listLinks(
  clerkUserId: string,
  filter: { search?: string; tag?: string; folderId?: string | null } = {},
): Promise<Link[]> {
  const accountId = await getAccountId(clerkUserId);
  const search = z
    .string()
    .max(200)
    .parse(filter.search ?? "");
  const tag = z
    .string()
    .max(40)
    .parse(filter.tag ?? "");
  const folderId = uuid.nullable().optional().parse(filter.folderId);
  const result = await getPostgres().query(
    `${linkSelect} WHERE l.account_id = $1 AND ($2 = '' OR l.title ILIKE '%' || $2 || '%' OR l.slug ILIKE '%' || $2 || '%' OR l.destination ILIKE '%' || $2 || '%')
     AND ($3 = '' OR $3 = ANY(l.tags))
     AND ($4::boolean OR ($5::uuid IS NULL AND lf.folder_id IS NULL) OR lf.folder_id = $5::uuid)
     ORDER BY l.created_at DESC LIMIT 500`,
    [accountId, search, tag, folderId === undefined, folderId ?? null],
  );
  return result.rows.map(toLink);
}

export async function getLink(clerkUserId: string, id: string): Promise<Link> {
  uuid.parse(id);
  const accountId = await getAccountId(clerkUserId);
  const result = await getPostgres().query(
    `${linkSelect} WHERE l.account_id = $1 AND l.id = $2`,
    [accountId, id],
  );
  if (!result.rows[0]) throw new NotFoundError();
  return toLink(result.rows[0]);
}

export async function listTags(
  clerkUserId: string,
  query = "",
): Promise<string[]> {
  const search = z.string().trim().max(40).parse(query);
  const accountId = await getAccountId(clerkUserId);
  const result = await getPostgres().query(
    `SELECT name FROM account_tags
     WHERE account_id = $1 AND strpos(lower(name), lower($2)) > 0
     ORDER BY lower(name), name LIMIT 20`,
    [accountId, search],
  );
  return result.rows.map((row) => row.name);
}

const folderName = z.string().trim().min(1).max(80);

export async function listFolders(clerkUserId: string): Promise<Folder[]> {
  const accountId = await getAccountId(clerkUserId);
  const result = await getPostgres().query(
    "SELECT id, name FROM folders WHERE account_id = $1 ORDER BY lower(name), name",
    [accountId],
  );
  return result.rows;
}

export async function createFolder(clerkUserId: string, name: string): Promise<Folder> {
  const parsed = folderName.parse(name);
  const accountId = await getAccountId(clerkUserId);
  try {
    return await transaction(async (db) => {
      await db.query("SELECT id FROM accounts WHERE id = $1 FOR UPDATE", [accountId]);
      const count = await db.query("SELECT count(*)::int AS count FROM folders WHERE account_id = $1", [accountId]);
      if (count.rows[0].count >= 100) throw new Error("You can have up to 100 folders.");
      const result = await db.query(
        "INSERT INTO folders (account_id, name) VALUES ($1, $2) RETURNING id, name",
        [accountId, parsed],
      );
      return result.rows[0];
    });
  } catch (error) {
    if ((error as { code?: string }).code === "23505") throw new Error("That folder name is already in use. Choose another.");
    throw error;
  }
}

export async function updateFolder(clerkUserId: string, id: string, name: string): Promise<Folder> {
  uuid.parse(id);
  const parsed = folderName.parse(name);
  const accountId = await getAccountId(clerkUserId);
  try {
    const result = await getPostgres().query(
      "UPDATE folders SET name = $3 WHERE account_id = $1 AND id = $2 RETURNING id, name",
      [accountId, id, parsed],
    );
    if (!result.rows[0]) throw new NotFoundError();
    return result.rows[0];
  } catch (error) {
    if ((error as { code?: string }).code === "23505") throw new Error("That folder name is already in use. Choose another.");
    throw error;
  }
}

export async function deleteFolder(clerkUserId: string, id: string): Promise<void> {
  uuid.parse(id);
  const accountId = await getAccountId(clerkUserId);
  const result = await getPostgres().query(
    "DELETE FROM folders WHERE account_id = $1 AND id = $2 RETURNING id", [accountId, id],
  );
  if (!result.rows[0]) throw new NotFoundError();
}

async function assignFolder(db: Queryable, accountId: string, linkId: string, folderId: string | null) {
  if (folderId) {
    // Hold the folder through the assignment; deletion then safely unfiles links.
    const owned = await db.query("SELECT id FROM folders WHERE account_id = $1 AND id = $2 FOR KEY SHARE", [accountId, folderId]);
    if (!owned.rows[0]) throw new NotFoundError();
    await db.query(
      `INSERT INTO link_folders (account_id, link_id, folder_id) VALUES ($1, $2, $3)
       ON CONFLICT (link_id) DO UPDATE SET folder_id = EXCLUDED.folder_id WHERE link_folders.account_id = $1`,
      [accountId, linkId, folderId],
    );
  } else {
    await db.query("DELETE FROM link_folders WHERE account_id = $1 AND link_id = $2", [accountId, linkId]);
  }
}

async function rememberTags(db: Queryable, accountId: string, tags: string[]) {
  if (!tags.length) return;
  await db.query(
    `INSERT INTO account_tags (account_id, name)
     SELECT $1, unnest($2::text[]) ON CONFLICT DO NOTHING`,
    [accountId, tags],
  );
}

function translateConstraint(error: unknown): never {
  if ((error as { code?: string }).code === "23505")
    throw new Error("That slug or name is already in use. Choose another.");
  throw error;
}

export async function createLink(
  clerkUserId: string,
  input: LinkInput,
): Promise<Link> {
  const parsed = linkInputSchema.parse(input);
  const accountId = await getAccountId(clerkUserId);
  const { resolvedUrl, utm } = mergeUtm(parsed.destination, parsed.utm);
  const slug = parsed.slug || `l${randomBytes(7).toString("base64url")}`;
  try {
    const result = await transaction(async (db) => {
      // Serialize account creation limits across multiple app processes.
      await db.query("SELECT id FROM accounts WHERE id = $1 FOR UPDATE", [
        accountId,
      ]);
      const count = await db.query(
        "SELECT count(*)::int AS count FROM links WHERE account_id = $1 AND created_at > now() - interval '1 day'",
        [accountId],
      );
      if (count.rows[0].count >= 100)
        throw new Error(
          "You can create up to 100 links per day. Please try again tomorrow.",
        );
      let domainHostname: string | null = null;
      if (parsed.domainId) {
        // Hold ownership and verification stable through link insertion.
        const domain = await db.query(
          "SELECT hostname, status FROM custom_domains WHERE account_id = $1 AND id = $2 FOR SHARE",
          [accountId, parsed.domainId],
        );
        if (!domain.rows[0]) throw new NotFoundError();
        if (domain.rows[0].status !== "verified" || !isCustomDomainHosted(domain.rows[0].hostname)) {
          throw new Error("This domain is not ready for links. Verify its ownership and connect hosting first.");
        }
        domainHostname = domain.rows[0].hostname;
      }
      const inserted = await db.query(
        `INSERT INTO links (account_id, slug, title, destination, resolved_url, utm, tags, enabled, domain_id)
        VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9) RETURNING *`,
        [
          accountId,
          slug,
          parsed.title || new URL(parsed.destination).hostname,
          parsed.destination,
          resolvedUrl,
          JSON.stringify(utm),
          parsed.tags,
          parsed.enabled,
          parsed.domainId ?? null,
        ],
      );
      await rememberTags(db, accountId, parsed.tags);
      await assignFolder(db, accountId, inserted.rows[0].id, parsed.folderId ?? null);
      inserted.rows[0].folder_id = parsed.folderId;
      inserted.rows[0].domain_hostname = domainHostname;
      return inserted;
    });
    return toLink(result.rows[0]);
  } catch (error) {
    return translateConstraint(error);
  }
}

/** Replaces editable fields; omitted folderId preserves membership. Public slug and domain are immutable. */
export async function updateLink(
  clerkUserId: string,
  id: string,
  input: LinkInput,
): Promise<Link> {
  uuid.parse(id);
  const parsed = linkInputSchema.parse(input);
  const accountId = await getAccountId(clerkUserId);
  const { resolvedUrl, utm } = mergeUtm(parsed.destination, parsed.utm);
  await transaction(async (db) => {
    const result = await db.query(
      `UPDATE links SET title = $3, destination = $4, resolved_url = $5,
      utm = $6, tags = $7, enabled = $8, revision = revision + 1, updated_at = now()
      WHERE account_id = $1 AND id = $2 RETURNING *`,
      [
        accountId,
        id,
        parsed.title || new URL(parsed.destination).hostname,
        parsed.destination,
        resolvedUrl,
        JSON.stringify(utm),
        parsed.tags,
        parsed.enabled,
      ],
    );
    if (!result.rows[0]) throw new NotFoundError();
    if (parsed.domainId !== undefined && parsed.domainId !== result.rows[0].domain_id) {
      throw new Error("A link's domain cannot be changed. Create a new link to use another domain.");
    }
    await rememberTags(db, accountId, parsed.tags);
    if (parsed.folderId !== undefined) await assignFolder(db, accountId, id, parsed.folderId);
  });
  return getLink(clerkUserId, id);
}

export async function saveQrStyle(
  clerkUserId: string,
  linkId: string,
  input: QrStyle,
): Promise<QrStyle> {
  uuid.parse(linkId);
  const style = qrStyleSchema.parse(input);
  const accountId = await getAccountId(clerkUserId);
  const result = await getPostgres().query(
    `INSERT INTO qr_styles (account_id, link_id, style)
    SELECT account_id, id, $3::jsonb FROM links WHERE account_id = $1 AND id = $2
    ON CONFLICT (link_id) DO UPDATE SET style = EXCLUDED.style WHERE qr_styles.account_id = $1 RETURNING style`,
    [accountId, linkId, JSON.stringify(style)],
  );
  if (!result.rows[0]) throw new NotFoundError();
  return result.rows[0].style;
}

function toTemplate(row: Record<string, any>): UtmTemplate {
  return {
    id: row.id,
    name: row.name,
    values: row.values,
    createdAt: new Date(row.created_at).toISOString(),
  };
}
const templateSchema = z
  .object({ name: z.string().trim().min(1).max(80), values: utmSchema })
  .strict();

export async function listTemplates(
  clerkUserId: string,
): Promise<UtmTemplate[]> {
  const accountId = await getAccountId(clerkUserId);
  const result = await getPostgres().query(
    "SELECT * FROM utm_templates WHERE account_id = $1 ORDER BY name",
    [accountId],
  );
  return result.rows.map(toTemplate);
}

export async function createTemplate(
  clerkUserId: string,
  input: { name: string; values: UtmValues },
): Promise<UtmTemplate> {
  const parsed = templateSchema.parse(input);
  const accountId = await getAccountId(clerkUserId);
  try {
    const result = await getPostgres().query(
      "INSERT INTO utm_templates (account_id, name, values) VALUES ($1,$2,$3) RETURNING *",
      [accountId, parsed.name, JSON.stringify(parsed.values)],
    );
    return toTemplate(result.rows[0]);
  } catch (error) {
    return translateConstraint(error);
  }
}

export async function updateTemplate(
  clerkUserId: string,
  id: string,
  input: { name: string; values: UtmValues },
): Promise<UtmTemplate> {
  uuid.parse(id);
  const parsed = templateSchema.parse(input);
  const accountId = await getAccountId(clerkUserId);
  try {
    const result = await getPostgres().query(
      "UPDATE utm_templates SET name = $3, values = $4, updated_at = now() WHERE account_id = $1 AND id = $2 RETURNING *",
      [accountId, id, parsed.name, JSON.stringify(parsed.values)],
    );
    if (!result.rows[0]) throw new NotFoundError();
    return toTemplate(result.rows[0]);
  } catch (error) {
    return translateConstraint(error);
  }
}

export async function deleteTemplate(
  clerkUserId: string,
  id: string,
): Promise<void> {
  uuid.parse(id);
  const accountId = await getAccountId(clerkUserId);
  const result = await getPostgres().query(
    "DELETE FROM utm_templates WHERE account_id = $1 AND id = $2 RETURNING id",
    [accountId, id],
  );
  if (!result.rows[0]) throw new NotFoundError();
}

export type RedirectResult =
  { status: 302; location: string } | { status: 404 | 410 };
export async function resolveRedirect(
  slug: string,
  metadata: { referrer?: string | null; userAgent?: string } = {},
  recordEvent = true,
  hostname?: string,
): Promise<RedirectResult> {
  if (!/^[a-zA-Z0-9][a-zA-Z0-9_-]{2,47}$/.test(slug)) return { status: 404 };
  // HTTP callers always supply the URL hostname, never forwarded headers.
  const host = hostname?.toLowerCase() ?? defaultLinkHostname();
  const isDefault = host === defaultLinkHostname();
  if (!isDefault && !isCustomDomainHosted(host)) return { status: 404 };
  return transaction(async (db) => {
    let domainId: string | null = null;
    let accountId: string | null = null;
    if (!isDefault) {
      // Prevent revocation/deletion racing the redirect's state snapshot.
      const domain = await db.query(
        "SELECT id, account_id FROM custom_domains WHERE hostname = $1 AND status = 'verified' FOR SHARE",
        [host],
      );
      if (!domain.rows[0]) return { status: 404 };
      domainId = domain.rows[0].id;
      accountId = domain.rows[0].account_id;
    }
    // Shared lock makes the redirect's state/event snapshot atomic with link edits.
    const result = await db.query(
      `SELECT * FROM links WHERE slug = $1
       AND (($2::uuid IS NULL AND domain_id IS NULL) OR (domain_id = $2::uuid AND account_id = $3::uuid)) FOR SHARE`,
      [slug, domainId, accountId],
    );
    const row = result.rows[0];
    if (!row) return { status: 404 };
    if (!row.enabled) return { status: 410 };
    if (recordEvent) {
      const utm = row.utm as UtmValues;
      const event: ClickEvent = {
        event_id: randomUUID(),
        account_id: row.account_id,
        link_id: row.id,
        occurred_at: new Date()
          .toISOString()
          .replace("T", " ")
          .replace("Z", ""),
        utm_source: utm.source || "",
        utm_medium: utm.medium || "",
        utm_campaign: utm.campaign || "",
        utm_term: utm.term || "",
        utm_content: utm.content || "",
        ...requestDimensions(
          metadata.referrer,
          metadata.userAgent?.slice(0, 2048),
        ),
        is_demo: 0,
      };
      await db.query(
        "INSERT INTO click_outbox (event_id, account_id, event) VALUES ($1,$2,$3)",
        [event.event_id, event.account_id, JSON.stringify(event)],
      );
    }
    return { status: 302, location: row.resolved_url };
  });
}
