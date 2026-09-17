"use client";

import { useActionState, useId, useState } from "react";
import Link from "next/link";
import {
  submitRequest,
  saveRequest,
  removeRequest,
  voteOnRequest,
  updateStatus,
  type ActionState,
} from "../app/actions";
import { statuses, statusLabels, type Status } from "../lib/validation";

function Feedback({ state, id }: { state: ActionState; id?: string }) {
  return (
    <div
      id={id}
      aria-live="polite"
      aria-atomic="true"
      className={`feedback ${state.error ? "feedback-error" : ""}`}
    >
      {state.error || state.success || ""}
    </div>
  );
}

export function RequestForm({
  request,
}: {
  request?: { id: string; title: string; description: string };
}) {
  const [state, action, pending] = useActionState(
    request ? saveRequest.bind(null, request.id) : submitRequest,
    {},
  );
  const id = useId();
  const [title, setTitle] = useState(request?.title ?? "");
  const [description, setDescription] = useState(request?.description ?? "");
  return (
    <form action={action} className="request-form">
      <label htmlFor={`${id}-title`}>A clear, short title</label>
      <input
        id={`${id}-title`}
        name="title"
        minLength={8}
        maxLength={120}
        required
        value={title}
        onChange={(event) => setTitle(event.target.value)}
        placeholder="What would make your day easier?"
        aria-describedby={`${id}-title-hint`}
      />
      <p id={`${id}-title-hint`} className="field-hint">
        8–120 characters
      </p>
      <label htmlFor={`${id}-description`}>Tell us a little more</label>
      <textarea
        id={`${id}-description`}
        name="description"
        minLength={20}
        maxLength={4000}
        required
        rows={5}
        value={description}
        onChange={(event) => setDescription(event.target.value)}
        placeholder="Describe the problem and how this would help."
        aria-describedby={`${id}-description-hint`}
      />
      <p id={`${id}-description-hint`} className="field-hint">
        20–4,000 characters. Your name and request will be public.
      </p>
      <Feedback state={state} />
      <button
        className="button button-primary"
        type="submit"
        disabled={pending}
      >
        {pending ? "Saving…" : request ? "Save changes" : "Submit request"}
        <span aria-hidden="true">↗</span>
      </button>
    </form>
  );
}

export function VoteButton({
  id,
  title,
  count,
  voted,
  signedIn,
}: {
  id: string;
  title: string;
  count: number;
  voted: boolean;
  signedIn: boolean;
}) {
  const [state, action, pending] = useActionState(
    voteOnRequest.bind(null, id, !voted),
    {},
  );
  const feedbackId = useId();
  if (!signedIn)
    return (
      <Link
        className="vote-button"
        href={`/sign-in?redirect_url=${encodeURIComponent(`/requests/${id}`)}`}
        aria-label={`Sign in to vote for ${title}; ${count} votes`}
      >
        <span aria-hidden="true">⌃</span>
        <strong>{count}</strong>
      </Link>
    );
  return (
    <form action={action} className="vote-form">
      <button
        className={`vote-button ${voted ? "is-voted" : ""}`}
        type="submit"
        disabled={pending}
        aria-pressed={voted}
        aria-label={`${voted ? "Remove vote from" : "Vote for"} ${title}; ${count} votes`}
        aria-describedby={feedbackId}
      >
        <span aria-hidden="true">⌃</span>
        <strong>{count}</strong>
      </button>
      <div
        id={feedbackId}
        aria-live="polite"
        className={state.error ? "vote-error" : "sr-only"}
      >
        {state.error || state.success}
      </div>
    </form>
  );
}

export function StatusForm({ id, status }: { id: string; status: Status }) {
  const [state, action, pending] = useActionState(
    updateStatus.bind(null, id),
    {},
  );
  return (
    <form action={action} className="status-form">
      <label htmlFor="request-status">Update status</label>
      <div className="inline-form">
        <select id="request-status" name="status" defaultValue={status}>
          {statuses.map((value) => (
            <option key={value} value={value}>
              {statusLabels[value]}
            </option>
          ))}
        </select>
        <button
          className="button button-secondary"
          type="submit"
          disabled={pending}
        >
          {pending ? "Saving…" : "Update"}
        </button>
      </div>
      <Feedback state={state} />
    </form>
  );
}

export function DeleteForm({ id }: { id: string }) {
  const [state, action, pending] = useActionState(
    removeRequest.bind(null, id),
    {},
  );
  return (
    <form
      action={action}
      onSubmit={(event) => {
        if (
          !window.confirm(
            "Delete this request and all its votes? This cannot be undone.",
          )
        )
          event.preventDefault();
      }}
    >
      <button type="submit" className="text-button danger" disabled={pending}>
        {pending ? "Deleting…" : "Delete request"}
      </button>
      <Feedback state={state} />
    </form>
  );
}
