import "server-only";
import { auth, currentUser } from "@clerk/nextjs/server";
import { BoardError } from "./validation";
import type { Actor } from "./board";

export async function getActor(): Promise<Actor> {
  const { userId } = await auth();
  if (!userId) throw new BoardError("Sign in to continue.");
  return { userId, name: "Community member" };
}

export async function getSubmissionActor(): Promise<Actor> {
  const actor = await getActor();
  const user = await currentUser();
  // Publish a name snapshot, never an email address or authentication token.
  return {
    ...actor,
    name: user?.firstName || user?.username || "Community member",
  };
}
