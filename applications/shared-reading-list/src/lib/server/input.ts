export function linkInput(data: Record<string, unknown>) {
  if (
    typeof data.title !== "string" ||
    !data.title.trim() ||
    data.title.trim().length > 200
  )
    throw new Error("Title must be 1–200 characters");
  if (typeof data.url !== "string" || data.url.length > 2048)
    throw new Error("Enter a URL up to 2048 characters");
  let url: URL;
  try {
    url = new URL(data.url.trim());
  } catch {
    throw new Error("Enter a valid HTTP or HTTPS URL");
  }
  if (
    !["http:", "https:"].includes(url.protocol) ||
    url.username ||
    url.password
  )
    throw new Error("Enter an HTTP or HTTPS URL without credentials");
  if (typeof data.notes !== "string" || data.notes.length > 2000)
    throw new Error("Notes must be at most 2000 characters");
  if (typeof data.tags !== "string" || data.tags.length > 300)
    throw new Error("Enter comma-separated tags, at most 300 characters");
  const tags = [
    ...new Set(
      data.tags
        .split(",")
        .map((t) => t.trim().toLowerCase())
        .filter(Boolean),
    ),
  ];
  if (tags.length > 8 || tags.some((t) => !/^[a-z0-9][a-z0-9-]{0,29}$/.test(t)))
    throw new Error(
      "Use at most 8 tags of 1–30 lowercase letters, numbers or hyphens",
    );
  return {
    title: data.title.trim(),
    url: url.toString(),
    notes: data.notes.trim(),
    tags,
  };
}
export const validId = (id: string) =>
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id);

export type LinkInput = ReturnType<typeof linkInput>;
