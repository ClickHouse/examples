import { implement } from "@orpc/server";
import { contract } from "../lib/contract";
import { getQuote, saveQuote } from "./quotes";
const api = implement(contract);
export const router = api.router({
  get: api.get.handler(({ input }) => getQuote(input.id)),
  save: api.save.handler(({ input }) => saveQuote(input)),
});
