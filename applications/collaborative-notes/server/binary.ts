import * as Y from "yjs";
import { MAX_STATE_BYTES, MAX_TEXT_LENGTH } from "../shared/spec.js";

export function validateState(bytes: Uint8Array): void {
  if (bytes.byteLength > MAX_STATE_BYTES)
    throw new Error("Document binary limit exceeded.");
  const preview = new Y.Doc({ gc: false });
  try {
    Y.applyUpdate(preview, bytes);
    if (preview.store.pendingStructs || preview.store.pendingDs)
      throw new Error("Incomplete note update rejected.");
    if ([...preview.share.keys()].some((key) => key !== "content"))
      throw new Error("Only plain note text is supported.");
    const text = preview.getText("content");
    // Text-only content: no embedded objects or formatting attributes.
    if (
      text
        .toDelta()
        .some(
          (part: { insert?: unknown; attributes?: unknown }) =>
            typeof part.insert !== "string" || part.attributes,
        )
    )
      throw new Error("Only plain note text is supported.");
    const value = text.toString();
    if (
      value.length > MAX_TEXT_LENGTH ||
      /[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f-\u009f\uFFFD]/u.test(value)
    )
      throw new Error("Note text limit or character rule exceeded.");
  } finally {
    preview.destroy();
  }
}
export function mergeState(
  stored: Uint8Array,
  incoming: Uint8Array,
): Uint8Array {
  const merged = Y.mergeUpdates([stored, incoming]);
  validateState(merged);
  return merged;
}
export function seedState(text: string): Uint8Array {
  const document = new Y.Doc();
  document.getText("content").insert(0, text);
  const bytes = Y.encodeStateAsUpdate(document);
  document.destroy();
  return bytes;
}
