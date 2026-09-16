import { useEffect, useId, useRef, useState } from "react";
import { Download, Upload } from "lucide-react";
import type QRCodeStyling from "qr-code-styling";
import type { Link, QrStyle } from "../lib/types";
import { qrStyleSchema } from "../lib/domain";
import { CLICKHOUSE_QR_LOGO, qrLogoImage } from "../lib/qr-logo";
import { saveQr } from "../routes/-api";
import { ErrorNotice, message, Modal, PrimaryButton, shortUrl } from "./ui";
import { AppSelect } from "./app-select";

export function QrEditor({
  link,
  onClose,
  onSaved,
}: {
  link: Link;
  onClose: () => void;
  onSaved: (style: QrStyle) => void;
}) {
  const [style, setStyle] = useState<QrStyle>(() => ({
    ...link.qrStyle,
    logo: link.qrStyle.logo ?? CLICKHOUSE_QR_LOGO,
  }));
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const [ready, setReady] = useState(false);
  const [saved, setSaved] = useState(false);
  const dotStyleId = useId();
  const container = useRef<HTMLDivElement>(null);
  const qr = useRef<QRCodeStyling | null>(null);
  useEffect(() => {
    let active = true;
    setReady(false);
    import("qr-code-styling")
      .then(({ default: QR }) => {
        if (!active || !container.current) return;
        const code = new QR({
          width: 280,
          height: 280,
          type: "canvas",
          data: shortUrl(link.slug, link.domainHostname),
          margin: 16,
          qrOptions: { errorCorrectionLevel: "H" },
          dotsOptions: { color: style.foreground, type: style.dots },
          backgroundOptions: { color: style.background },
          image: qrLogoImage(style.logo, style.background),
          imageOptions: {
            // Accepted logos are already self-contained; retain SVG vectors on export.
            saveAsBlob: false,
            hideBackgroundDots: true,
            imageSize: 0.22,
            margin: 5,
          },
        });
        container.current.replaceChildren();
        code.append(container.current);
        qr.current = code;
        setReady(true);
      })
      .catch(() =>
        setError("The QR preview could not load. Please try again."),
      );
    return () => {
      active = false;
    };
  }, [style, link.slug, link.domainHostname]);
  function update(part: Partial<QrStyle>) {
    setStyle((old) => ({ ...old, ...part }));
    setSaved(false);
    setError("");
  }
  async function upload(file?: File) {
    if (!file) return;
    if (
      !["image/png", "image/jpeg", "image/webp"].includes(file.type) ||
      file.size > 120_000
    ) {
      setError("Choose a PNG, JPEG, or WebP logo smaller than 120 KB.");
      return;
    }
    const reader = new FileReader();
    reader.onload = () => update({ logo: String(reader.result) });
    reader.onerror = () => setError("This image could not be read.");
    reader.readAsDataURL(file);
  }
  async function save() {
    setBusy(true);
    setError("");
    try {
      const result = await saveQr({ data: { linkId: link.id, style } });
      onSaved(result);
      setSaved(true);
    } catch (err) {
      setError(message(err));
    } finally {
      setBusy(false);
    }
  }
  async function download(extension: "png" | "svg") {
    try {
      qrStyleSchema.parse(style);
      await qr.current?.download({ name: `shortwave-${link.slug}`, extension });
    } catch (err) {
      setError(message(err));
    }
  }
  return (
    <Modal title="Customize QR code" onClose={onClose} wide>
      <div className="modal-body">
        {error && <ErrorNotice message={error} />}
        <div className="qr-layout">
          <div>
            <div className="qr-preview" ref={container} />
            <p className="qr-link">{shortUrl(link.slug, link.domainHostname)}</p>
          </div>
          <div className="qr-controls">
            <div className="color-fields">
              <label className="field">
                <span>Code color</span>
                <input
                  type="color"
                  value={style.foreground}
                  onChange={(e) => update({ foreground: e.target.value })}
                />
                <small>{style.foreground}</small>
              </label>
              <label className="field">
                <span>Background</span>
                <input
                  type="color"
                  value={style.background}
                  onChange={(e) => update({ background: e.target.value })}
                />
                <small>{style.background}</small>
              </label>
            </div>
            <div className="field">
              <label htmlFor={dotStyleId}>Dot style</label>
              <AppSelect
                id={dotStyleId}
                value={style.dots}
                onValueChange={(value) =>
                  update({ dots: value as QrStyle["dots"] })
                }
                options={[
                  { value: "square", label: "Classic squares" },
                  { value: "rounded", label: "Soft corners" },
                  { value: "dots", label: "Round dots" },
                ]}
              />
            </div>
            <label className="field">
              <span>
                Custom logo <small>Optional</small>
              </span>
              <span className="upload-label">
                <Upload size={17} />
                Choose an image
                <input
                  type="file"
                  accept="image/png,image/jpeg,image/webp"
                  onChange={(e) => {
                    void upload(e.target.files?.[0]);
                    e.target.value = "";
                  }}
                />
              </span>
              <small>PNG, JPEG, or WebP · up to 120 KB</small>
            </label>
            <div className="qr-logo-actions">
            {style.logo && style.logo !== CLICKHOUSE_QR_LOGO && (
              <button
                className="text-link plain-button"
                onClick={() => update({ logo: CLICKHOUSE_QR_LOGO })}
              >
                Remove custom logo
              </button>
            )}
            </div>
          </div>
        </div>
      </div>
      <div className="modal-actions qr-actions">
        <div>
          <button
            className="button-secondary"
            disabled={!ready}
            onClick={() => void download("png")}
          >
            <Download size={16} />
            PNG
          </button>
          <button
            className="button-secondary"
            disabled={!ready}
            onClick={() => void download("svg")}
          >
            <Download size={16} />
            SVG
          </button>
        </div>
        <PrimaryButton disabled={busy || saved} onClick={() => void save()}>
          {busy ? "Saving…" : saved ? "Style saved" : "Save style"}
        </PrimaryButton>
      </div>
    </Modal>
  );
}
