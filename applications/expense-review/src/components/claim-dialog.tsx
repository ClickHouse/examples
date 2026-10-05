"use client";
import { useEffect, useRef, useState } from "react";
import { useFieldArray, useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { client } from "@/lib/client";
import {
  editInput,
  decideInput,
  type Detail,
  type Edit,
  type Decision,
} from "@/shared/schema";
import { money } from "./workbench";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
export default function ClaimDialog({
  id,
  onClose,
  onSaved,
}: {
  id: number | null;
  onClose: () => void;
  onSaved: () => void;
}) {
  const [detail, setDetail] = useState<Detail | null>(null),
    [busy, setBusy] = useState(false),
    [loading, setLoading] = useState(false),
    [error, setError] = useState(""),
    [message, setMessage] = useState(""),
    [conflict, setConflict] = useState(false);
  const request = useRef(0);
  const edit = useForm<Edit>({
      resolver: zodResolver(editInput),
      defaultValues: { memo: "", lines: [] },
    }),
    review = useForm<Decision>({
      resolver: zodResolver(decideInput),
      defaultValues: { decision: "approved", reason: "" },
    });
  const lines = useFieldArray({ control: edit.control, name: "lines" });
  function populate(saved: Detail) {
    setDetail(saved);
    edit.reset({
      id: saved.id,
      revision: saved.revision,
      memo: saved.memo,
      lines: saved.lines,
    });
    review.reset({
      id: saved.id,
      revision: saved.revision,
      decision: "approved",
      reason: "",
    });
    setConflict(false);
  }
  async function reload() {
    if (id === null) return;
    const token = ++request.current;
    setLoading(true);
    setError("");
    setMessage("");
    setDetail(null);
    try {
      const saved = await client.detail.query({ id });
      if (token === request.current) populate(saved);
    } catch {
      if (token === request.current)
        setError("This claim could not be loaded. Retry the saved revision.");
    } finally {
      if (token === request.current) setLoading(false);
    }
  }
  useEffect(() => {
    void reload();
    return () => {
      request.current++;
    };
  }, [id]);
  async function mutate(action: () => Promise<Detail>, success: string) {
    setBusy(true);
    setError("");
    setMessage("");
    try {
      populate(await action());
      setMessage(success);
      onSaved();
    } catch (e) {
      const failure = e as { data?: { code?: string }; message?: string };
      setConflict(failure.data?.code === "CONFLICT");
      setError(
        failure.message ??
          "The claim could not be saved. Reload before trying again.",
      );
    } finally {
      setBusy(false);
    }
  }
  const saveEdit = edit.handleSubmit((values) =>
    mutate(
      () => client.edit.mutate(values),
      "Claim amended. Review its new pending revision.",
    ),
  );
  const saveDecision = review.handleSubmit((values) =>
    mutate(
      () => client.decide.mutate(values),
      "Decision saved with the reviewed line snapshot.",
    ),
  );
  const disabled = busy || loading || conflict || !detail || detail.id !== id;
  return (
    <Dialog
      open={id !== null}
      onOpenChange={(open) => {
        if (!open && !busy) onClose();
      }}
    >
      <DialogContent className="review-dialog">
        <DialogHeader>
          <DialogTitle>Review claim #{id}</DialogTitle>
          <DialogDescription>
            Read the saved revision, amend expenses if needed, then record your
            decision.
          </DialogDescription>
        </DialogHeader>
        {loading && <p role="status">Loading the saved claim…</p>}
        {error && (
          <p role="alert" className="feedback error">
            {error}
          </p>
        )}
        {message && (
          <p role="status" className="feedback">
            {message}
          </p>
        )}
        {(conflict || (!detail && !loading)) && (
          <Button
            variant="outline"
            onClick={() => void reload()}
            disabled={busy}
          >
            Reload saved revision (discard draft)
          </Button>
        )}
        {detail?.id === id && detail && (
          <>
            <div className="claim-summary">
              <div>
                <strong>{detail.employee}</strong>
                <p>
                  {detail.category} · revision {detail.revision}
                </p>
              </div>
              <div>
                <Badge>{detail.status}</Badge>
                <strong>{money(detail.totalCents)}</strong>
              </div>
            </div>
            <form onSubmit={saveEdit} className="claim-form">
              <h2>Expense details</h2>
              <label htmlFor="memo">Claim description</label>
              <Textarea
                id="memo"
                disabled={disabled}
                {...edit.register("memo")}
              />
              {edit.formState.errors.memo && (
                <p className="error">{edit.formState.errors.memo.message}</p>
              )}
              {lines.fields.map((field, index) => (
                <div key={field.id} className="line-form">
                  <div>
                    <label htmlFor={`description-${index}`}>
                      Line {index + 1} description
                    </label>
                    <Input
                      id={`description-${index}`}
                      disabled={disabled}
                      {...edit.register(`lines.${index}.description`)}
                    />
                    <p className="error">
                      {
                        edit.formState.errors.lines?.[index]?.description
                          ?.message
                      }
                    </p>
                  </div>
                  <div>
                    <label htmlFor={`amount-${index}`}>Amount (pence)</label>
                    <Input
                      id={`amount-${index}`}
                      type="number"
                      step="1"
                      disabled={disabled}
                      {...edit.register(`lines.${index}.amountCents`, {
                        valueAsNumber: true,
                      })}
                    />
                    <p className="error">
                      {
                        edit.formState.errors.lines?.[index]?.amountCents
                          ?.message
                      }
                    </p>
                  </div>
                  <Button
                    type="button"
                    variant="ghost"
                    disabled={disabled || lines.fields.length === 1}
                    onClick={() => lines.remove(index)}
                    aria-label={`Remove line ${index + 1}`}
                  >
                    Remove
                  </Button>
                </div>
              ))}
              <div className="actions">
                <Button
                  type="button"
                  variant="outline"
                  disabled={disabled || lines.fields.length >= 8}
                  onClick={() =>
                    lines.append({ description: "", amountCents: 100 })
                  }
                >
                  Add expense line
                </Button>
                <Button
                  type="submit"
                  disabled={disabled || !edit.formState.isDirty}
                >
                  Save amendment
                </Button>
              </div>
              <p className="hint">
                Amending returns this claim to pending and advances its
                revision. Previous decisions keep their captured amounts.
              </p>
            </form>
            <form onSubmit={saveDecision} className="decision-form">
              <h2>Review this saved revision</h2>
              <fieldset
                disabled={
                  disabled ||
                  edit.formState.isDirty ||
                  detail.status !== "pending"
                }
              >
                <legend>Decision</legend>
                <label>
                  <input
                    type="radio"
                    value="approved"
                    {...review.register("decision")}
                  />{" "}
                  Approve
                </label>
                <label>
                  <input
                    type="radio"
                    value="rejected"
                    {...review.register("decision")}
                  />{" "}
                  Reject
                </label>
              </fieldset>
              <label htmlFor="reason">Review reason</label>
              <Textarea
                id="reason"
                disabled={
                  disabled ||
                  edit.formState.isDirty ||
                  detail.status !== "pending"
                }
                {...review.register("reason")}
              />
              {review.formState.errors.reason && (
                <p className="error">
                  {review.formState.errors.reason.message}
                </p>
              )}
              <Button
                type="submit"
                disabled={
                  disabled ||
                  edit.formState.isDirty ||
                  detail.status !== "pending"
                }
              >
                Record decision
              </Button>
              {edit.formState.isDirty && (
                <p className="hint">
                  Save your amendment before reviewing its new revision.
                </p>
              )}
            </form>
            <section className="history">
              <h2>Decision history</h2>
              {detail.history.length === 0 ? (
                <p>No decisions recorded.</p>
              ) : (
                detail.history.map((entry) => (
                  <article key={entry.id}>
                    <div>
                      <Badge variant="outline">{entry.decision}</Badge>
                      <strong>{money(entry.totalCents)}</strong>
                    </div>
                    <p>
                      Reviewed revision {entry.reviewedRevision} ·{" "}
                      {new Date(entry.decidedAt).toLocaleString("en-GB", {
                        timeZone: "Europe/London",
                      })}
                    </p>
                    <p>{entry.reason}</p>
                    <p>Claim description: {entry.memoSnapshot}</p>
                    <ul>
                      {entry.snapshot.map((line, index) => (
                        <li key={index}>
                          {line.description}: {money(line.amountCents)}
                        </li>
                      ))}
                    </ul>
                  </article>
                ))
              )}
            </section>
          </>
        )}
      </DialogContent>
    </Dialog>
  );
}
