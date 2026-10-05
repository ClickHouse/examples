import {
  randomBytes,
  scryptSync,
  timingSafeEqual,
  createHash,
} from "node:crypto";
import type { Pool } from "pg";
export function passwordHash(password: string, salt: string) {
  return scryptSync(password, salt, 64).toString("hex");
}
export function passwordMatches(password: string, salt: string, hash: string) {
  if (!/^[a-f0-9]{128}$/.test(hash)) return false;
  return timingSafeEqual(
    Buffer.from(passwordHash(password, salt), "hex"),
    Buffer.from(hash, "hex"),
  );
}
export function tokenHash(token: string) {
  return createHash("sha256").update(token).digest("hex");
}
export type Session = {
  userId: string;
  email: string;
  workspaceId: string;
  workspaceName: string;
};
export async function login(pool: Pool, email: string, password: string) {
  const { rows } = await pool.query(
    "SELECT * FROM tracker_private.accounts WHERE email=$1",
    [email],
  );
  const account = rows[0];
  if (
    !account ||
    !passwordMatches(password, account.salt, account.password_hash)
  )
    return null;
  const token = randomBytes(32).toString("hex");
  await pool.query(
    "INSERT INTO tracker_private.sessions(token_hash,account_id,expires_at) VALUES($1,$2,now()+interval '2 hours')",
    [tokenHash(token), account.id],
  );
  return token;
}
export function cookieToken(cookie: string | undefined) {
  const matches =
    cookie
      ?.split(";")
      .map((s) => s.trim())
      .filter((s) => s.startsWith("ground_session=")) ?? [];
  if (matches.length !== 1) return null;
  const value = matches[0]!.slice("ground_session=".length);
  return /^[a-f0-9]{64}$/.test(value) ? value : null;
}
export async function getSession(
  pool: Pool,
  cookie: string | undefined,
): Promise<Session | null> {
  const token = cookieToken(cookie);
  if (!token) return null;
  const { rows } = await pool.query(
    `SELECT a.id AS "userId",a.email,a.workspace_id AS "workspaceId",a.workspace_name AS "workspaceName" FROM tracker_private.sessions s JOIN tracker_private.accounts a ON a.id=s.account_id WHERE s.token_hash=$1 AND s.expires_at>now()`,
    [tokenHash(token)],
  );
  return rows[0] ?? null;
}
export async function logout(pool: Pool, cookie: string | undefined) {
  const token = cookieToken(cookie);
  if (token)
    await pool.query(
      "DELETE FROM tracker_private.sessions WHERE token_hash=$1",
      [tokenHash(token)],
    );
}
