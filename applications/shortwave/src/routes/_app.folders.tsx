import { createFileRoute } from "@tanstack/react-router";
import { useCallback, useEffect, useState } from "react";
import type { Folder } from "../lib/types";
import { fetchFolders } from "./-api";
import { FolderManager } from "../components/folder-manager";
import { ErrorNotice, Loading, SectionHeading, message } from "../components/ui";

export const Route = createFileRoute("/_app/folders")({ component: FoldersPage });

function FoldersPage() {
  const [folders, setFolders] = useState<Folder[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const load = useCallback(async () => {
    setLoading(true);
    setError("");
    try { setFolders(await fetchFolders()); }
    catch (err) { setError(message(err)); }
    finally { setLoading(false); }
  }, []);
  useEffect(() => { void load(); }, [load]);
  return <>
    <SectionHeading title="Folders" />
    {loading ? <Loading /> : error ? <>
      <ErrorNotice message={error} />
      <button className="button-secondary" onClick={() => void load()}>Try again</button>
    </> : <FolderManager folders={folders} onChange={setFolders} />}
  </>;
}
