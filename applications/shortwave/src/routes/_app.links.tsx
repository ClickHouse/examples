import { createFileRoute, Link as RouterLink } from "@tanstack/react-router";
import { useCallback, useEffect, useMemo, useState } from "react";
import {
  ArrowUpRight,
  Folder,
  Link2,
  Plus,
  QrCode,
  Search,
  Settings2,
  Tag,
  BarChart3,
} from "lucide-react";
import type { Link, Folder as FolderValue } from "../lib/types";
import { fetchLinks, fetchFolders } from "./-api";
import {
  CopyButton,
  EmptyState,
  ErrorNotice,
  Loading,
  message,
  PrimaryButton,
  SectionHeading,
  shortUrl,
} from "../components/ui";
import { LinkEditor } from "../components/link-editor";
import { QrEditor } from "../components/qr-editor";
import { AppSelect } from "../components/app-select";
import { useLinkShortcuts } from "../components/workspace-shortcuts";
import "../components/folders.css";
export const Route = createFileRoute("/_app/links")({
  validateSearch: (search: Record<string, unknown>): { folderId?: string } => {
    const folderId = search.folderId;
    return typeof folderId === "string" && (folderId === "unfiled" || /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(folderId))
      ? { folderId: folderId.toLowerCase() } : {};
  },
  component: LinksPage,
});
function LinksPage() {
  const [folders, setFolders] = useState<FolderValue[]>([]);
  const folderId = Route.useSearch().folderId ?? "";
  const navigate = Route.useNavigate();
  const setFolderId = useCallback((value: string) => {
    void navigate({ search: value ? { folderId: value } : {}, resetScroll: false });
  }, [navigate]);
  const [links, setLinks] = useState<Link[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [search, setSearch] = useState("");
  const [tag, setTag] = useState("");
  const [editor, setEditor] = useState<Link | "new" | null>(null);
  const [qr, setQr] = useState<Link | null>(null);
  const closeEditor = useCallback(() => setEditor(null), []);
  const closeQr = useCallback(() => setQr(null), []);
  const createLink = useCallback(() => setEditor("new"), []);
  const focusSearch = useCallback(() => document.querySelector<HTMLInputElement>('[aria-label="Search links"]')?.focus(), []);
  useLinkShortcuts(createLink, focusSearch);
  const load = useCallback(async () => {
    setLoading(true);
    setError("");
    try {
      const [loadedLinks, loadedFolders] = await Promise.all([fetchLinks({ data: {} }), fetchFolders()]);
      setLinks(loadedLinks); setFolders(loadedFolders);
    } catch (err) {
      setError(message(err));
    } finally {
      setLoading(false);
    }
  }, []);
  useEffect(() => {
    void load();
  }, [load]);
  const tags = useMemo(
    () => [...new Set(links.flatMap((link) => link.tags))].sort(),
    [links],
  );
  const missingFolder = !loading && !error && !!folderId && folderId !== "unfiled" && !folders.some((folder) => folder.id === folderId);
  const filtered = links.filter(
    (link) =>
      (!tag || link.tags.includes(tag)) &&
      (!folderId || (folderId === "unfiled" ? !link.folderId : link.folderId === folderId)) &&
      `${link.title} ${link.destination} ${link.slug} ${link.tags.join(" ")}`
        .toLowerCase()
        .includes(search.toLowerCase()),
  );
  return (
    <>
      <SectionHeading
        title="Your links"
        action={
          <PrimaryButton onClick={() => setEditor("new")} aria-keyshortcuts="C" title="Create a link (C)">
            <Plus size={18} />
            Create a link <kbd aria-hidden="true">C</kbd>
          </PrimaryButton>
        }
      />
      <div className="collection-heading">
        <h2>
          All links <span className="count-badge">{links.length}</span>
        </h2>
      </div>
      <div className="filter-bar links-filter-bar">
        <label className="search-field">
          <Search size={18} />
          <input
            aria-label="Search links"
            aria-keyshortcuts="/"
            title="Search links (/)"
            placeholder="Search by name, URL, or tag…"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
        </label>
        <AppSelect
          className="filter-select"
          icon={<Folder size={16} />}
          aria-label="Filter links by folder"
          value={folderId}
          onValueChange={setFolderId}
          disabled={loading}
          options={[{ value: "", label: "All folders" }, { value: "unfiled", label: "No folder" }, ...folders.map((folder) => ({ value: folder.id, label: folder.name })), ...(folderId && folderId !== "unfiled" && !folders.some((folder) => folder.id === folderId) ? [{ value: folderId, label: loading ? "Loading folder…" : "Unavailable folder" }] : [])]}
        />
        <AppSelect
          className="filter-select"
          icon={<Tag size={16} />}
          aria-label="Filter links by tag"
          value={tag}
          onValueChange={setTag}
          options={[{ value: "", label: "All tags" }, ...tags.map((item) => ({ value: item, label: item }))]}
        />
      </div>
      {loading ? (
        <Loading />
      ) : error ? (
        <>
          <ErrorNotice message={error} />
          <button className="button-secondary" onClick={() => void load()}>
            Try again
          </button>
        </>
      ) : !missingFolder && filtered.length ? (
        <div className="link-list">
          {filtered.map((link) => (
            <article className="link-row" key={link.id}>
              <div className="link-avatar">
                <Link2 size={23} />
              </div>
              <div className="link-info">
                <div className="link-title-line">
                  <button
                    className="plain-button link-title"
                    onClick={() => setEditor(link)}
                  >
                    {link.title || new URL(link.destination).hostname}
                  </button>
                  {!link.enabled && (
                    <span className="disabled-badge">Disabled</span>
                  )}
                </div>
                <a
                  className="short-link"
                  href={shortUrl(link.slug, link.domainHostname)}
                  target="_blank"
                  rel="noreferrer"
                >
                  {shortUrl(link.slug, link.domainHostname).replace(/^https?:\/\//, "")}
                  <ArrowUpRight size={13} />
                </a>
                <p className="destination" title={link.resolvedUrl}>
                  {link.resolvedUrl}
                </p>
                <div className="link-meta">
                  {link.folderId && folders.find((folder) => folder.id === link.folderId) && <button className="tag folder-tag" onClick={() => setFolderId(link.folderId!)}><Folder size={12} />{folders.find((folder) => folder.id === link.folderId)!.name}</button>}
                  {link.tags.map((item) => (
                    <button
                      key={item}
                      className="tag"
                      onClick={() => setTag(item)}
                    >
                      {item}
                    </button>
                  ))}
                  <span>
                    {new Date(link.createdAt).toLocaleDateString(undefined, {
                      month: "short",
                      day: "numeric",
                      year: "numeric",
                    })}
                  </span>
                </div>
              </div>
              <div className="link-actions">
                <CopyButton value={shortUrl(link.slug, link.domainHostname)} />
                <button
                  className="icon-button"
                  aria-label={`QR code for ${link.title || link.slug}`}
                  title="QR code"
                  onClick={() => setQr(link)}
                >
                  <QrCode size={18} />
                </button>
                <RouterLink
                  className="icon-button"
                  to="/analytics"
                  search={{ linkId: link.id }}
                  aria-label={`Analytics for ${link.title || link.slug}`}
                  title="View analytics"
                >
                  <BarChart3 size={18} />
                </RouterLink>
                <button
                  className="icon-button"
                  aria-label={`Edit ${link.title || link.slug}`}
                  title="Edit link"
                  onClick={() => setEditor(link)}
                >
                  <Settings2 size={18} />
                </button>
              </div>
            </article>
          ))}
        </div>
      ) : (
        <EmptyState
          icon={<Link2 size={30} />}
          title={
            missingFolder ? "Folder unavailable" : search || tag || folderId
              ? "No matching links"
              : "No links yet"
          }
        >
          {(search || tag || folderId) && (
            <button
              className="button-secondary"
              onClick={() => {
                setSearch("");
                setTag("");
                setFolderId("");
              }}
            >
              Clear filters
            </button>
          )}
        </EmptyState>
      )}
      {editor && (
        <LinkEditor
          link={editor === "new" ? undefined : editor}
          onClose={closeEditor}
          onSaved={(saved) => {
            setLinks((items) => [
              saved,
              ...items.filter((item) => item.id !== saved.id),
            ]);
            setEditor(null);
            void fetchFolders().then(setFolders).catch((err) => setError(message(err)));
          }}
        />
      )}
      {qr && (
        <QrEditor
          link={qr}
          onClose={closeQr}
          onSaved={(style) =>
            setLinks((items) =>
              items.map((item) =>
                item.id === qr.id ? { ...item, qrStyle: style } : item,
              ),
            )
          }
        />
      )}
    </>
  );
}
