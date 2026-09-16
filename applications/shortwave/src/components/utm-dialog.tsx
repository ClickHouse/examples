import { useEffect, useLayoutEffect, useRef, useState, type RefObject } from "react";
import { Check, ChevronDown, X } from "lucide-react";
import { mergeUtm, utmKeys, utmSchema } from "../lib/domain";
import type { UtmTemplate, UtmValues } from "../lib/types";
import { fetchTemplates, saveTemplate } from "../routes/-api";
import { ErrorNotice, message } from "./ui";
import "./utm-editor.css";

function editableValues(destination: string, value: UtmValues): UtmValues {
  try { return { ...mergeUtm(destination, value).utm, ...value }; }
  catch { return { ...value }; }
}

export function UtmFields({ value, onChange }: { value: UtmValues; onChange: (value: UtmValues) => void }) {
  return <div className="form-grid">
    {utmKeys.map((key) => <label className="field" key={key}>
      <span>{key.charAt(0).toUpperCase() + key.slice(1)} <small>utm_{key}</small></span>
      <input value={value[key] || ""} onChange={(event) => onChange({ ...value, [key]: event.target.value })}
        maxLength={200} placeholder={{ source: "e.g. newsletter", medium: "e.g. email", campaign: "e.g. summer-launch", term: "Optional keyword", content: "Optional variation" }[key]} />
    </label>)}
  </div>;
}

export function UtmDialog({ id, value, destination, onSave, onClose, onBusyChange, returnFocus }: {
  id: string;
  value: UtmValues;
  destination: string;
  onSave: (value: UtmValues) => void;
  onClose: () => void;
  onBusyChange: (busy: boolean) => void;
  returnFocus: RefObject<HTMLButtonElement | null>;
}) {
  // This component mounts for each editing session. Only Save commits its copy.
  const [draft, setDraft] = useState<UtmValues>(() => editableValues(destination, value));
  const [templates, setTemplates] = useState<UtmTemplate[]>([]);
  const [selectedTemplate, setSelectedTemplate] = useState("");
  const [templateName, setTemplateName] = useState("");
  const [menuOpen, setMenuOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const pending = useRef(false);
  const [error, setError] = useState("");
  const [templateError, setTemplateError] = useState("");
  const [loadingTemplates, setLoadingTemplates] = useState(true);
  const dialog = useRef<HTMLDialogElement>(null);
  const menu = useRef<HTMLDivElement>(null);
  const menuTrigger = useRef<HTMLButtonElement>(null);
  const nameInput = useRef<HTMLInputElement>(null);
  const backdropPointer = useRef(false);
  let preview = "";
  try { preview = mergeUtm(destination, draft).resolvedUrl; } catch { /* An incomplete destination does not prevent composing UTMs. */ }

  useLayoutEffect(() => {
    const element = dialog.current!;
    const trigger = returnFocus.current;
    element.showModal();
    element.querySelector<HTMLInputElement>(".utm-parameter-rows input")?.focus({ preventScroll: true });
    return () => {
      if (element.open) element.close();
      trigger?.focus({ preventScroll: true });
    };
  }, []);

  useEffect(() => {
    let active = true;
    fetchTemplates().then((items) => { if (active) setTemplates((current) => [...items, ...current.filter((saved) => !items.some((item) => item.id === saved.id))]); })
      .catch(() => { if (active) setTemplateError("Saved templates could not be loaded."); })
      .finally(() => { if (active) setLoadingTemplates(false); });
    return () => { active = false; };
  }, []);

  useLayoutEffect(() => {
    if (!menuOpen || !menu.current || !menuTrigger.current) return;
    const element = menu.current;
    const trigger = menuTrigger.current;
    const viewport = window.visualViewport;
    const position = () => {
      const rect = trigger.getBoundingClientRect();
      const top = (viewport?.offsetTop ?? 0) + 8;
      const left = (viewport?.offsetLeft ?? 0) + 8;
      const bottom = (viewport?.offsetTop ?? 0) + (viewport?.height ?? window.innerHeight) - 8;
      const right = (viewport?.offsetLeft ?? 0) + (viewport?.width ?? window.innerWidth) - 8;
      const above = Math.max(0, rect.top - top - 6);
      const below = Math.max(0, bottom - rect.bottom - 6);
      // Prefer above the footer so its Save and Cancel actions stay exposed.
      const useAbove = above >= 200 || above > below;
      const height = Math.min(320, useAbove ? above : below);
      const width = Math.min(300, right - left);
      element.style.width = `${width}px`;
      element.style.maxHeight = `${height}px`;
      element.style.left = `${Math.max(left, Math.min(rect.left, right - width))}px`;
      element.style.top = useAbove ? "auto" : `${rect.bottom + 6}px`;
      element.style.bottom = useAbove ? `${window.innerHeight - rect.top + 6}px` : "auto";
      if (!pending.current && (rect.top < top || rect.bottom > bottom)) setMenuOpen(false);
    };
    const outside = (event: MouseEvent) => {
      if (!pending.current && !element.contains(event.target as Node) && !trigger.contains(event.target as Node)) setMenuOpen(false);
    };
    position();
    element.showPopover();
    (element.querySelector<HTMLButtonElement>(".utm-saved-templates button") ?? nameInput.current)?.focus({ preventScroll: true });
    const observer = new ResizeObserver(position);
    observer.observe(trigger);
    window.addEventListener("resize", position);
    document.addEventListener("scroll", position, true);
    document.addEventListener("click", outside, true);
    viewport?.addEventListener("resize", position);
    viewport?.addEventListener("scroll", position);
    return () => {
      observer.disconnect();
      window.removeEventListener("resize", position);
      document.removeEventListener("scroll", position, true);
      document.removeEventListener("click", outside, true);
      viewport?.removeEventListener("resize", position);
      viewport?.removeEventListener("scroll", position);
      if (element.isConnected && element.matches(":popover-open")) element.hidePopover();
    };
  }, [menuOpen]);

  function closeMenu() {
    if (pending.current) return;
    setMenuOpen(false);
    menuTrigger.current?.focus({ preventScroll: true });
  }
  function cancel() {
    if (!pending.current) onClose();
  }
  function save() {
    if (pending.current) return;
    const result = utmSchema.safeParse(draft);
    if (!result.success) { setError("Use up to 200 characters per UTM field."); return; }
    onSave(result.data);
  }
  async function createTemplate() {
    if (pending.current || !templateName.trim()) return;
    const parsed = utmSchema.safeParse(draft);
    if (!parsed.success) { setTemplateError("Use up to 200 characters per UTM field."); return; }
    pending.current = true;
    setBusy(true); onBusyChange(true); setTemplateError("");
    try {
      const template = await saveTemplate({ data: { name: templateName.trim(), values: parsed.data } });
      setTemplates((items) => [...items.filter((item) => item.id !== template.id), template].sort((a, b) => a.name.localeCompare(b.name)));
      setSelectedTemplate(template.id); setTemplateName("");
    } catch (err) { setTemplateError(message(err)); }
    finally {
      pending.current = false; setBusy(false); onBusyChange(false);
      requestAnimationFrame(() => nameInput.current?.focus({ preventScroll: true }));
    }
  }

  return <dialog ref={dialog} id={id} aria-label="UTM parameters" aria-modal="true" className="utm-popup utm-editor"
    onCancel={(event) => { event.preventDefault(); if (menuOpen) closeMenu(); else cancel(); }}
    onMouseDown={(event) => event.stopPropagation()}
    onPointerDown={(event) => {
      const bounds = event.currentTarget.getBoundingClientRect();
      backdropPointer.current = event.target === event.currentTarget && (event.clientX < bounds.left || event.clientX > bounds.right || event.clientY < bounds.top || event.clientY > bounds.bottom);
    }}
    onClick={(event) => {
      event.stopPropagation();
      const bounds = event.currentTarget.getBoundingClientRect();
      const outside = event.clientX < bounds.left || event.clientX > bounds.right || event.clientY < bounds.top || event.clientY > bounds.bottom;
      if (backdropPointer.current && event.target === event.currentTarget && outside) cancel();
      backdropPointer.current = false;
    }}
    onKeyDown={(event) => {
      event.stopPropagation();
      if (event.defaultPrevented || event.nativeEvent.isComposing) return;
      if (event.key === "Escape") { event.preventDefault(); if (menuOpen) closeMenu(); else cancel(); }
      else if (event.key === "Tab") {
        const controls = [...event.currentTarget.querySelectorAll<HTMLElement>('button:not(:disabled), input:not(:disabled)')]
          .filter((item) => item.tabIndex >= 0 && item.getClientRects().length > 0);
        const first = controls[0]; const last = controls[controls.length - 1];
        if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last?.focus(); }
        else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first?.focus(); }
      } else if (event.key === "Enter" && (event.shiftKey || (event.target instanceof HTMLElement && event.target.tagName !== "BUTTON"))) event.preventDefault();
    }}>
    <div className="utm-popup-heading">
      <h3>UTM parameters</h3>
      <button type="button" className="icon-button" aria-label="Close UTMs" disabled={busy} onClick={cancel}><X size={17} /></button>
    </div>
    <fieldset className="utm-parameter-rows" aria-label="UTM parameters" disabled={busy}>
      <UtmFields value={draft} onChange={(next) => { setDraft(next); setSelectedTemplate(""); setError(""); }} />
    </fieldset>
    {error && <ErrorNotice message={error} />}
    <label className="utm-url-preview-field"><span>URL preview</span>
      <input className="utm-url-preview" aria-label="Destination URL preview" readOnly value={preview}
        placeholder={destination.trim() ? "Enter a valid destination URL to preview" : "Add a destination URL to preview"} />
    </label>
    <div className="utm-dialog-actions">
      <button type="button" ref={menuTrigger} className="button-secondary utm-templates-toggle" aria-expanded={menuOpen}
        aria-haspopup="dialog" aria-controls={menuOpen ? `${id}-templates` : undefined} disabled={busy}
        onClick={() => menuOpen ? closeMenu() : setMenuOpen(true)}>Templates <ChevronDown size={14} /></button>
      <div className="utm-dialog-save-actions">
        <button type="button" className="button-secondary" disabled={busy} onClick={cancel}>Cancel</button>
        <button type="button" className="button-primary" disabled={busy} onClick={save}>Save</button>
      </div>
    </div>
    {menuOpen && <div ref={menu} popover="manual" id={`${id}-templates`} className="utm-template-menu" role="dialog" aria-label="UTM templates"
      onKeyDown={(event) => {
        if (event.nativeEvent.isComposing) return;
        if (event.key === "Escape") { event.preventDefault(); event.stopPropagation(); closeMenu(); }
        if (event.key === "Enter" && event.target === nameInput.current) {
          event.preventDefault(); event.stopPropagation(); if (!event.shiftKey) void createTemplate();
        }
      }}>
      <div className="utm-saved-templates">
        {loadingTemplates && <p role="status">Loading templates…</p>}
        {templates.map((template) => <button key={template.id} type="button" disabled={busy}
          onClick={() => { setDraft(editableValues(destination, template.values)); setSelectedTemplate(template.id); setError(""); closeMenu(); }}>
          <span>{template.name}</span>{selectedTemplate === template.id && <Check size={15} aria-hidden="true" />}
        </button>)}
      </div>
      <div className="utm-template-create">
        <label className="field"><span>Template name</span><input ref={nameInput} value={templateName} maxLength={80} disabled={busy}
          onChange={(event) => setTemplateName(event.target.value)} placeholder="Template name" /></label>
        <button type="button" className="button-secondary" disabled={busy || !templateName.trim()} onClick={createTemplate}>{busy ? "Saving…" : "Save new template"}</button>
      </div>
      {templateError && <ErrorNotice message={templateError} />}
    </div>}
  </dialog>;
}
