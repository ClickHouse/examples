import { GraphQLError } from "graphql";
export function bad(message: string): never {
  throw new GraphQLError(message, { extensions: { code: "BAD_USER_INPUT" } });
}
export function uuid(value: string) {
  if (
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
      value,
    )
  )
    bad("Expected a UUID");
  return value;
}
export function contents(ids: string[]) {
  if (ids.length > 12 || new Set(ids).size !== ids.length)
    bad("Choose up to 12 distinct products");
  return ids.map(uuid);
}
export function page(first: number, offset: number) {
  if (
    !Number.isInteger(first) ||
    first < 1 ||
    first > 20 ||
    !Number.isInteger(offset) ||
    offset < 0 ||
    offset > 10000
  )
    bad("Use first 1..20 and offset 0..10000");
}
export function title(value: string) {
  const v = value.trim();
  if (v.length < 1 || v.length > 60) bad("Use a title of 1..60 characters");
  return v;
}
export function revision(value: number) {
  if (!Number.isInteger(value) || value < 1 || value >= 2147483647)
    bad("Invalid revision");
  return value;
}
