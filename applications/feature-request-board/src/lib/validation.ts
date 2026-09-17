export const statuses = ["OPEN", "PLANNED", "IN_PROGRESS", "SHIPPED"] as const;
export type Status = (typeof statuses)[number];
export const statusLabels: Record<Status, string> = {
  OPEN: "Open",
  PLANNED: "Planned",
  IN_PROGRESS: "In progress",
  SHIPPED: "Shipped",
};

export class BoardError extends Error {}

export function parseStatus(value: unknown): Status {
  if (typeof value !== "string" || !statuses.includes(value as Status)) {
    throw new BoardError("Choose a valid status.");
  }
  return value as Status;
}

export function parseRequestId(value: unknown): string {
  if (
    typeof value !== "string" ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
      value,
    )
  ) {
    throw new BoardError("This request could not be found.");
  }
  return value;
}

export function parseContent(input: { title: unknown; description: unknown }) {
  const title = typeof input.title === "string" ? input.title.trim() : "";
  const description =
    typeof input.description === "string" ? input.description.trim() : "";
  if (Array.from(title).length < 8 || Array.from(title).length > 120)
    throw new BoardError("Use 8–120 characters for the title.");
  if (
    Array.from(description).length < 20 ||
    Array.from(description).length > 4000
  )
    throw new BoardError("Use 20–4,000 characters for the description.");
  return { title, description };
}

export function isMaintainer(
  userId: string | null,
  allowlist = process.env.MAINTAINER_USER_IDS ?? "",
) {
  return (
    userId !== null &&
    allowlist
      .split(",")
      .map((id) => id.trim())
      .filter(Boolean)
      .includes(userId)
  );
}

export type Cursor = { createdAt: Date; id: string };
export function encodeCursor(cursor: Cursor) {
  return Buffer.from(`${cursor.createdAt.toISOString()}_${cursor.id}`).toString(
    "base64url",
  );
}
export function decodeCursor(value: string | undefined): Cursor | undefined {
  if (!value) return undefined;
  if (value.length > 120)
    throw new BoardError(
      "Invalid page link. Return to the board to start again.",
    );
  const [date, id] = Buffer.from(value, "base64url").toString().split("_");
  if (!date || !id || !Number.isFinite(Date.parse(date)))
    throw new BoardError(
      "Invalid page link. Return to the board to start again.",
    );
  return { createdAt: new Date(date), id: parseRequestId(id) };
}
