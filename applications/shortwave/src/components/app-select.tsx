import { useEffect, useId, useLayoutEffect, useRef, useState, type ReactNode } from "react";
import { Check, ChevronDown } from "lucide-react";
import "./app-select.css";

type Option = { value: string; label: string };
type Placement = { above: boolean; maxHeight: number; visible: boolean };

/** Select-only combobox. Focus remains on its trigger, including inside dialogs. */
export function AppSelect({
  value, onValueChange, options, id, disabled, className = "", name, icon,
  "aria-label": ariaLabel,
}: {
  value: string;
  onValueChange: (value: string) => void;
  options: Option[];
  id?: string;
  "aria-label"?: string;
  disabled?: boolean;
  className?: string;
  name?: string;
  icon?: ReactNode;
}) {
  const generatedId = useId();
  const triggerId = id || generatedId;
  const root = useRef<HTMLDivElement>(null);
  const trigger = useRef<HTMLButtonElement>(null);
  const list = useRef<HTMLUListElement>(null);
  const search = useRef({ value: "", at: 0 });
  const [open, setOpen] = useState(false);
  const [active, setActive] = useState(0);
  const [placement, setPlacement] = useState<Placement>({ above: false, maxHeight: 220, visible: false });
  const selected = options.findIndex((option) => option.value === value);
  const expanded = open && placement.visible && !disabled;

  function show(index = Math.max(0, selected)) {
    if (disabled || !options.length) return;
    search.current = { value: "", at: 0 };
    setActive(index);
    setOpen(true);
  }
  function choose(index: number) {
    if (options[index]) onValueChange(options[index].value);
    setOpen(false);
    trigger.current?.focus();
  }

  useEffect(() => {
    if (!open) return;
    const outside = (event: PointerEvent) => {
      if (!root.current?.contains(event.target as Node)) setOpen(false);
    };
    document.addEventListener("pointerdown", outside);
    return () => document.removeEventListener("pointerdown", outside);
  }, [open]);

  useLayoutEffect(() => {
    if (!open || !trigger.current) return;
    const target = trigger.current;
    const dialog = target.closest("dialog");
    const popup = target.closest<HTMLElement>(".utm-popup");
    const footer = dialog?.querySelector<HTMLElement>(".modal-actions");
    const heading = dialog?.querySelector<HTMLElement>(".modal-heading");
    const viewport = window.visualViewport;
    function position() {
      const rect = target.getBoundingClientRect();
      const bounds = dialog?.getBoundingClientRect();
      const popupBounds = popup?.getBoundingClientRect();
      const viewportTop = viewport?.offsetTop ?? 0;
      const viewportBottom = viewportTop + (viewport?.height ?? window.innerHeight);
      const top = Math.max(viewportTop, bounds?.top ?? 0, heading?.getBoundingClientRect().bottom ?? 0, popupBounds?.top ?? 0) + 8;
      const bottom = Math.min(viewportBottom, bounds?.bottom ?? Infinity, popupBounds?.bottom ?? Infinity,
        footer && !footer.contains(target) ? footer.getBoundingClientRect().top : Infinity) - 8;
      const below = Math.max(0, bottom - rect.bottom - 6);
      const above = Math.max(0, rect.top - top - 6);
      const desired = Math.min(220, options.length * 36 + 10);
      const placeAbove = below < desired && above > below;
      const maxHeight = Math.floor(Math.min(desired, placeAbove ? above : below));
      const visible = rect.top >= top && rect.bottom <= bottom && maxHeight >= 36;
      // Dismiss if scrolling hides the anchor; an invisible menu must not commit a choice.
      if (!visible) setOpen(false);
      setPlacement((current) => current.above === placeAbove && current.maxHeight === maxHeight && current.visible === visible
        ? current : { above: placeAbove, maxHeight, visible });
    }
    position();
    const observer = new ResizeObserver(position);
    observer.observe(target);
    if (dialog) observer.observe(dialog);
    if (popup) observer.observe(popup);
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
  }, [open, options.length]);

  useLayoutEffect(() => {
    const menu = list.current;
    const option = menu?.children[active] as HTMLElement | undefined;
    if (!expanded || !menu || !option) return;
    // Keep scrolling local to the menu, avoiding jumps in the enclosing dialog.
    if (option.offsetTop < menu.scrollTop) menu.scrollTop = option.offsetTop;
    else if (option.offsetTop + option.offsetHeight > menu.scrollTop + menu.clientHeight) {
      menu.scrollTop = option.offsetTop + option.offsetHeight - menu.clientHeight;
    }
  }, [active, expanded, placement.maxHeight]);

  return (
    <div className={`app-select ${className}`} ref={root}>
      {name && <input type="hidden" name={name} value={value} disabled={disabled} />}
      <button
        ref={trigger}
        id={triggerId}
        type="button"
        role="combobox"
        className="app-select-trigger"
        disabled={disabled || !options.length}
        aria-label={ariaLabel}
        aria-haspopup="listbox"
        aria-expanded={expanded}
        aria-controls={expanded ? `${triggerId}-listbox` : undefined}
        aria-activedescendant={expanded && options[active] ? `${triggerId}-option-${active}` : undefined}
        onClick={() => open ? setOpen(false) : show()}
        onBlur={() => setOpen(false)}
        onKeyDown={(event) => {
          if (event.nativeEvent.isComposing || event.ctrlKey || event.metaKey) return;
          if (event.key === "Escape" && open) {
            event.preventDefault();
            event.stopPropagation();
            setOpen(false);
          } else if (event.key === "Tab") {
            if (expanded) choose(active);
            setOpen(false);
          } else if (["ArrowDown", "ArrowUp", "Home", "End", "Enter", " "].includes(event.key)) {
            event.preventDefault();
            event.stopPropagation();
            if (event.key === "Enter" || event.key === " ") {
              if (expanded) choose(active);
              else show();
            } else if (event.key === "Home" || event.key === "End") {
              const index = event.key === "Home" ? 0 : options.length - 1;
              if (!open) show(index);
              else setActive(index);
            } else if (!open) show(selected < 0 && event.key === "ArrowUp" ? options.length - 1 : Math.max(0, selected));
            else setActive((index) => (index + (event.key === "ArrowDown" ? 1 : -1) + options.length) % options.length);
          } else if (event.key.length === 1 && !event.altKey) {
            event.preventDefault();
            event.stopPropagation();
            const now = Date.now();
            const previous = now - search.current.at < 700 ? search.current.value : "";
            const query = `${previous}${event.key.toLocaleLowerCase()}`;
            search.current = { value: query, at: now };
            const repeated = [...query].every((char) => char === query[0]);
            const prefix = repeated ? query[0]! : query;
            const start = open ? active : selected;
            const offset = previous && !repeated ? 0 : 1;
            for (let step = offset; step < options.length + offset; step++) {
              const index = (Math.max(0, start) + step) % options.length;
              if (options[index]!.label.toLocaleLowerCase().startsWith(prefix)) {
                if (open) setActive(index);
                else onValueChange(options[index]!.value);
                break;
              }
            }
          }
        }}
      >
        {icon && <span className="app-select-icon" aria-hidden="true">{icon}</span>}
        <span className="app-select-value">{options[selected]?.label || "Select"}</span>
        <ChevronDown size={15} aria-hidden="true" />
      </button>
      {open && !disabled && (
        <ul ref={list} id={`${triggerId}-listbox`} role="listbox"
          aria-label={ariaLabel} aria-labelledby={ariaLabel ? undefined : triggerId}
          className={`app-select-options${placement.above ? " app-select-options-above" : ""}`}
          hidden={!placement.visible} style={{ maxHeight: placement.maxHeight }}>
          {options.map((option, index) => (
            <li key={option.value} id={`${triggerId}-option-${index}`} role="option"
              aria-selected={option.value === value} data-active={active === index || undefined}
              onPointerMove={() => setActive(index)}
              onMouseDown={(event) => event.preventDefault()}
              onClick={(event) => { event.preventDefault(); event.stopPropagation(); choose(index); }}>
              <span>{option.label}</span>
              {option.value === value && <Check size={15} aria-hidden="true" />}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
