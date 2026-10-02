export async function up(knex) {
  await knex.raw(`
    CREATE TABLE users (
      id uuid PRIMARY KEY, email text NOT NULL UNIQUE CHECK (length(email) BETWEEN 3 AND 254),
      password_hash text NOT NULL, active boolean NOT NULL DEFAULT true,
      display_name text NOT NULL CHECK (length(btrim(display_name)) BETWEEN 1 AND 80),
      biography text NOT NULL DEFAULT '' CHECK (length(biography) <= 1000),
      location text NOT NULL DEFAULT '' CHECK (length(location) <= 80),
      revision integer NOT NULL DEFAULT 1 CHECK (revision > 0),
      updated_at timestamptz NOT NULL DEFAULT now()
    );
    CREATE TABLE skills (id integer PRIMARY KEY, name text NOT NULL UNIQUE CHECK (length(name) BETWEEN 1 AND 60));
    CREATE TABLE user_skills (
      user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      skill_id integer NOT NULL REFERENCES skills(id), PRIMARY KEY(user_id,skill_id)
    );
    CREATE INDEX user_skills_skill ON user_skills(skill_id,user_id);
    CREATE FUNCTION check_skill_limit() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN
      PERFORM 1 FROM users WHERE id = NEW.user_id FOR UPDATE;
      IF (SELECT count(*) FROM user_skills WHERE user_id = NEW.user_id) >= 6 THEN
        RAISE EXCEPTION 'A profile supports at most six skills' USING ERRCODE = '23514';
      END IF;
      RETURN NEW;
    END $$;
    CREATE TRIGGER skill_limit BEFORE INSERT OR UPDATE ON user_skills FOR EACH ROW EXECUTE FUNCTION check_skill_limit();
  `);
}
export async function down(knex) {
  await knex.raw(
    "DROP TABLE user_skills; DROP FUNCTION check_skill_limit(); DROP TABLE skills; DROP TABLE users;",
  );
}
