import type { PrismaClient, Prisma } from "../generated/prisma/client";
import {
  BoardError,
  isMaintainer,
  parseContent,
  parseRequestId,
  parseStatus,
  type Cursor,
  type Status,
} from "./validation";

export type Actor = { userId: string; name: string };

function requireActor(actor: Actor | null): asserts actor is Actor {
  if (!actor?.userId) throw new BoardError("Sign in to continue.");
}

export async function createRequest(
  db: PrismaClient,
  actor: Actor | null,
  input: { title: unknown; description: unknown },
) {
  requireActor(actor);
  return db.featureRequest.create({
    data: {
      ...parseContent(input),
      authorId: actor.userId,
      authorName:
        Array.from(actor.name.trim()).slice(0, 80).join("") ||
        "Community member",
    },
  });
}

export async function editRequest(
  db: PrismaClient,
  actor: Actor | null,
  requestId: string,
  input: { title: unknown; description: unknown },
) {
  requireActor(actor);
  const result = await db.featureRequest.updateMany({
    // A single conditional write closes the gap between checking ownership and writing.
    where: { id: parseRequestId(requestId), authorId: actor.userId },
    data: parseContent(input),
  });
  if (!result.count)
    throw new BoardError("Request not found, or you do not own it.");
}

export async function deleteRequest(
  db: PrismaClient,
  actor: Actor | null,
  requestId: string,
) {
  requireActor(actor);
  const result = await db.featureRequest.deleteMany({
    where: { id: parseRequestId(requestId), authorId: actor.userId },
  });
  if (!result.count)
    throw new BoardError("Request not found, or you do not own it.");
  // PostgreSQL cascades the request's votes in the same statement.
}

export async function setVote(
  db: PrismaClient,
  actor: Actor | null,
  requestId: string,
  voted: boolean,
) {
  requireActor(actor);
  const id = parseRequestId(requestId);
  if (voted) {
    try {
      // INSERT ... ON CONFLICT DO NOTHING: concurrent/retried votes remain one row.
      await db.vote.createMany({
        data: [{ requestId: id, userId: actor.userId }],
        skipDuplicates: true,
      });
    } catch (error) {
      if (
        error &&
        typeof error === "object" &&
        "code" in error &&
        error.code === "P2003"
      ) {
        throw new BoardError(
          "This request has been deleted. Return to the board.",
        );
      }
      throw error;
    }
  } else {
    // A desired state is safe to retry. A toggle would undo an earlier attempt.
    await db.vote.deleteMany({
      where: { requestId: id, userId: actor.userId },
    });
  }
}

export async function changeStatus(
  db: PrismaClient,
  actor: Actor | null,
  requestId: string,
  status: unknown,
) {
  requireActor(actor);
  if (!isMaintainer(actor.userId))
    throw new BoardError("Only a board maintainer can change status.");
  const result = await db.featureRequest.updateMany({
    where: { id: parseRequestId(requestId) },
    data: { status: parseStatus(status) },
  });
  if (!result.count) throw new BoardError("This request could not be found.");
}

export function listRequests(
  db: PrismaClient,
  userId: string | null,
  status?: Status,
  cursor?: Cursor,
) {
  const where: Prisma.FeatureRequestWhereInput = { status };
  if (cursor)
    where.OR = [
      { createdAt: { lt: cursor.createdAt } },
      { createdAt: cursor.createdAt, id: { lt: cursor.id } },
    ];
  return db.featureRequest.findMany({
    where,
    take: 21,
    orderBy: [{ createdAt: "desc" }, { id: "desc" }],
    select: {
      id: true,
      title: true,
      description: true,
      authorName: true,
      status: true,
      createdAt: true,
      _count: { select: { votes: true } },
      votes: { where: { userId: userId ?? "" }, select: { requestId: true } },
    },
  });
}
