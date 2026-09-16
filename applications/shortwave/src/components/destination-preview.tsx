import { useEffect, useState } from "react";
import { Image as ImageIcon } from "lucide-react";
import { validateDestination } from "../lib/domain";
import type { DestinationMetadata } from "../lib/preview";
import { fetchDestinationPreview } from "../routes/-preview-api";
import "./destination-preview.css";

export function DestinationPreview({ destination }: { destination: string }) {
  const [result, setResult] = useState<{ url: string; metadata: DestinationMetadata | null } | null>(null);
  const [brokenImage, setBrokenImage] = useState<string | null>(null);
  let previewDestination = "";
  let hostname = "";
  try {
    previewDestination = validateDestination(destination);
    hostname = new URL(previewDestination).hostname;
  } catch { /* Incomplete draft. */ }
  useEffect(() => {
    if (!hostname) return;
    let active = true;
    const timer = setTimeout(() => {
      fetchDestinationPreview({ data: previewDestination })
        .then((metadata) => { if (active) setResult({ url: previewDestination, metadata }); })
        .catch(() => { if (active) setResult({ url: previewDestination, metadata: null }); });
    }, 650);
    return () => { active = false; clearTimeout(timer); };
  }, [previewDestination, hostname]);
  const current = result?.url === previewDestination ? result : null;
  const metadata = current?.metadata;
  const loading = Boolean(hostname && !current);
  const unavailable = Boolean(hostname && current && metadata?.status !== "ready");
  return (
    <section className="destination-preview" aria-label="Destination preview">
      <h3>Destination preview</h3>
      <div className="destination-preview-card" aria-busy={loading}>
        <div className="destination-preview-media">
          {metadata?.image && metadata.image !== brokenImage ? (
            <img key={`${previewDestination}:${metadata.image}`} className="destination-preview-image" src={metadata.image} alt={metadata.imageAlt || ""} referrerPolicy="no-referrer" onError={() => setBrokenImage(metadata.image)} />
          ) : (
            <div className="destination-preview-placeholder"><ImageIcon size={30} strokeWidth={1.2} /><span>{loading ? "Loading preview…" : hostname ? "No image available" : "Add a destination to preview"}</span></div>
          )}
        </div>
        <div className="destination-preview-copy">
          <small>{metadata?.siteName || hostname}</small>
          <strong>{metadata?.title || hostname}</strong>
          <p><span role="status">{unavailable ? "Preview unavailable. You can still save this link." : ""}</span>{!unavailable && (metadata?.description || "")}</p>
        </div>
      </div>
    </section>
  );
}
