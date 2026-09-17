export interface DatabaseConfig {
  url: string;
  caCertPath: string;
  maxConnections: number;
}

export interface Config {
  database: DatabaseConfig;
  apiKeys: ReadonlyMap<string, string>;
  hostname: string;
  port: number;
}

function required(env: Record<string, string | undefined>, name: string): string {
  const value = env[name]?.trim();
  if (!value) throw new Error(`${name} is required.`);
  return value;
}

function integer(value: string, name: string, min: number, max: number): number {
  if (!/^\d+$/.test(value)) throw new Error(`${name} must be an integer from ${min} to ${max}.`);
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed < min || parsed > max) {
    throw new Error(`${name} must be an integer from ${min} to ${max}.`);
  }
  return parsed;
}

export function validateDatabaseUrl(value: string): URL {
  let url: URL;
  try {
    url = new URL(value);
  } catch {
    throw new Error("DATABASE_URL must be a valid PostgreSQL URL.");
  }
  if (!['postgres:', 'postgresql:'].includes(url.protocol) || !url.hostname || !url.username || !url.password || url.pathname.length < 2) {
    throw new Error("DATABASE_URL must include a PostgreSQL host, database, username, and password.");
  }
  if (url.search || url.hash) {
    throw new Error("DATABASE_URL must not include query parameters or a fragment; TLS is configured explicitly.");
  }
  return url;
}

export function loadConfig(env: Record<string, string | undefined> = process.env): Config {
  const url = required(env, "DATABASE_URL");
  validateDatabaseUrl(url);
  let entries: unknown;
  try {
    entries = JSON.parse(required(env, "API_KEYS_JSON"));
  } catch {
    throw new Error("API_KEYS_JSON must be a JSON object mapping client IDs to tokens.");
  }
  if (!entries || typeof entries !== "object" || Array.isArray(entries)) {
    throw new Error("API_KEYS_JSON must be a JSON object mapping client IDs to tokens.");
  }
  const apiKeys = new Map<string, string>();
  const tokens = new Set<string>();
  for (const [clientId, token] of Object.entries(entries)) {
    if (!/^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$/.test(clientId)) {
      throw new Error("API_KEYS_JSON client IDs must be 1–64 ASCII letters, digits, underscores, or hyphens.");
    }
    if (typeof token !== "string" || !/^[A-Za-z0-9._~-]{32,256}$/.test(token) || /REPLACE|YOUR_TOKEN/i.test(token)) {
      throw new Error("API_KEYS_JSON tokens must be unique random strings of 32–256 token-safe characters.");
    }
    if (tokens.has(token)) throw new Error("API_KEYS_JSON must not reuse a token for multiple clients.");
    apiKeys.set(clientId, token);
    tokens.add(token);
  }
  if (apiKeys.size === 0 || apiKeys.size > 100) throw new Error("API_KEYS_JSON must contain 1–100 clients.");
  return {
    database: {
      url,
      caCertPath: required(env, "PG_CA_CERT_PATH"),
      maxConnections: integer(env.PG_MAX_CONNECTIONS ?? "5", "PG_MAX_CONNECTIONS", 1, 20),
    },
    apiKeys,
    hostname: env.HOST?.trim() || "127.0.0.1",
    port: integer(env.PORT ?? "3000", "PORT", 1, 65535),
  };
}
