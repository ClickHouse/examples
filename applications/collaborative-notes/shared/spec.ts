export const NOTES = [
  { id: "release-planning", title: "Release planning" },
  { id: "meeting-notes", title: "Meeting notes" },
  { id: "workshop-checklist", title: "Workshop checklist" },
] as const;
export const MAX_STATE_BYTES = 512 * 1024;
export const MAX_FRAME_BYTES = 64 * 1024;
export const MAX_TEXT_LENGTH = 10000;
export function allowedDocument(name: string): boolean {
  return NOTES.some((note) => note.id === name);
}
export type StoreReceipt = {
  document: string;
  revision: number;
  storedAt: string;
  capturedHash: string;
};
export type Storage = {
  load(name: string): Promise<Uint8Array>;
  store(name: string, captured: Uint8Array): Promise<StoreReceipt>;
};
