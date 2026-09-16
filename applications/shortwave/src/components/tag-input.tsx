import {
  useEffect,
  useId,
  useLayoutEffect,
  useRef,
  useState,
  type RefObject,
} from "react";
import { X } from "lucide-react";
import { fetchTags } from "../routes/-api";
import "./tag-input.css";

type Placement = { above: boolean; maxHeight: number; visible: boolean };

export function TagInput({
  tags,
  onTagsChange,
  draft,
  onDraftChange,
  error,
  onErrorChange,
  inputRef,
}: {
  tags: string[];
  onTagsChange: (tags: string[]) => void;
  draft: string;
  onDraftChange: (draft: string) => void;
  error: string;
  onErrorChange: (error: string) => void;
  inputRef: RefObject<HTMLInputElement | null>;
}) {
  const id = useId();
  const anchor = useRef<HTMLDivElement>(null);
  const list = useRef<HTMLUListElement>(null);
  const [suggestions, setSuggestions] = useState<string[]>([]);
  const [focused, setFocused] = useState(false);
  const [activeSuggestion, setActiveSuggestion] = useState(-1);
  const [placement, setPlacement] = useState<Placement>({ above: false, maxHeight: 170, visible: false });
  const hasSuggestions = focused && suggestions.length > 0;
  const open = hasSuggestions && placement.visible;

  useEffect(() => {
    let active = true;
    setSuggestions([]);
    setActiveSuggestion(-1);
    if (!focused) return;
    const timer = setTimeout(() => {
      fetchTags({ data: draft.trim() })
        .then((data) => {
          if (active) {
            setSuggestions(data.filter((tag) => !tags.includes(tag)));
            onErrorChange("");
          }
        })
        .catch(() => {
          if (active) onErrorChange("Saved tags could not be loaded. You can still add tags.");
        });
    }, 150);
    return () => {
      active = false;
      clearTimeout(timer);
    };
  }, [draft, tags, focused, onErrorChange]);

  useLayoutEffect(() => {
    if (!hasSuggestions || !anchor.current) return;
    const target = anchor.current;
    const dialog = target.closest("dialog");
    const footer = dialog?.querySelector<HTMLElement>(".modal-actions");
    const viewport = window.visualViewport;
    function position() {
      const rect = target.getBoundingClientRect();
      const bounds = dialog?.getBoundingClientRect();
      const viewportTop = viewport?.offsetTop ?? 0;
      const viewportBottom = viewportTop + (viewport?.height ?? window.innerHeight);
      const top = Math.max(viewportTop, bounds?.top ?? 0) + 8;
      const bottom = Math.min(viewportBottom, bounds?.bottom ?? window.innerHeight, footer?.getBoundingClientRect().top ?? Infinity) - 8;
      const below = Math.max(0, bottom - rect.bottom - 6);
      const above = Math.max(0, rect.top - top - 6);
      const desiredHeight = Math.min(170, suggestions.length * 36 + 12);
      const placeAbove = below < desiredHeight && above > below;
      const maxHeight = Math.floor(Math.min(170, placeAbove ? above : below));
      const visible = rect.top >= top && rect.bottom <= bottom && maxHeight >= 36;
      setPlacement((current) => current.above === placeAbove && current.maxHeight === maxHeight && current.visible === visible
        ? current : { above: placeAbove, maxHeight, visible });
    }
    position();
    const observer = new ResizeObserver(position);
    observer.observe(target);
    if (dialog) observer.observe(dialog);
    if (footer) observer.observe(footer);
    // Capture scrolling ancestors; the overlay itself never alters their layout.
    window.addEventListener("scroll", position, true);
    window.addEventListener("resize", position);
    viewport?.addEventListener("resize", position);
    viewport?.addEventListener("scroll", position);
    return () => {
      observer.disconnect();
      window.removeEventListener("scroll", position, true);
      window.removeEventListener("resize", position);
      viewport?.removeEventListener("resize", position);
      viewport?.removeEventListener("scroll", position);
    };
  }, [hasSuggestions, suggestions.length]);

  useLayoutEffect(() => {
    const menu = list.current;
    const option = menu?.children[activeSuggestion] as HTMLElement | undefined;
    if (!menu || !option || !open) return;
    // Scroll only the options, never the dialog or the page behind it.
    if (option.offsetTop < menu.scrollTop) menu.scrollTop = option.offsetTop;
    else if (option.offsetTop + option.offsetHeight > menu.scrollTop + menu.clientHeight) {
      menu.scrollTop = option.offsetTop + option.offsetHeight - menu.clientHeight;
    }
  }, [activeSuggestion, open, placement.maxHeight]);

  function commitTag(value: string) {
    const tag = value.trim();
    if (!tag) return;
    if (!tags.includes(tag) && tags.length >= 12) {
      onErrorChange("Use up to 12 tags per link.");
      return;
    }
    if (!tags.includes(tag)) onTagsChange([...tags, tag]);
    onDraftChange("");
    onErrorChange("");
    setActiveSuggestion(-1);
    inputRef.current?.focus();
  }

  return (
    <div className="field tag-field">
      <label htmlFor={id}>Tags</label>
      <div ref={anchor} className="tag-input-anchor">
        <div className="tag-input-shell">
          {tags.map((tag) => (
            <span className="tag-chip" key={tag}>
              <span>{tag}</span>
              <button
                type="button"
                aria-label={`Remove tag ${tag}`}
                onClick={() => {
                  onTagsChange(tags.filter((value) => value !== tag));
                  inputRef.current?.focus();
                }}
              ><X size={13} /></button>
            </span>
          ))}
          <input
            ref={inputRef}
            id={id}
            role="combobox"
            aria-autocomplete="list"
            aria-expanded={open}
            aria-controls={open ? `${id}-suggestions` : undefined}
            aria-activedescendant={open && activeSuggestion >= 0 ? `${id}-option-${activeSuggestion}` : undefined}
            aria-describedby={error ? `${id}-error` : undefined}
            placeholder="Add a tag"
            autoComplete="off"
            maxLength={40}
            value={draft}
            onChange={(event) => { onDraftChange(event.target.value); setFocused(true); setActiveSuggestion(-1); }}
            onFocus={() => setFocused(true)}
            onBlur={() => { setFocused(false); setActiveSuggestion(-1); }}
            onKeyDown={(event) => {
              if (event.nativeEvent.isComposing) return;
              if (event.key === "Enter") {
                event.preventDefault();
                commitTag((open ? suggestions[activeSuggestion] : undefined) ?? draft);
              } else if (event.key === "ArrowDown" || event.key === "ArrowUp") {
                event.preventDefault();
                setFocused(true);
                if (suggestions.length) {
                  const direction = event.key === "ArrowDown" ? 1 : -1;
                  setActiveSuggestion((index) => index < 0
                    ? direction > 0 ? 0 : suggestions.length - 1
                    : (index + direction + suggestions.length) % suggestions.length);
                }
              } else if (event.key === "Escape" && focused) {
                event.preventDefault();
                event.stopPropagation();
                setFocused(false);
                setActiveSuggestion(-1);
              } else if (event.key === "Backspace" && !draft && tags.length) {
                event.preventDefault();
                onDraftChange(tags[tags.length - 1]!);
                onTagsChange(tags.slice(0, -1));
              }
            }}
          />
        </div>
        {hasSuggestions && (
          <ul
            ref={list}
            id={`${id}-suggestions`}
            role="listbox"
            aria-label="Saved tags"
            className={`tag-suggestions${placement.above ? " tag-suggestions-above" : ""}`}
            hidden={!placement.visible}
            style={{ maxHeight: placement.maxHeight }}
          >
            {suggestions.map((tag, index) => (
              <li
                key={tag}
                id={`${id}-option-${index}`}
                role="option"
                aria-selected={activeSuggestion === index}
                onMouseDown={(event) => event.preventDefault()}
                onClick={() => commitTag(tag)}
              >{tag}</li>
            ))}
          </ul>
        )}
      </div>
      {error && <small id={`${id}-error`} role="status">{error}</small>}
    </div>
  );
}
