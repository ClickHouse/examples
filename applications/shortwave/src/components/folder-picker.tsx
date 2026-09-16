import { useEffect, useId, useLayoutEffect, useRef, useState } from "react";
import { Check, ChevronDown, Folder, Plus } from "lucide-react";
import type { Folder as FolderValue } from "../lib/types";
import { fetchFolders, saveFolder } from "../routes/-api";
import { ErrorNotice, message } from "./ui";
import "./folders.css";

export function FolderPicker({ value, onChange, disabled = false, onBusyChange, onOpen }: {
  value: string | null;
  onChange: (id: string | null) => void;
  disabled?: boolean;
  onBusyChange?: (busy: boolean) => void;
  onOpen?: () => void;
}) {
  const [folders, setFolders] = useState<FolderValue[]>([]);
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState("");
  const [busy, setBusy] = useState(false);
  const creating = useRef(false);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const popup = useRef<HTMLDivElement>(null);
  const options = useRef<HTMLDivElement>(null);
  const pointerActive = useRef(false);
  const root = useRef<HTMLDivElement>(null);
  const trigger = useRef<HTMLButtonElement>(null);
  const input = useRef<HTMLInputElement>(null);
  const id = useId();
  function openPicker() {
    onOpen?.();
    setOpen(true);
  }
  useEffect(() => {
    let active = true;
    fetchFolders().then((rows) => { if (active) setFolders(rows); })
      .catch((err) => { if (active) setError(message(err)); })
      .finally(() => { if (active) setLoading(false); });
    return () => { active = false; };
  }, []);
  useLayoutEffect(() => {
    if (!open) return;
    const panel = popup.current;
    const button = trigger.current;
    if (!panel || !button) return;
    const viewport = window.visualViewport;
    const position = () => {
      const rect = button.getBoundingClientRect();
      const viewportTop = viewport?.offsetTop ?? 0;
      const viewportLeft = viewport?.offsetLeft ?? 0;
      const viewportBottom = viewportTop + (viewport?.height ?? window.innerHeight);
      const viewportRight = viewportLeft + (viewport?.width ?? window.innerWidth);
      const top = rect.bottom + 6;
      const width = Math.min(rect.width, viewportRight - viewportLeft - 16);
      // The top layer avoids both dialog clipping and scrollable overflow.
      // Stay below Folder, allowing the menu to overlap the footer if needed.
      const height = Math.max(0, Math.min(172, viewportBottom - top - 8));
      panel.style.top = `${top}px`;
      panel.style.left = `${Math.max(viewportLeft + 8, Math.min(rect.left, viewportRight - width - 8))}px`;
      panel.style.width = `${width}px`;
      panel.style.height = `${height}px`;
      if (!creating.current && (rect.top < viewportTop || rect.bottom > viewportBottom || height <= 0)) setOpen(false);
    };
    const pointerDown = () => { pointerActive.current = true; };
    const pointerUp = () => { pointerActive.current = false; };
    const dismiss = (event: MouseEvent) => {
      if (!creating.current && !root.current?.contains(event.target as Node)) setOpen(false);
    };
    position();
    panel.showPopover();
    input.current?.focus({ preventScroll: true });
    const observer = new ResizeObserver(position);
    observer.observe(button);
    const form = root.current?.closest(".link-editor-form");
    if (form) observer.observe(form);
    window.addEventListener("resize", position);
    document.addEventListener("scroll", position, true);
    viewport?.addEventListener("resize", position);
    viewport?.addEventListener("scroll", position);
    document.addEventListener("pointerdown", pointerDown, true);
    document.addEventListener("pointerup", pointerUp, true);
    document.addEventListener("pointercancel", pointerUp, true);
    document.addEventListener("click", dismiss, true);
    return () => {
      observer.disconnect();
      window.removeEventListener("resize", position);
      document.removeEventListener("scroll", position, true);
      viewport?.removeEventListener("resize", position);
      viewport?.removeEventListener("scroll", position);
      document.removeEventListener("pointerdown", pointerDown, true);
      document.removeEventListener("pointerup", pointerUp, true);
      document.removeEventListener("pointercancel", pointerUp, true);
      document.removeEventListener("click", dismiss, true);
      pointerActive.current = false;
      if (panel.isConnected && panel.matches(":popover-open")) panel.hidePopover();
    };
  }, [open]);
  useLayoutEffect(() => {
    if (error && options.current) options.current.scrollTop = 0;
  }, [error]);
  const select = (id: string | null) => { onChange(id); setOpen(false); setQuery(""); trigger.current?.focus({ preventScroll: true }); };
  const filtered = folders.filter((folder) => folder.name.toLowerCase().includes(query.trim().toLowerCase()));
  const canCreate = query.trim() && !folders.some((folder) => folder.name.toLowerCase() === query.trim().toLowerCase());
  return (
    <div className="field folder-picker" ref={root} onBlur={(event) => {
      if (!creating.current && !pointerActive.current && !event.currentTarget.contains(event.relatedTarget as Node)) setOpen(false);
    }} onKeyDown={(event) => {
      if (!open || event.nativeEvent.isComposing || event.keyCode === 229) return;
      if (event.key === "Escape") {
        event.preventDefault(); event.stopPropagation();
        if (!creating.current) { setOpen(false); trigger.current?.focus({ preventScroll: true }); }
      }
      // Folder search/creation must never submit the containing link form.
      if (event.key === "Enter") {
        event.stopPropagation();
        if (event.target === input.current || event.shiftKey) event.preventDefault();
      }
      if (event.key === "ArrowDown" || event.key === "ArrowUp") {
        event.preventDefault(); event.stopPropagation();
        const controls = [...root.current!.querySelectorAll<HTMLElement>(".folder-popup input, .folder-popup button:not(:disabled)")];
        const current = controls.indexOf(document.activeElement as HTMLElement);
        const nextIndex = current < 0
          ? event.key === "ArrowDown" ? 0 : controls.length - 1
          : (current + (event.key === "ArrowDown" ? 1 : -1) + controls.length) % controls.length;
        const next = controls[nextIndex];
        next?.focus({ preventScroll: true });
        const list = options.current;
        if (next && list?.contains(next)) {
          if (next.offsetTop < list.scrollTop) list.scrollTop = next.offsetTop;
          else if (next.offsetTop + next.offsetHeight > list.scrollTop + list.clientHeight) {
            list.scrollTop = next.offsetTop + next.offsetHeight - list.clientHeight;
          }
        }
      }
    }}>
      <span id={`${id}-label`}>Folder</span>
      <div className="folder-anchor">
      <button type="button" className="folder-trigger" ref={trigger} disabled={disabled || busy}
        aria-labelledby={`${id}-label ${id}-value`} aria-expanded={open} aria-controls={open ? id : undefined} aria-haspopup="dialog"
        onKeyDown={(event) => {
          if (!open && (event.key === "ArrowDown" || event.key === "ArrowUp")) {
            event.preventDefault(); event.stopPropagation(); openPicker();
          }
        }}
        onClick={() => open ? setOpen(false) : openPicker()}>
        <Folder size={16} /><span id={`${id}-value`}>{folders.find((folder) => folder.id === value)?.name ?? (value ? "Selected folder" : "No folder")}</span><ChevronDown size={15} />
      </button>
      {open && <div className="folder-popup" popover="manual" ref={popup} id={id} role="dialog" aria-label="Choose a folder">
        <input ref={input} aria-label="Search or create a folder" placeholder="Search or create a folder…" maxLength={80} value={query} disabled={disabled || busy}
          onChange={(event) => setQuery(event.target.value)} />
        <div className="folder-options" ref={options}>
        {error && <ErrorNotice message={error} />}
        {loading ? <p role="status">Loading folders…</p> : <>
          <button type="button" disabled={disabled || busy} onClick={() => select(null)}><Folder size={15} /><span>No folder</span>{value === null && <Check size={15} />}</button>
          {filtered.map((folder) => <button type="button" key={folder.id} disabled={disabled || busy} onClick={() => select(folder.id)}><Folder size={15} /><span>{folder.name}</span>{value === folder.id && <Check size={15} />}</button>)}
          {canCreate && <button type="button" disabled={busy || disabled} onClick={async () => {
            if (creating.current) return;
            creating.current = true; setBusy(true); onBusyChange?.(true); setError("");
            let saved = false;
            try {
              const folder = await saveFolder({ data: { name: query.trim() } });
              setFolders((items) => [...items, folder]); select(folder.id); saved = true;
            } catch (err) { setError(message(err)); } finally {
              creating.current = false; setBusy(false); onBusyChange?.(false);
              requestAnimationFrame(() => (saved ? trigger.current : input.current)?.focus({ preventScroll: true }));
            }
          }}><Plus size={15} /><span>{busy ? "Creating…" : `Create “${query.trim()}”`}</span></button>}
        </>}
        </div>
      </div>}
      </div>
    </div>
  );
}
