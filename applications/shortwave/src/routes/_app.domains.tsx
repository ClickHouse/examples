import { createFileRoute } from "@tanstack/react-router";
import { useCallback, useEffect, useRef, useState } from "react";
import { Check, Copy, Globe, LoaderCircle, Plus, RefreshCw, Trash2 } from "lucide-react";
import type { CustomDomain } from "../lib/custom-domains";
import { addDomain, checkDomainDns, fetchDomains, removeDomain } from "./-domains-api";
import { EmptyState, ErrorNotice, Loading, Modal, PrimaryButton, SectionHeading, message } from "../components/ui";
import "../components/domains.css";

export const Route = createFileRoute("/_app/domains")({ component: DomainsPage });

function DomainsPage() {
  const [domains, setDomains] = useState<CustomDomain[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [adding, setAdding] = useState(false);
  const [deleting, setDeleting] = useState<CustomDomain | null>(null);
  const addTrigger = useRef<HTMLDivElement>(null);
  const load = useCallback(async () => {
    setLoading(true);
    setError("");
    try { setDomains(await fetchDomains()); }
    catch (err) { setError(message(err)); }
    finally { setLoading(false); }
  }, []);
  useEffect(() => { void load(); }, [load]);
  const closeAdd = useCallback(() => setAdding(false), []);
  const closeDelete = useCallback(() => setDeleting(null), []);
  return <>
    <SectionHeading title="Domains" action={<div ref={addTrigger}>
      <PrimaryButton disabled={loading || Boolean(error)} onClick={() => setAdding(true)}><Plus size={18} />Add domain</PrimaryButton>
    </div>} />
    {loading ? <Loading /> : error ? <>
      <ErrorNotice message={error} />
      <button className="button-secondary" onClick={() => void load()}>Try again</button>
    </> : <>
      {!domains.length ? <EmptyState title="No domains yet" icon={<Globe size={30} />}>{null}</EmptyState> :
        <div className="domain-list">{domains.map((domain) => <DomainCard key={domain.id} domain={domain}
          onChange={(saved) => setDomains((items) => items.map((item) => item.id === saved.id ? saved : item))}
          onRemove={() => setDeleting(domain)} />)}</div>}
    </>}
    {adding && <AddDomainDialog onClose={closeAdd} onSaved={(saved) => {
      setDomains((items) => [saved, ...items.filter((item) => item.id !== saved.id)]);
      setAdding(false);
    }} />}
    {deleting && <RemoveDomainDialog domain={deleting} onClose={closeDelete} onRemoved={() => {
      setDomains((items) => items.filter((item) => item.id !== deleting.id));
      setDeleting(null);
      requestAnimationFrame(() => addTrigger.current?.querySelector("button")?.focus());
    }} />}
  </>;
}

function DomainCard({ domain, onChange, onRemove }: {
  domain: CustomDomain;
  onChange: (domain: CustomDomain) => void;
  onRemove: () => void;
}) {
  const [busy, setBusy] = useState(false);
  const checking = useRef(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  async function check() {
    if (checking.current) return;
    checking.current = true; setBusy(true); setError(""); setNotice("");
    try {
      const saved = await checkDomainDns({ data: domain.id });
      onChange(saved);
      if (saved.status === "verified" && !saved.verificationError) setNotice("Ownership verified.");
    } catch (err) { setError(message(err)); }
    finally { checking.current = false; setBusy(false); }
  }
  return <article className="domain-card" aria-label={domain.hostname}>
    <header className="domain-card-heading">
      <Globe size={22} className="domain-icon" aria-hidden="true" />
      <h2>{domain.hostname}</h2>
      <span className={`domain-status${domain.status === "verified" ? " domain-status-verified" : ""}`}>
        {domain.status === "verified" && <Check size={14} aria-hidden="true" />}
        {domain.routingReady ? "Ready for links" : domain.status === "verified" ? "Ownership verified" : "Pending verification"}
      </span>
      <button className="icon-button domain-remove" aria-label={`Remove ${domain.hostname}`} disabled={busy} onClick={onRemove}><Trash2 size={17} /></button>
    </header>
    <div className="domain-dns">
      {domain.status === "verified" && !domain.routingReady && <p>Ownership verified. Hosting setup is required before creating links on this domain.</p>}
      <p>{domain.status === "verified" ? "Keep this TXT record in your DNS settings to allow ownership rechecks." : "Add this TXT record in your domain’s DNS settings, then check DNS."}</p>
      <table className="domain-dns-table">
        <caption className="domain-table-caption">Ownership verification record for {domain.hostname}</caption>
        <thead><tr><th scope="col">Type</th><th scope="col">Name</th><th scope="col">Value</th><th scope="col">TTL</th></tr></thead>
        <tbody><tr>
          <td data-label="Type">TXT</td>
          <td data-label="Name"><DnsValue label="record name" value={domain.verificationName} /></td>
          <td data-label="Value"><DnsValue label="record value" value={domain.verificationValue} /></td>
          <td data-label="TTL">Auto</td>
        </tr></tbody>
      </table>
      <p className="domain-dns-help">In Cloudflare, paste the full Name above. If your DNS provider appends the zone name, enter only the part before it.</p>
      {error && <ErrorNotice message={error} />}
      {domain.verificationError && <ErrorNotice message={domain.verificationError} />}
      <div className="domain-check-row">
        <button className="button-secondary" disabled={busy} onClick={() => void check()}>
          {busy ? <LoaderCircle size={15} className="spin" /> : <RefreshCw size={15} />}
          {busy ? "Checking DNS…" : domain.status === "verified" ? "Recheck DNS" : "Check DNS"}
        </button>
        {domain.lastCheckedAt && <span className="domain-last-checked">Last checked <time dateTime={domain.lastCheckedAt}>{new Date(domain.lastCheckedAt).toLocaleString()}</time></span>}
      </div>
      {notice && <p className="domain-check-success" role="status">{notice}</p>}
    </div>
  </article>;
}

function DnsValue({ label, value }: { label: string; value: string }) {
  const [feedback, setFeedback] = useState<"copied" | "error" | null>(null);
  useEffect(() => {
    if (feedback !== "copied") return;
    const timer = setTimeout(() => setFeedback(null), 2500);
    return () => clearTimeout(timer);
  }, [feedback]);
  return <div className="domain-dns-value">
    <div className="domain-dns-value-line"><code>{value}</code><button type="button" className="icon-button" aria-label={`Copy ${label}`} onClick={async () => {
      try { await navigator.clipboard.writeText(value); setFeedback("copied"); }
      catch { setFeedback("error"); }
    }}>{feedback === "copied" ? <Check size={15} /> : <Copy size={15} />}</button></div>
    {feedback && <span className={`domain-copy-feedback${feedback === "error" ? " domain-copy-error" : ""}`} role="status">{feedback === "copied" ? "Copied" : "Copy failed. Select the text and copy it."}</span>}
  </div>;
}

function AddDomainDialog({ onClose, onSaved }: { onClose: () => void; onSaved: (domain: CustomDomain) => void }) {
  const [hostname, setHostname] = useState("");
  const hostnameInput = useRef<HTMLInputElement>(null);
  // Run after Modal records the trigger and applies its initial focus.
  useEffect(() => { hostnameInput.current?.focus(); }, []);
  const [busy, setBusy] = useState(false);
  const saving = useRef(false);
  const [error, setError] = useState("");
  const close = useCallback(() => { if (!saving.current) onClose(); }, [onClose]);
  return <Modal title="Add domain" onClose={close}>
    <form onSubmit={async (event) => {
      event.preventDefault();
      if (saving.current) return;
      saving.current = true; setBusy(true); setError("");
      try { onSaved(await addDomain({ data: hostname })); }
      catch (err) { setError(message(err)); }
      finally { saving.current = false; setBusy(false); }
    }}>
      <div className="modal-body">
        {error && <ErrorNotice message={error} />}
        <label className="field"><span>Domain</span><input ref={hostnameInput} required maxLength={253} autoCapitalize="none" autoCorrect="off" spellCheck={false} placeholder="go.example.com" value={hostname} disabled={busy} onChange={(event) => setHostname(event.target.value)} aria-describedby="domain-input-help" /></label>
        <p id="domain-input-help" className="domain-input-help">Enter a domain or subdomain you own, without a protocol or path.</p>
      </div>
      <div className="modal-actions"><button type="button" className="button-secondary" disabled={busy} onClick={close}>Cancel</button>
        <PrimaryButton htmlType="submit" disabled={busy || !hostname.trim()}>{busy ? "Adding…" : "Add domain"}</PrimaryButton>
      </div>
    </form>
  </Modal>;
}

function RemoveDomainDialog({ domain, onClose, onRemoved }: { domain: CustomDomain; onClose: () => void; onRemoved: () => void }) {
  const [busy, setBusy] = useState(false);
  const saving = useRef(false);
  const [error, setError] = useState("");
  const close = useCallback(() => { if (!saving.current) onClose(); }, [onClose]);
  return <Modal title="Remove domain?" onClose={close}>
    <div className="modal-body domain-remove-body">
      {error && <ErrorNotice message={error} />}
      <p>Remove <strong>{domain.hostname}</strong> from your account?</p>
      <p>You can delete its verification TXT record from your DNS settings afterward. Adding the domain again requires a new record.</p>
    </div>
    <div className="modal-actions"><button className="button-secondary" disabled={busy} onClick={close}>Cancel</button>
      <PrimaryButton type="danger" disabled={busy} onClick={async () => {
        if (saving.current) return;
        saving.current = true; setBusy(true); setError("");
        try { await removeDomain({ data: domain.id }); onRemoved(); }
        catch (err) { setError(message(err)); }
        finally { saving.current = false; setBusy(false); }
      }}>{busy ? "Removing…" : "Remove domain"}</PrimaryButton>
    </div>
  </Modal>;
}
