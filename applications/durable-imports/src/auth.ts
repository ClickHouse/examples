import { createHash, timingSafeEqual } from "node:crypto";
import type { RequestHandler } from "express";
import { CASEY, MORGAN } from "./input.js";
export function accountTokens(): { id: string; digest: Buffer }[] {
  const casey = process.env.CASEY_TOKEN;
  const morgan = process.env.MORGAN_TOKEN;
  if (
    !casey ||
    !morgan ||
    casey === morgan ||
    ![casey, morgan].every((value) => /^[A-Za-z0-9_-]{32,128}$/.test(value))
  )
    throw new Error(
      "Set distinct, random CASEY_TOKEN and MORGAN_TOKEN (32–128 URL-safe characters)",
    );
  return [
    { id: CASEY, digest: hash(casey) },
    { id: MORGAN, digest: hash(morgan) },
  ];
}
function hash(value: string): Buffer {
  return createHash("sha256").update(value).digest();
}
export function authorize(tokens = accountTokens()): RequestHandler {
  return (req, res, next) => {
    const header = req.header("authorization");
    const token = header?.startsWith("Bearer ") ? header.slice(7) : "";
    const digest = hash(token.length <= 128 ? token : "");
    const account = tokens.find((candidate) =>
      timingSafeEqual(candidate.digest, digest),
    );
    if (!account) {
      res.status(401).json({ error: "unauthorized" });
      return;
    }
    res.locals.accountId = account.id;
    next();
  };
}
