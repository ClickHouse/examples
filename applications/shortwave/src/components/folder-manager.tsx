import { useCallback, useEffect, useId, useLayoutEffect, useRef, useState } from "react";
import { Folder as FolderIcon, MoreHorizontal, Pencil, Plus, Trash2 } from "lucide-react";
import { Link } from "@tanstack/react-router";
import type { Folder } from "../lib/types";
import { removeFolder, saveFolder } from "../routes/-api";
import { ErrorNotice, Modal, PrimaryButton, message } from "./ui";
import "./folder-manager.css";

export function FolderManager({ folders, onChange }: {
  folders: Folder[];
  onChange: (folders: Folder[]) => void;
}) {
  const [name, setName] = useState("");
  const [busy, setBusy] = useState(false);
  const saving = useRef(false);
  const createInput = useRef<HTMLInputElement>(null);
  const renameInput = useRef<HTMLInputElement>(null);
  const returnFocus = useRef<HTMLButtonElement | null>(null);
  const pendingFocus = useRef<HTMLElement | null>(null);
  const [error, setError] = useState("");
  const [action, setAction] = useState<{ kind: "rename" | "delete"; folder: Folder } | null>(null);
  const [editName, setEditName] = useState("");
  useLayoutEffect(() => {
    if (!action && !busy && pendingFocus.current) {
      pendingFocus.current.focus();
      pendingFocus.current = null;
    }
  }, [action, busy]);
  const closeAction = useCallback(() => {
    if (saving.current) return;
    pendingFocus.current = returnFocus.current;
    setAction(null);
    setError("");
  }, []);

  async function act(operation: () => Promise<void>) {
    if (saving.current) return;
    saving.current = true; setBusy(true); setError("");
    try { await operation(); } catch (err) { setError(message(err)); }
    finally { saving.current = false; setBusy(false); }
  }

  return <div className="folder-workspace">
    {error && !action && <ErrorNotice message={error} />}
    <form className="folder-create-form" onSubmit={(event) => {
      event.preventDefault();
      void act(async () => {
        const folder = await saveFolder({ data: { name } });
        onChange([...folders, folder]); setName("");
      });
    }}>
      <label className="field"><span>New folder</span><input ref={createInput} required maxLength={80} value={name} disabled={busy} onChange={(event) => setName(event.target.value)} /></label>
      <PrimaryButton htmlType="submit" disabled={busy || !name.trim()}><Plus size={16} />Create folder</PrimaryButton>
    </form>
    {!folders.length && <p className="muted">No folders yet.</p>}
    <div className="folder-grid">
      {folders.map((folder) => <FolderTile key={folder.id} folder={folder} disabled={busy} onAction={(kind, trigger) => {
        returnFocus.current = trigger;
        setEditName(folder.name);
        setError("");
        setAction({ kind, folder });
      }} />)}
    </div>
    {action && <Modal title={action.kind === "rename" ? "Rename folder" : "Delete folder?"} onClose={closeAction} initialFocus={action.kind === "rename" ? renameInput : undefined}>
      <form onSubmit={(event) => {
        event.preventDefault();
        void act(async () => {
          if (action.kind === "rename") {
            const saved = await saveFolder({ data: { id: action.folder.id, name: editName } });
            onChange(folders.map((item) => item.id === saved.id ? saved : item));
            pendingFocus.current = returnFocus.current;
          } else {
            await removeFolder({ data: action.folder.id });
            onChange(folders.filter((item) => item.id !== action.folder.id));
            pendingFocus.current = createInput.current;
          }
          setAction(null);
        });
      }}>
        <div className="modal-body">
          {error && <ErrorNotice message={error} />}
          {action.kind === "rename" ? <label className="field"><span>Folder name</span><input ref={renameInput} required maxLength={80} value={editName} disabled={busy} onFocus={(event) => event.currentTarget.select()} onChange={(event) => setEditName(event.target.value)} /></label> : <>
            <p className="folder-delete-name">“{action.folder.name}”</p>
            <p>Links will move to No folder.</p>
          </>}
        </div>
        <div className="modal-actions">
          <button type="button" className="button-secondary" disabled={busy} onClick={closeAction}>Cancel</button>
          <PrimaryButton htmlType="submit" type={action.kind === "delete" ? "danger" : undefined} disabled={busy || (action.kind === "rename" && !editName.trim())}>
            {action.kind === "rename" ? "Save name" : "Delete folder"}
          </PrimaryButton>
        </div>
      </form>
    </Modal>}
  </div>;
}

function FolderTile({ folder, disabled, onAction }: {
  folder: Folder;
  disabled: boolean;
  onAction: (kind: "rename" | "delete", trigger: HTMLButtonElement) => void;
}) {
  const [open, setOpen] = useState(false);
  const [above, setAbove] = useState(false);
  const trigger = useRef<HTMLButtonElement>(null);
  const lastItemOnOpen = useRef(false);
  const menu = useRef<HTMLDivElement>(null);
  const anchor = useRef<HTMLDivElement>(null);
  const menuId = useId();
  useLayoutEffect(() => {
    if (!open) return;
    const place = () => {
      const bounds = anchor.current?.getBoundingClientRect();
      if (bounds && menu.current) setAbove(bounds.bottom + menu.current.offsetHeight + 16 > window.innerHeight);
    };
    place();
    window.addEventListener("resize", place);
    window.addEventListener("scroll", place, true);
    return () => {
      window.removeEventListener("resize", place);
      window.removeEventListener("scroll", place, true);
    };
  }, [open]);
  useEffect(() => {
    if (!open) return;
    const items = menu.current?.querySelectorAll<HTMLButtonElement>("button");
    items?.[lastItemOnOpen.current ? items.length - 1 : 0]?.focus();
    const dismiss = (event: PointerEvent | FocusEvent) => {
      if (!anchor.current?.contains(event.target as Node)) setOpen(false);
    };
    document.addEventListener("pointerdown", dismiss);
    document.addEventListener("focusin", dismiss);
    return () => {
      document.removeEventListener("pointerdown", dismiss);
      document.removeEventListener("focusin", dismiss);
    };
  }, [open]);

  return <article className="folder-tile" aria-label={folder.name}>
    <Link className="folder-tile-link" to="/links" search={{ folderId: folder.id }} aria-disabled={disabled || undefined} tabIndex={disabled ? -1 : undefined} onClick={(event) => { if (disabled) event.preventDefault(); }}>
      <FolderIcon className="folder-tile-icon" size={76} strokeWidth={1.3} aria-hidden="true" />
      <h2>{folder.name}</h2>
    </Link>
    <div className="folder-tile-actions" ref={anchor}>
      <button ref={trigger} type="button" className="icon-button" aria-label={`Actions for ${folder.name}`} aria-haspopup="menu" aria-expanded={open} aria-controls={open ? menuId : undefined} disabled={disabled} onClick={() => { lastItemOnOpen.current = false; setOpen(!open); }} onKeyDown={(event) => {
        if (event.key === "ArrowDown" || event.key === "ArrowUp") { event.preventDefault(); lastItemOnOpen.current = event.key === "ArrowUp"; setOpen(true); }
      }}><MoreHorizontal size={19} /></button>
      {open && <div ref={menu} id={menuId} className={`folder-action-menu${above ? " folder-action-menu-above" : ""}`} role="menu" aria-label={`Actions for ${folder.name}`} onKeyDown={(event) => {
        const items = Array.from(menu.current?.querySelectorAll<HTMLButtonElement>("button") ?? []);
        const index = items.indexOf(document.activeElement as HTMLButtonElement);
        if (event.key === "Escape") { event.preventDefault(); event.stopPropagation(); setOpen(false); trigger.current?.focus(); }
        else if (["ArrowDown", "ArrowUp", "Home", "End"].includes(event.key)) {
          event.preventDefault();
          const next = event.key === "Home" ? 0 : event.key === "End" ? items.length - 1 : (index + (event.key === "ArrowDown" ? 1 : -1) + items.length) % items.length;
          items[next]?.focus();
        } else if (event.key === "Tab") {
          setOpen(false);
          trigger.current?.focus();
        }
      }}>
        <button type="button" role="menuitem" onClick={() => { setOpen(false); trigger.current?.focus(); onAction("rename", trigger.current!); }}><Pencil size={15} />Rename</button>
        <button type="button" role="menuitem" onClick={() => { setOpen(false); trigger.current?.focus(); onAction("delete", trigger.current!); }}><Trash2 size={15} />Delete</button>
      </div>}
    </div>
  </article>;
}
