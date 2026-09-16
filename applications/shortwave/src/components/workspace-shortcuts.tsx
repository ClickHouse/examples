import { createContext, useCallback, useContext, useEffect, useRef, useState, type ReactNode } from "react";
import { Keyboard } from "lucide-react";
import { Modal } from "./ui";
import "./workspace-shortcuts.css";

type LinkShortcuts = {
  onCreate: () => void;
  onSearch: () => void;
};
const ShortcutContext = createContext<{
  register: (actions: LinkShortcuts) => () => void;
  showHelp: () => void;
} | null>(null);

export function useLinkShortcuts(onCreate: () => void, onSearch: () => void) {
  const context = useContext(ShortcutContext);
  const register = context?.register;
  useEffect(() => register?.({ onCreate, onSearch }), [register, onCreate, onSearch]);
}

export function WorkspaceShortcutProvider({ children }: { children: ReactNode }) {
  const [open, setOpen] = useState(false);
  const actions = useRef<LinkShortcuts | null>(null);
  const register = useCallback((next: LinkShortcuts) => {
    actions.current = next;
    return () => { if (actions.current === next) actions.current = null; };
  }, []);
  const showHelp = useCallback(() => setOpen(true), []);
  const close = useCallback(() => setOpen(false), []);
  useEffect(() => {
    const handle = (event: KeyboardEvent) => {
      const target = event.target;
      if (event.defaultPrevented || event.repeat || event.isComposing ||
        event.ctrlKey || event.metaKey || event.altKey ||
        document.querySelector('dialog[open], [role="dialog"], [role="menu"], [role="listbox"], [aria-modal="true"]') ||
        (target instanceof HTMLElement && (target.isContentEditable ||
          target.closest('input, textarea, select, [contenteditable]:not([contenteditable="false"]), [role="textbox"], [role="combobox"]')))) return;
      if (event.key.toLowerCase() === "c" && !event.shiftKey && actions.current) {
        event.preventDefault();
        actions.current.onCreate();
      } else if (event.key === "/" && !event.shiftKey && actions.current) {
        event.preventDefault();
        actions.current.onSearch();
      } else if (event.key === "?") {
        event.preventDefault();
        setOpen(true);
      }
    };
    document.addEventListener("keydown", handle);
    return () => document.removeEventListener("keydown", handle);
  }, []);
  return <ShortcutContext.Provider value={{ register, showHelp }}>
    {children}
    {open && <Modal title="Keyboard shortcuts" onClose={close}>
      <div className="modal-body shortcut-help">
        <dl>
          <div><dt>Create a link</dt><dd><kbd>C</kbd></dd></div>
          <div><dt>Search links</dt><dd><kbd>/</kbd></dd></div>
          <div><dt>Show shortcuts</dt><dd><kbd>?</kbd></dd></div>
          <div><dt>Save a link</dt><dd aria-label="Shift and Enter"><kbd>⇧</kbd> <kbd>↵</kbd></dd></div>
          <div><dt>Close popup or dialog</dt><dd><kbd>Esc</kbd></dd></div>
        </dl>
        <p className="muted small">Create and search work on the Links page. Create, search, and help shortcuts pause while typing or using a dialog.</p>
      </div>
    </Modal>}
  </ShortcutContext.Provider>;
}

export function WorkspaceShortcuts() {
  const context = useContext(ShortcutContext);
  return <button type="button" className="workspace-shortcuts-button" onClick={context?.showHelp}
    aria-label="Keyboard shortcuts" aria-keyshortcuts="Shift+/" title="Keyboard shortcuts (?)">
    <Keyboard size={18} /><span>Shortcuts</span><kbd aria-hidden="true">?</kbd>
  </button>;
}
