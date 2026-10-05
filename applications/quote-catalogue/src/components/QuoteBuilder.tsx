import { useEffect, useMemo, useState, useRef } from "preact/hooks";
import { quoteClient } from "../lib/client";
import type { Product, Quote } from "../lib/contract";
const money = (minor: number) =>
  new Intl.NumberFormat("en-GB", { style: "currency", currency: "GBP" }).format(
    minor / 100,
  );
export default function QuoteBuilder({
  products,
  quoteId,
}: {
  products: Product[];
  quoteId: number;
}) {
  const [quote, setQuote] = useState<Quote | null>(null);
  const [selected, setSelected] = useState<Record<number, number>>({});
  const [days, setDays] = useState(1);
  const [dirty, setDirty] = useState(false);
  const [busy, setBusy] = useState(true);
  const [conflict, setConflict] = useState(false);
  const [message, setMessage] = useState("");
  const [failed, setFailed] = useState(false);
  const [category, setCategory] = useState("All equipment");
  const [reloadDialog, setReloadDialog] = useState(false);
  const dialog = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    if (reloadDialog) dialog.current?.showModal();
    else dialog.current?.close();
  }, [reloadDialog]);
  const client = useMemo(() => quoteClient(), []);
  const apply = (next: Quote) => {
    setQuote(next);
    setDays(next.days);
    setSelected(
      Object.fromEntries(next.lines.map((l) => [l.productId, l.quantity])),
    );
    setDirty(false);
    setConflict(false);
  };
  const load = async () => {
    setBusy(true);
    try {
      apply(await client.get({ id: quoteId }));
      setMessage("");
      setFailed(false);
    } catch {
      setMessage(
        "The quote could not be loaded. Check the database connection and try again.",
      );
      setFailed(true);
    } finally {
      setBusy(false);
    }
  };
  useEffect(() => {
    void load();
  }, []);
  const change = (id: number, quantity: number) => {
    setSelected((old) => {
      const next = { ...old };
      if (quantity === 0) delete next[id];
      else next[id] = quantity;
      return next;
    });
    setDirty(true);
    setMessage("");
  };
  const lines = products.filter((p) => selected[p.id]);
  const estimated = lines.reduce(
    (total, p) => total + p.rateMinor * selected[p.id] * days,
    0,
  );
  const shownRate = (p: Product) =>
    !dirty
      ? (quote?.lines.find((l) => l.productId === p.id)?.unitMinor ??
        p.rateMinor)
      : p.rateMinor;
  const disabled = busy || conflict || !quote;
  const save = async () => {
    if (disabled || !dirty || lines.length === 0) return;
    setBusy(true);
    try {
      const next = await client.save({
        id: quote!.id,
        revision: quote!.revision,
        days,
        lines: lines.map((p) => ({
          productId: p.id,
          quantity: selected[p.id],
        })),
      });
      apply(next);
      setMessage("Quote saved. Rates and total were calculated by the server.");
      setFailed(false);
    } catch (error) {
      const code = (error as { code?: string }).code;
      setConflict(code === "CONFLICT");
      setFailed(true);
      setMessage(
        code === "CONFLICT"
          ? "A newer quote was saved. Your edits remain here. Reload before editing again."
          : "The quote could not be saved. Your edits remain here.",
      );
    } finally {
      setBusy(false);
    }
  };
  return (
    <section class="workbench" aria-label="Equipment quote builder">
      <div class="catalogue">
        <div class="section-heading">
          <div>
            <p class="eyebrow">THE EQUIPMENT SHELF</p>
            <h2>Choose your kit</h2>
          </div>
          <select
            class="select select-bordered"
            aria-label="Filter equipment"
            value={category}
            onChange={(e) => setCategory(e.currentTarget.value)}
          >
            {["All equipment", "Camera", "Lighting", "Audio", "Support"].map(
              (c) => (
                <option key={c}>{c}</option>
              ),
            )}
          </select>
        </div>
        <div class="product-grid">
          {products
            .filter(
              (p) => category === "All equipment" || p.category === category,
            )
            .map((p) => (
              <article
                class="card bg-base-100 product-card"
                key={p.id}
                data-product={p.id}
              >
                <div
                  class={"equipment-visual visual-" + p.category.toLowerCase()}
                  aria-hidden="true"
                >
                  <span>{String(p.id).padStart(2, "0")}</span>
                  <strong>{p.category}</strong>
                </div>
                <div class="card-body">
                  <span class="badge badge-outline">{p.category}</span>
                  <h3 class="card-title">{p.name}</h3>
                  <p>{p.description}</p>
                  <div class="card-actions">
                    <span>
                      <strong>{money(p.rateMinor)}</strong> / day
                    </span>
                    <button
                      class={
                        "btn btn-sm " +
                        (selected[p.id] ? "btn-outline" : "btn-primary")
                      }
                      disabled={disabled || !!selected[p.id]}
                      onClick={() => change(p.id, 1)}
                      aria-label={"Add " + p.name}
                    >
                      {selected[p.id] ? "In your quote" : "Add to quote"}
                    </button>
                  </div>
                </div>
              </article>
            ))}
        </div>
      </div>
      <aside class="card bg-base-100 quote-card">
        <div class="card-body">
          <p class="eyebrow">YOUR PRODUCTION</p>
          <h2>{quote?.title ?? "Loading quote"}</h2>
          <div class="quote-meta">
            <span class="badge badge-ghost">
              {quote ? "Revision " + quote.revision : "Loading"}
            </span>
            <span
              class={"badge " + (dirty ? "badge-warning" : "badge-success")}
            >
              {dirty ? "Unsaved changes" : quote ? "Saved draft" : "Connecting"}
            </span>
          </div>
          <label class="field-label">
            Hire duration
            <select
              class="select select-bordered"
              aria-label="Hire days"
              disabled={disabled}
              value={days}
              onChange={(e) => {
                setDays(Number(e.currentTarget.value));
                setDirty(true);
                setMessage("");
              }}
            >
              {Array.from({ length: 14 }, (_, i) => (
                <option value={i + 1} key={i}>
                  {i + 1} {i === 0 ? "day" : "days"}
                </option>
              ))}
            </select>
          </label>
          {lines.length === 0 ? (
            <div class="empty-quote">
              <span aria-hidden="true">＋</span>
              <h3>Start with a camera, light or microphone.</h3>
              <p>Add equipment to build a reusable quote.</p>
            </div>
          ) : (
            <div class="quote-lines">
              {lines.map((p) => (
                <div class="quote-line" key={p.id}>
                  <div>
                    <h3>{p.name}</h3>
                    <p>{money(shownRate(p))} per day</p>
                  </div>
                  <div class="quantity-controls join">
                    <button
                      class="btn btn-sm join-item"
                      aria-label={"Decrease " + p.name}
                      disabled={disabled}
                      onClick={() => change(p.id, selected[p.id] - 1)}
                    >
                      −
                    </button>
                    <output aria-label={"Quantity " + p.name}>
                      {selected[p.id]}
                    </output>
                    <button
                      class="btn btn-sm join-item"
                      aria-label={"Increase " + p.name}
                      disabled={disabled || selected[p.id] >= 20}
                      onClick={() => change(p.id, selected[p.id] + 1)}
                    >
                      ＋
                    </button>
                  </div>
                </div>
              ))}
            </div>
          )}
          <div class="total-row">
            <span>{dirty ? "Estimated total" : "Saved total"}</span>
            <strong data-testid="total">
              {money(dirty ? estimated : (quote?.totalMinor ?? 0))}
            </strong>
          </div>
          <p class="price-note">
            GBP, integer pennies. Estimates use the loaded catalogue; each save
            uses current server rates. No taxes, discounts or booking are
            included.
          </p>
          {message && (
            <div
              class={"alert " + (failed ? "alert-error" : "alert-success")}
              role="status"
            >
              {message}
            </div>
          )}
          <button
            class="btn btn-primary save-btn"
            disabled={disabled || !dirty || lines.length === 0}
            onClick={() => void save()}
          >
            {busy ? "Working…" : "Save quote"}
          </button>
          <button
            class="btn btn-ghost"
            disabled={busy}
            onClick={() => {
              if (dirty) setReloadDialog(true);
              else void load();
            }}
          >
            Reload saved quote
          </button>
          <a class="link link-hover" href="/hire-guide">
            Read the equipment-hire guide
          </a>
        </div>
      </aside>
      <dialog
        ref={dialog}
        class="modal"
        aria-labelledby="reload-title"
        onCancel={() => setReloadDialog(false)}
        onClose={() => setReloadDialog(false)}
      >
        <div class="modal-box">
          <h2 id="reload-title">Discard unsaved edits?</h2>
          <p>
            Reloading brings back the saved quote and removes the edits shown
            here.
          </p>
          <div class="modal-action">
            <button class="btn" onClick={() => setReloadDialog(false)}>
              Keep editing
            </button>
            <button
              class="btn btn-primary"
              onClick={() => {
                setReloadDialog(false);
                void load();
              }}
            >
              Discard and reload
            </button>
          </div>
        </div>
      </dialog>
    </section>
  );
}
