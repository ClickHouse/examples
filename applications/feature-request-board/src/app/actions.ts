"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { getActor, getSubmissionActor } from "../lib/actor";
import { getDb } from "../lib/db";
import {
  createRequest,
  editRequest,
  deleteRequest,
  setVote,
  changeStatus,
} from "../lib/board";
import { BoardError } from "../lib/validation";

export type ActionState = { error?: string; success?: string };

function failure(error: unknown): ActionState {
  if (error instanceof BoardError) return { error: error.message };
  // Never return database URLs, SQL, auth metadata or stack traces to the browser.
  console.error(
    "Feature board operation failed",
    error instanceof Error ? error.name : "UnknownError",
  );
  return { error: "We could not save that change. Please try again." };
}
function refresh(id: string) {
  revalidatePath("/");
  revalidatePath(`/requests/${id}`);
}

export async function submitRequest(
  _previous: ActionState,
  form: FormData,
): Promise<ActionState> {
  let id: string;
  try {
    const actor = await getSubmissionActor();
    const request = await createRequest(getDb(), actor, {
      title: form.get("title"),
      description: form.get("description"),
    });
    id = request.id;
  } catch (error) {
    return failure(error);
  }
  refresh(id);
  redirect(`/requests/${id}`);
}

export async function saveRequest(
  id: string,
  _previous: ActionState,
  form: FormData,
): Promise<ActionState> {
  try {
    const actor = await getActor();
    await editRequest(getDb(), actor, id, {
      title: form.get("title"),
      description: form.get("description"),
    });
  } catch (error) {
    return failure(error);
  }
  refresh(id);
  return { success: "Your changes are saved." };
}

export async function removeRequest(
  id: string,
  _previous: ActionState,
  _form: FormData,
): Promise<ActionState> {
  try {
    const actor = await getActor();
    await deleteRequest(getDb(), actor, id);
  } catch (error) {
    return failure(error);
  }
  refresh(id);
  redirect("/");
}

export async function voteOnRequest(
  id: string,
  voted: boolean,
  _previous: ActionState,
  _form: FormData,
): Promise<ActionState> {
  try {
    const actor = await getActor();
    await setVote(getDb(), actor, id, voted);
  } catch (error) {
    return failure(error);
  }
  refresh(id);
  return { success: voted ? "Vote added." : "Vote removed." };
}

export async function updateStatus(
  id: string,
  _previous: ActionState,
  form: FormData,
): Promise<ActionState> {
  try {
    const actor = await getActor();
    await changeStatus(getDb(), actor, id, form.get("status"));
  } catch (error) {
    return failure(error);
  }
  refresh(id);
  return { success: "Status updated." };
}
