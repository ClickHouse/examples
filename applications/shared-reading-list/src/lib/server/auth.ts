import { betterAuth } from "better-auth/minimal";
import { drizzleAdapter } from "better-auth/adapters/drizzle";
import { db } from "./db";
import * as schema from "./schema";
if (
  !process.env.BETTER_AUTH_SECRET ||
  process.env.BETTER_AUTH_SECRET.length < 32
)
  throw new Error("Set a random BETTER_AUTH_SECRET of at least 32 characters");
const baseURL = new URL(process.env.BETTER_AUTH_URL ?? "");
if (
  !["http:", "https:"].includes(baseURL.protocol) ||
  baseURL.origin !== process.env.BETTER_AUTH_URL
)
  throw new Error(
    "BETTER_AUTH_URL must be an HTTP(S) origin without a trailing slash or path",
  );
export const auth = betterAuth({
  database: drizzleAdapter(db, { provider: "pg", schema }),
  secret: process.env.BETTER_AUTH_SECRET,
  baseURL: baseURL.origin,
  trustedOrigins: [baseURL.origin],
  emailAndPassword: {
    enabled: true,
    disableSignUp: process.env.SIGNUP_ENABLED !== "true",
    minPasswordLength: 12,
  },
  session: {
    expiresIn: 60 * 60 * 24 * 7,
    updateAge: 60 * 60 * 24,
    cookieCache: { enabled: false },
  },
  rateLimit: { enabled: true },
});
