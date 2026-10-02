import { InputError, literalLike } from "./validation.mjs";
const publicColumns = [
  "id",
  "display_name",
  "biography",
  "location",
  "revision",
  "updated_at",
];
async function withSkills(trx, user) {
  const skills = await trx("user_skills")
    .join("skills", "skills.id", "user_skills.skill_id")
    .where("user_id", user.id)
    .select("skills.id", "skills.name")
    .orderBy("skills.name");
  return { ...user, skills };
}
export async function readProfile(db, id) {
  return db.transaction(async (trx) => {
    const user = await trx("users")
      .select(publicColumns)
      .where({ id, active: true })
      .forShare()
      .first();
    if (!user) throw new InputError("Profile not found.", 404);
    return withSkills(trx, user);
  });
}
export async function updateProfile(db, actorId, targetId, input) {
  if (actorId !== targetId) throw new InputError("Profile not found.", 404);
  return db.transaction(async (trx) => {
    const user = await trx("users")
      .where({ id: actorId, active: true })
      .forUpdate()
      .first();
    if (!user) throw new InputError("Sign in again.", 401);
    if (user.revision !== input.revision)
      throw new InputError(
        "This profile changed. Reload it before saving your edits.",
        409,
      );
    await trx("users")
      .where("id", actorId)
      .update({
        display_name: input.displayName,
        biography: input.biography,
        location: input.location,
        revision: user.revision + 1,
        updated_at: trx.fn.now(),
      });
    await trx("user_skills").where("user_id", actorId).delete();
    // Database-backed validation occurs after writes; an invalid skill rolls all of them back.
    const found = await trx("skills")
      .whereIn("id", input.skillIds)
      .select("id");
    if (found.length !== input.skillIds.length)
      throw new InputError(
        "A selected skill is no longer available. Reload the skill list.",
      );
    if (input.skillIds.length)
      await trx("user_skills").insert(
        input.skillIds.map((skill_id) => ({ user_id: actorId, skill_id })),
      );
    return withSkills(
      trx,
      await trx("users").select(publicColumns).where("id", actorId).first(),
    );
  });
}
export async function listDirectory(db, filters) {
  return db.transaction(async (trx) => {
    await trx.raw("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY");
    const query = trx("users").where("active", true);
    if (filters.q)
      query.andWhere(function () {
        for (const column of ["display_name", "biography", "location"])
          this.orWhereRaw("?? ILIKE ? ESCAPE '\\'", [
            column,
            `%${literalLike(filters.q)}%`,
          ]);
      });
    if (filters.location)
      query.andWhereRaw("location ILIKE ? ESCAPE '\\'", [
        `%${literalLike(filters.location)}%`,
      ]);
    if (filters.skill !== null)
      query.whereExists(
        trx("user_skills")
          .select(trx.raw("1"))
          .whereRaw("user_skills.user_id = users.id")
          .where("skill_id", filters.skill),
      );
    const [{ count }] = await query.clone().count("* as count");
    const ordered =
      filters.sort === "recent"
        ? query.clone().orderBy("updated_at", "desc")
        : query.clone().orderByRaw("lower(display_name) ASC");
    const users = await ordered
      .orderBy("id")
      .select(publicColumns)
      .limit(12)
      .offset((filters.page - 1) * 12);
    const members = users.length
      ? await trx("user_skills")
          .join("skills", "skills.id", "user_skills.skill_id")
          .whereIn(
            "user_id",
            users.map((u) => u.id),
          )
          .select("user_id", "skills.id", "skills.name")
          .orderBy("skills.name")
      : [];
    return {
      profiles: users.map((user) => ({
        ...user,
        skills: members
          .filter((s) => s.user_id === user.id)
          .map(({ id, name }) => ({ id, name })),
      })),
      total: Number(count),
      page: filters.page,
      pageSize: 12,
    };
  });
}
