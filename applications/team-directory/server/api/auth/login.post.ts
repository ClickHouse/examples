import { database } from "../../domain/database.mjs";
const attempts = new Map<string, { count: number; until: number }>();
export default defineEventHandler((event) =>
  apiResult(async () => {
    const ip = event.node.req.socket.remoteAddress || "local";
    const now = Date.now();
    for (const [key, entry] of attempts)
      if (entry.until <= now) attempts.delete(key);
    if (!attempts.has(ip) && attempts.size >= 1000)
      throw createError({
        statusCode: 429,
        statusMessage: "Sign-in is busy. Try again shortly.",
      });
    const attempt = attempts.get(ip) || { count: 0, until: now + 180000 };
    attempts.set(ip, attempt);
    if (++attempt.count > 12)
      throw createError({
        statusCode: 429,
        statusMessage: "Too many sign-in attempts. Try again in three minutes.",
      });
    const body = event.context.directoryBody;
    if (
      !body ||
      typeof body.email !== "string" ||
      typeof body.password !== "string" ||
      body.email.length > 254 ||
      body.password.length > 256 ||
      Object.keys(body).some((k) => !["email", "password"].includes(k))
    )
      throw createError({
        statusCode: 422,
        statusMessage: "Enter your email and password.",
      });
    const user = await database()("users")
      .where({ email: body.email.trim().toLowerCase(), active: true })
      .first();
    if (!user || !(await verifyPassword(user.password_hash, body.password)))
      throw createError({
        statusCode: 401,
        statusMessage: "Email or password is incorrect.",
      });
    const config = useRuntimeConfig(event);
    await replaceUserSession(
      event,
      { user: { id: user.id }, loggedInAt: new Date().toISOString() },
      {
        cookie: {
          secure:
            config.sessionSecure !== false &&
            String(config.sessionSecure) !== "false",
        },
        maxAge: 7200,
      },
    );
    return { id: user.id };
  }),
);
