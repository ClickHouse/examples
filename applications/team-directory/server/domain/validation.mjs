export class InputError extends Error {
  constructor(message, statusCode = 422) {
    super(message);
    this.statusCode = statusCode;
  }
}
function text(value, name, max, required = false) {
  if (typeof value !== "string" || value.length > max || /\p{Cc}/u.test(value))
    throw new InputError(
      `${name} must be text of at most ${max} characters without control characters.`,
    );
  const clean = value.trim();
  if (required && !clean) throw new InputError(`${name} is required.`);
  return clean;
}
export function profileInput(body) {
  if (
    !body ||
    typeof body !== "object" ||
    Array.isArray(body) ||
    Object.keys(body).some(
      (k) =>
        ![
          "revision",
          "displayName",
          "biography",
          "location",
          "skillIds",
        ].includes(k),
    )
  )
    throw new InputError("Unexpected profile fields.");
  if (!Number.isSafeInteger(body.revision) || body.revision < 1)
    throw new InputError("A valid profile revision is required.");
  if (
    !Array.isArray(body.skillIds) ||
    body.skillIds.length > 6 ||
    body.skillIds.some((id) => !Number.isSafeInteger(id) || id < 1) ||
    new Set(body.skillIds).size !== body.skillIds.length
  )
    throw new InputError("Select up to six distinct skills from the list.");
  return {
    revision: body.revision,
    displayName: text(body.displayName, "Display name", 80, true),
    biography: text(body.biography, "Biography", 1000),
    location: text(body.location, "Location", 80),
    skillIds: [...body.skillIds].sort((a, b) => a - b),
  };
}
export function literalLike(value) {
  return value.replace(/[\\%_]/g, "\\$&");
}
export function directoryInput(query) {
  const q = text(query.q ?? "", "Search", 80);
  const location = text(query.location ?? "", "Location", 80);
  const skill =
    query.skill === undefined || query.skill === ""
      ? null
      : Number(query.skill);
  const page = query.page === undefined ? 1 : Number(query.page);
  const sort = query.sort ?? "name";
  if (
    (skill !== null && (!Number.isSafeInteger(skill) || skill < 1)) ||
    !Number.isSafeInteger(page) ||
    page < 1 ||
    page > 1000 ||
    !["name", "recent"].includes(sort)
  )
    throw new InputError("Invalid directory filter.");
  return { q, location, skill, page, sort };
}

export function profileId(value) {
  if (
    typeof value !== "string" ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
      value,
    )
  )
    throw new InputError("Profile not found.", 404);
  return value.toLowerCase();
}
