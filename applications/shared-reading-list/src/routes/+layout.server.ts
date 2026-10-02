export function load({ locals }) {
  return {
    user: locals.user ? { id: locals.user.id, name: locals.user.name } : null,
  };
}
