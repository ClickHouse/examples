import { createFileRoute } from "@tanstack/react-router";
import { useCallback, useEffect, useState, type FormEvent } from "react";
import {
  ArrowUpRight,
  Plus,
  SlidersHorizontal,
  Trash2,
  Pencil,
} from "lucide-react";
import type { UtmTemplate, UtmValues } from "../lib/types";
import { fetchTemplates, removeTemplate, saveTemplate } from "./-api";
import {
  EmptyState,
  ErrorNotice,
  Loading,
  message,
  Modal,
  PrimaryButton,
  SectionHeading,
} from "../components/ui";
import { UtmFields } from "../components/link-editor";
export const Route = createFileRoute("/_app/templates")({
  component: TemplatesPage,
});
function TemplatesPage() {
  const [templates, setTemplates] = useState<UtmTemplate[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [editor, setEditor] = useState<UtmTemplate | "new" | null>(null);
  const [deleting, setDeleting] = useState<UtmTemplate | null>(null);
  const [busy, setBusy] = useState(false);
  const close = useCallback(() => setEditor(null), []);
  const closeDelete = useCallback(() => setDeleting(null), []);
  const load = useCallback(async () => {
    setLoading(true);
    setError("");
    try {
      setTemplates(await fetchTemplates());
    } catch (err) {
      setError(message(err));
    } finally {
      setLoading(false);
    }
  }, []);
  useEffect(() => {
    void load();
  }, [load]);
  async function remove() {
    if (!deleting) return;
    setBusy(true);
    try {
      await removeTemplate({ data: deleting.id });
      setTemplates((items) => items.filter((item) => item.id !== deleting.id));
      setDeleting(null);
    } catch (err) {
      setError(message(err));
      setDeleting(null);
    } finally {
      setBusy(false);
    }
  }
  return (
    <>
      <SectionHeading
        title="UTM templates"
        action={
          <PrimaryButton onClick={() => setEditor("new")}>
            <Plus size={18} />
            New template
          </PrimaryButton>
        }
      />
      {error && <ErrorNotice message={error} />}
      {loading ? (
        <Loading />
      ) : !templates.length ? (
        <EmptyState
          icon={<SlidersHorizontal size={30} />}
          title="No templates yet"
        >
          {null}
        </EmptyState>
      ) : (
        <div className="template-grid">
          {templates.map((template) => (
            <article key={template.id} className="template-card">
              <div className="template-icon">
                <SlidersHorizontal size={22} />
              </div>
              <h2>{template.name}</h2>
              <dl>
                {Object.entries(template.values)
                  .filter(([, value]) => value)
                  .map(([key, value]) => (
                    <div key={key}>
                      <dt>utm_{key}</dt>
                      <dd>{value}</dd>
                    </div>
                  ))}
              </dl>
              <div className="template-actions">
                <button
                  className="button-secondary"
                  onClick={() => setEditor(template)}
                >
                  <Pencil size={15} />
                  Edit template
                </button>
                <button
                  className="icon-button"
                  aria-label={`Delete ${template.name}`}
                  onClick={() => setDeleting(template)}
                >
                  <Trash2 size={17} />
                </button>
              </div>
            </article>
          ))}
        </div>
      )}
      {editor && (
        <TemplateEditor
          template={editor === "new" ? undefined : editor}
          onClose={close}
          onSaved={(saved) => {
            setTemplates((items) => [
              saved,
              ...items.filter((item) => item.id !== saved.id),
            ]);
            setEditor(null);
          }}
        />
      )}
      {deleting && (
        <Modal title="Delete this template?" onClose={closeDelete}>
          <div className="modal-body">
            <p>
              “{deleting.name}” will be removed. Links you’ve already created
              will keep their parameters.
            </p>
          </div>
          <div className="modal-actions">
            <button
              className="button-secondary"
              disabled={busy}
              onClick={closeDelete}
            >
              Keep template
            </button>
            <PrimaryButton
              type="danger"
              disabled={busy}
              onClick={() => void remove()}
            >
              {busy ? "Deleting…" : "Delete template"}
            </PrimaryButton>
          </div>
        </Modal>
      )}
    </>
  );
}
function TemplateEditor({
  template,
  onClose,
  onSaved,
}: {
  template?: UtmTemplate;
  onClose: () => void;
  onSaved: (value: UtmTemplate) => void;
}) {
  const [name, setName] = useState(template?.name || "");
  const [values, setValues] = useState<UtmValues>(template?.values || {});
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  async function submit(event: FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError("");
    try {
      onSaved(await saveTemplate({ data: { id: template?.id, name, values } }));
    } catch (err) {
      setError(message(err));
    } finally {
      setBusy(false);
    }
  }
  return (
    <Modal
      title={template ? "Fine-tune your template" : "Create a UTM template"}
      onClose={onClose}
      wide
    >
      <form onSubmit={submit}>
        <div className="modal-body">
          {error && <ErrorNotice message={error} />}
          <label className="field">
            <span>
              Template name <em>*</em>
            </span>
            <input
              autoFocus
              required
              maxLength={100}
              placeholder="e.g. Weekly newsletter"
              value={name}
              onChange={(e) => setName(e.target.value)}
            />
          </label>
          <UtmFields value={values} onChange={setValues} />
        </div>
        <div className="modal-actions">
          <button
            type="button"
            className="button-secondary"
            onClick={onClose}
            disabled={busy}
          >
            Cancel
          </button>
          <PrimaryButton htmlType="submit" disabled={busy}>
            {busy ? "Saving…" : "Save template"}
            <ArrowUpRight size={17} />
          </PrimaryButton>
        </div>
      </form>
    </Modal>
  );
}
