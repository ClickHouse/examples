import { initTRPC } from "@trpc/server";
import { z } from "zod";
import {
  claimId,
  detail,
  list,
  editInput,
  decideInput,
} from "../shared/schema";
import { readList, readDetail, editClaim, decideClaim } from "./claims";
const t = initTRPC.create({
  errorFormatter({ shape, error }) {
    return error.code === "INTERNAL_SERVER_ERROR"
      ? {
          ...shape,
          message:
            "The saved claim could not be updated. Reload and try again.",
          data: { ...shape.data, stack: undefined },
        }
      : shape;
  },
});
export const appRouter = t.router({
  list: t.procedure.output(list).query(() => readList()),
  detail: t.procedure
    .input(z.object({ id: claimId }).strict())
    .output(detail)
    .query(({ input }) => readDetail(input.id)),
  edit: t.procedure
    .input(editInput)
    .output(detail)
    .mutation(({ input }) => editClaim(input)),
  decide: t.procedure
    .input(decideInput)
    .output(detail)
    .mutation(({ input }) => decideClaim(input)),
});
export type AppRouter = typeof appRouter;
