import { z } from "zod";
export const claimId = z.number().int().positive().max(2147483647);
export const revision = z.number().int().nonnegative().max(2147483646);
export const lineInput = z
  .object({
    description: z.string().trim().min(2).max(80),
    amountCents: z.number().int().min(1).max(10000000),
  })
  .strict();
export const editInput = z
  .object({
    id: claimId,
    revision,
    memo: z.string().trim().min(3).max(300),
    lines: z.array(lineInput).min(1).max(8),
  })
  .strict();
export const decideInput = z
  .object({
    id: claimId,
    revision,
    decision: z.enum(["approved", "rejected"]),
    reason: z.string().trim().min(8).max(300),
  })
  .strict();
export const summary = z.object({
  id: claimId,
  employee: z.string(),
  category: z.string(),
  submittedAt: z.string(),
  status: z.enum(["pending", "approved", "rejected"]),
  revision: z.number().int().nonnegative().max(2147483647),
  memo: z.string(),
  totalCents: z.number().int().nonnegative(),
});
export const detail = summary.extend({
  lines: z.array(lineInput),
  history: z.array(
    z.object({
      id: z.number().int(),
      reviewedRevision: revision,
      decision: z.enum(["approved", "rejected"]),
      reason: z.string(),
      memoSnapshot: z.string(),
      totalCents: z.number().int().nonnegative(),
      snapshot: z.array(lineInput),
      decidedAt: z.string(),
    }),
  ),
});
export const list = z.object({
  claims: z.array(summary),
  totalCount: z.number().int().nonnegative(),
});
export type Summary = z.infer<typeof summary>;
export type Detail = z.infer<typeof detail>;
export type Edit = z.infer<typeof editInput>;
export type Decision = z.infer<typeof decideInput>;
