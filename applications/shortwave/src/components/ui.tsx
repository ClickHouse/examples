import { Button } from "@clickhouse/click-ui";
import "./ui.css";
import { useEffect, useRef, useState, type ReactNode, type RefObject } from "react";
import {
  ArrowUpRight,
  Check,
  Copy,
  LoaderCircle,
  Radio,
  X,
} from "lucide-react";

export function Brand() {
  return (
    <a className="brand" href="/" aria-label="Shortwave home">
      <span className="brand-mark">
        <Radio size={25} strokeWidth={2.5} />
      </span>
      shortwave<span className="brand-dot">.</span>
    </a>
  );
}
export function PrimaryButton({
  children,
  className = "",
  ...props
}: React.ComponentProps<typeof Button>) {
  return (
    <Button {...props} className={`primary-button ${className}`}>
      <span className="primary-button-content">{children}</span>
    </Button>
  );
}
export function Loading() {
  return (
    <div className="loading" role="status">
      <LoaderCircle className="spin" size={22} /> Loading…
    </div>
  );
}
export function ErrorNotice({ message }: { message: string }) {
  return (
    <div className="error-notice" role="alert">
      {message}
    </div>
  );
}
export function message(error: unknown) {
  return error instanceof Error
    ? error.message
    : "Something went wrong. Please try again.";
}
export function CopyButton({ value }: { value: string }) {
  const [copied, setCopied] = useState(false);
  const [error, setError] = useState(false);
  useEffect(() => {
    if (copied) {
      const timer = setTimeout(() => setCopied(false), 2000);
      return () => clearTimeout(timer);
    }
  }, [copied]);
  return (
    <button
      className="icon-button"
      title={
        error
          ? "Could not copy. Select and copy the link."
          : copied
            ? "Copied!"
            : "Copy link"
      }
      aria-label={copied ? "Link copied" : "Copy link"}
      onClick={async () => {
        try {
          await navigator.clipboard.writeText(value);
          setCopied(true);
          setError(false);
        } catch {
          setError(true);
        }
      }}
    >
      {copied ? <Check size={17} /> : <Copy size={17} />}
      {error && <span className="copy-error">Copy failed</span>}
    </button>
  );
}
export function Modal({
  title,
  children,
  onClose,
  wide = false,
  initialFocus,
}: {
  title: string;
  children: ReactNode;
  onClose: () => void;
  wide?: boolean;
  initialFocus?: RefObject<HTMLElement | null>;
}) {
  const dialogRef = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    const previous = document.activeElement as HTMLElement | null;
    const dialog = dialogRef.current;
    const target = initialFocus?.current || dialog?.querySelector<HTMLElement>("input, button, select");
    target?.focus();
    const key = (event: KeyboardEvent) => {
      // Let nested controls consume Escape (for example, a tag suggestion list).
      if (event.defaultPrevented) return;
      if (event.key === "Escape") onClose();
      if (event.key === "Tab" && dialog) {
        const items = [
          ...dialog.querySelectorAll<HTMLElement>(
            "button, input, select, textarea, a[href]",
          ),
        ].filter((el) => !el.matches(":disabled") && el.tabIndex >= 0 && el.getClientRects().length > 0);
        const first = items[0];
        const last = items[items.length - 1];
        if (event.shiftKey && document.activeElement === first) {
          event.preventDefault();
          last?.focus();
        } else if (!event.shiftKey && document.activeElement === last) {
          event.preventDefault();
          first?.focus();
        }
      }
    };
    document.addEventListener("keydown", key);
    const overflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      document.removeEventListener("keydown", key);
      document.body.style.overflow = overflow;
      previous?.focus();
    };
  }, [onClose, initialFocus]);
  return (
    <div
      className="modal-backdrop"
      onMouseDown={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
    >
      <dialog
        ref={dialogRef}
        open
        aria-modal="true"
        aria-labelledby="dialog-title"
        className={`modal ${wide ? "modal-wide" : ""}`}
      >
        <div className="modal-heading">
          <h2 id="dialog-title">{title}</h2>
          <button
            className="icon-button"
            aria-label="Close dialog"
            onClick={onClose}
          >
            <X size={20} />
          </button>
        </div>
        {children}
      </dialog>
    </div>
  );
}
export function EmptyState({
  title,
  children,
  icon,
}: {
  title: string;
  children: ReactNode;
  icon: ReactNode;
}) {
  return (
    <div className="empty-state">
      <div className="empty-icon">{icon}</div>
      <h2>{title}</h2>
      <div className="muted">{children}</div>
    </div>
  );
}
export function SectionHeading({
  title,
  children,
  action,
}: {
  title: string;
  children?: ReactNode;
  action?: ReactNode;
}) {
  return (
    <header className="section-heading">
      <div>
        <h1>{title}</h1>
        {children && <p>{children}</p>}
      </div>
      {action}
    </header>
  );
}
export function shortUrl(slug: string, domainHostname?: string | null) {
  const origin = domainHostname ? `https://${domainHostname}` : typeof window !== "undefined" ? window.location.origin : "";
  return `${origin}/r/${slug}`;
}
export function ExternalLink({
  href,
  children,
}: {
  href: string;
  children: ReactNode;
}) {
  return (
    <a href={href} target="_blank" rel="noreferrer" className="external-link">
      {children}
      <ArrowUpRight size={14} />
    </a>
  );
}
