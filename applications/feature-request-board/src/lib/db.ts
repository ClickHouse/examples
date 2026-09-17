import "server-only";
import { PrismaPg } from "@prisma/adapter-pg";
import { PrismaClient } from "../generated/prisma/client";
import { databaseConfig } from "./database-config";

const globalForPrisma = globalThis as unknown as {
  featureBoardDb?: PrismaClient;
};

export function getDb(): PrismaClient {
  if (!globalForPrisma.featureBoardDb) {
    const adapter = new PrismaPg(databaseConfig(), { schema: "feature_board" });
    globalForPrisma.featureBoardDb = new PrismaClient({ adapter });
  }
  return globalForPrisma.featureBoardDb;
}
