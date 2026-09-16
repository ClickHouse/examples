import { useCallback, useEffect, useId, useRef, useState, type FormEvent } from "react";
import { Link2, SlidersHorizontal } from "lucide-react";
import type { Link, UtmValues } from "../lib/types";
import { DestinationPreview } from "./destination-preview";
import { FolderPicker } from "./folder-picker";
import { UtmDialog } from "./utm-dialog";
export { UtmFields } from "./utm-dialog";
import { utmKeys, validateDestination } from "../lib/domain";
import { saveLink } from "../routes/-api";
import { ErrorNotice, message, Modal, PrimaryButton } from "./ui";
import { TagInput } from "./tag-input";
import { AppSelect } from "./app-select";
import { fetchDomains } from "../routes/-domains-api";
import type { CustomDomain } from "../lib/custom-domains";
import "./link-editor.css";
import "./utm-editor.css";

export function LinkEditor({
  link,
  onClose,
  onSaved,
}: {
  link?: Link;
  onClose: () => void;
  onSaved: (link: Link) => void;
}) {
  const [destination, setDestination] = useState(link?.destination || "");
  const [title, setTitle] = useState(link?.title || "");
  const [slug, setSlug] = useState(link?.slug || "");
  const [domainId, setDomainId] = useState(link?.domainId || "");
  const [domains, setDomains] = useState<CustomDomain[]>([]);
  const [domainsLoading, setDomainsLoading] = useState(!link);
  const [domainError, setDomainError] = useState("");
  useEffect(() => {
    if (link) return;
    let active = true;
    void fetchDomains().then((items) => {
      if (!active) return;
      const ready = items.filter((item) => item.routingReady);
      setDomains(ready);
      if (ready.length === 1) setDomainId(ready[0].id);
    }).catch(() => { if (active) setDomainError("Domains could not load. You can use the default domain or reopen this form to retry."); })
      .finally(() => { if (active) setDomainsLoading(false); });
    return () => { active = false; };
  }, [link]);
  const [tags, setTags] = useState<string[]>(link?.tags || []);
  const [folderId, setFolderId] = useState<string | null>(link?.folderId ?? null);
  const [folderBusy, setFolderBusy] = useState(false);
  const folderPending = useRef(false);
  const updateFolderBusy = useCallback((pending: boolean) => {
    folderPending.current = pending;
    setFolderBusy(pending);
  }, []);
  const [tagDraft, setTagDraft] = useState("");
  const [tagError, setTagError] = useState("");
  const tagInput = useRef<HTMLInputElement>(null);
  const utmId = useId();
  const [utm, setUtm] = useState<UtmValues>(link?.utm || {});
  const [utmExpanded, setUtmExpanded] = useState(false);
  const utmTrigger = useRef<HTMLButtonElement>(null);
  const submitButton = useRef<HTMLDivElement>(null);
  const [enabled, setEnabled] = useState(link?.enabled ?? true);
  const [templateBusy, setTemplateBusy] = useState(false);
  const templatePending = useRef(false);
  const updateTemplateBusy = useCallback((pending: boolean) => {
    templatePending.current = pending;
    setTemplateBusy(pending);
  }, []);
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const savePending = useRef(false);
  const closeEditor = useCallback(() => {
    if (!savePending.current && !folderPending.current && !templatePending.current) onClose();
  }, [onClose]);
  async function submit(event: FormEvent) {
    event.preventDefault();
    if (savePending.current || folderPending.current || domainsLoading) return;
    const nextTags = [...new Set([...tags, tagDraft.trim()].filter(Boolean))];
    if (nextTags.length > 12) {
      setUtmExpanded(false);
      setTagError("Use up to 12 tags per link.");
      tagInput.current?.focus();
      return;
    }
    setError("");
    savePending.current = true;
    setBusy(true);
    try {
      const result = await saveLink({
        data: {
          id: link?.id,
          input: {
            destination: validateDestination(destination),
            title,
            ...(link ? {} : { domainId: domainId || null }),
            ...(link ? {} : slug ? { slug } : {}),
            tags: nextTags,
            folderId,
            utm,
            enabled,
          },
        },
      });
      onSaved(result);
    } catch (err) {
      setError(message(err));
    } finally {
      savePending.current = false;
      setBusy(false);
    }
  }
  return (
    <Modal
      title={link ? "Edit link" : "Create a link"}
      onClose={closeEditor}
      wide
    >
      <form
        className="link-editor-form"
        onSubmit={submit}
        onInvalidCapture={() => setUtmExpanded(false)}
        onKeyDown={(event) => {
          if (event.key !== "Enter" || !event.shiftKey || event.ctrlKey || event.metaKey || event.altKey) return;
          if (event.defaultPrevented || event.nativeEvent.isComposing || event.nativeEvent.keyCode === 229) return;
          event.preventDefault();
          if (event.repeat || savePending.current || folderPending.current || utmExpanded) return;
          const button = submitButton.current?.querySelector<HTMLButtonElement>('button[type="submit"]');
          event.currentTarget.requestSubmit(button ?? undefined);
        }}
      >
        <div className="modal-body link-editor-layout">
          <div className="link-editor-fields">
            {error && <ErrorNotice message={error} />}
            <label className="field">
              <span>
                Destination URL <em>*</em>
              </span>
              <div className="input-icon">
                <Link2 size={18} />
                <input
                  autoFocus
                  type="text"
                  inputMode="url"
                  required
                  placeholder="example.com"
                  value={destination}
                  onChange={(event) => {
                    const input = event.currentTarget;
                    let validation = "";
                    if (input.value) {
                      try { validateDestination(input.value); }
                      catch (err) { validation = message(err); }
                    }
                    input.setCustomValidity(validation);
                    setDestination(input.value);
                  }}
                  onBlur={(event) => {
                    try {
                      const normalized = validateDestination(event.currentTarget.value);
                      event.currentTarget.setCustomValidity("");
                      setDestination(normalized);
                    } catch { /* Preserve invalid drafts until native form validation. */ }
                  }}
                  maxLength={4096}
                />
              </div>
            </label>
            {(domains.length > 0 || link?.domainId) && <div className="field">
              <span>Domain {link && <small>Permanent</small>}</span>
              <AppSelect aria-label="Short link domain" value={domainId} onValueChange={setDomainId}
                disabled={Boolean(link) || domainsLoading || busy}
                options={link ? [{ value: domainId, label: link.domainHostname || (typeof window !== "undefined" ? window.location.host : "Default domain") }]
                  : [{ value: "", label: domainsLoading ? "Loading domains…" : typeof window !== "undefined" ? window.location.host : "Default domain" }, ...domains.map((item) => ({ value: item.id, label: item.hostname }))]} />
              {domainError && <small role="status">{domainError}</small>}
            </div>}
            <div className="form-grid">
              <label className="field">
                <span>Link title</span>
                <input
                  placeholder="Give this link a name"
                  value={title}
                  onChange={(e) => setTitle(e.target.value)}
                  maxLength={160}
                />
              </label>
              <label className="field">
                <span>Short link ending {link && <small>Permanent</small>}</span>
                <div className="input-prefix">
                  <span>/r/</span>
                  <input
                    placeholder="Generated automatically"
                    value={slug}
                    disabled={!!link}
                    onChange={(e) => setSlug(e.target.value)}
                    pattern="[A-Za-z0-9][A-Za-z0-9_-]*"
                    minLength={3}
                    maxLength={48}
                  />
                </div>
              </label>
            </div>
            <TagInput
              tags={tags}
              onTagsChange={setTags}
              draft={tagDraft}
              onDraftChange={setTagDraft}
              error={tagError}
              onErrorChange={setTagError}
              inputRef={tagInput}
            />
            <FolderPicker value={folderId} onChange={setFolderId} onBusyChange={updateFolderBusy} disabled={busy || templateBusy} />
            {link && (
              <label className="checkbox-field">
                <input
                  type="checkbox"
                  checked={enabled}
                  onChange={(e) => setEnabled(e.target.checked)}
                />
                <span>
                  Link is active
                  <small>Disabled links stop redirecting immediately.</small>
                </span>
              </label>
            )}
          </div>
          <aside className="link-editor-preview" aria-label="Destination preview">
            <DestinationPreview destination={destination} />
          </aside>
        </div>
        <div className="modal-actions link-editor-actions">
          <button
            ref={utmTrigger}
            type="button"
            className="button-secondary utm-toggle"
            aria-expanded={utmExpanded}
            aria-controls={utmExpanded ? utmId : undefined}
            aria-haspopup="dialog"
            disabled={busy || templateBusy || folderBusy}
            onClick={() => setUtmExpanded(true)}
          >
            <SlidersHorizontal size={15} /> UTMs
            {utmKeys.some((key) => utm[key]) && <span className="utm-active-dot" aria-label="Parameters added" />}
          </button>
          <div className="link-editor-save-actions" ref={submitButton}>
            <button
              type="button"
              className="button-secondary"
              disabled={busy || templateBusy || folderBusy}
              onClick={closeEditor}
            >
              Cancel
            </button>
            <PrimaryButton htmlType="submit" disabled={busy || templateBusy || folderBusy || domainsLoading} aria-keyshortcuts="Shift+Enter" title="Submit link (Shift + Enter)">
              {busy ? "Saving…" : link ? "Save changes" : "Create link"}
              <kbd className="submit-shortcut" aria-hidden="true">⇧ ↵</kbd>
            </PrimaryButton>
          </div>
        </div>
      </form>
      {utmExpanded && <UtmDialog id={utmId} value={utm} destination={destination} returnFocus={utmTrigger}
        onBusyChange={updateTemplateBusy} onClose={() => setUtmExpanded(false)}
        onSave={(next) => { setUtm(next); setUtmExpanded(false); }} />}
    </Modal>
  );
}
