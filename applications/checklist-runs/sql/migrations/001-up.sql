CREATE TABLE checklist_storage.operators (
    role_name text PRIMARY KEY CHECK (role_name IN ('checklist_north', 'checklist_south')),
    lock_nonce integer NOT NULL DEFAULT 0
);

CREATE TABLE checklist_storage.templates (
    id uuid PRIMARY KEY,
    version integer NOT NULL CHECK (version BETWEEN 1 AND 1000000),
    title text NOT NULL CHECK (char_length(title) BETWEEN 1 AND 80),
    steps jsonb NOT NULL CHECK (jsonb_typeof(steps) = 'array'
        AND jsonb_array_length(steps) BETWEEN 1 AND 10)
);

CREATE TABLE checklist_storage.runs (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    operator_role text NOT NULL REFERENCES checklist_storage.operators(role_name),
    request_id uuid NOT NULL,
    start_payload jsonb NOT NULL,
    start_result jsonb NOT NULL,
    template_id uuid NOT NULL REFERENCES checklist_storage.templates(id),
    template_version integer NOT NULL,
    template_title text NOT NULL,
    template_snapshot jsonb NOT NULL,
    label text NOT NULL CHECK (char_length(label) BETWEEN 1 AND 80),
    total_steps integer NOT NULL CHECK (total_steps BETWEEN 1 AND 10),
    completed_steps integer NOT NULL DEFAULT 0,
    completed_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (operator_role, request_id),
    UNIQUE (operator_role, id),
    CHECK (completed_steps BETWEEN 0 AND total_steps),
    CHECK ((completed_steps = total_steps) = (completed_at IS NOT NULL)),
    CHECK (jsonb_typeof(template_snapshot) = 'array'
        AND jsonb_array_length(template_snapshot) = total_steps)
);

CREATE TABLE checklist_storage.run_steps (
    operator_role text NOT NULL,
    run_id bigint NOT NULL REFERENCES checklist_storage.runs(id),
    step_number integer NOT NULL CHECK (step_number BETWEEN 1 AND 10),
    title text NOT NULL CHECK (char_length(title) BETWEEN 1 AND 120),
    PRIMARY KEY (run_id, step_number),
    FOREIGN KEY (operator_role, run_id)
        REFERENCES checklist_storage.runs(operator_role, id)
);

CREATE TABLE checklist_storage.completions (
    operator_role text NOT NULL,
    request_id uuid NOT NULL,
    run_id bigint NOT NULL REFERENCES checklist_storage.runs(id),
    step_number integer NOT NULL,
    payload jsonb NOT NULL,
    result jsonb NOT NULL,
    note text NOT NULL CHECK (char_length(note) <= 400),
    completed_at timestamptz NOT NULL,
    PRIMARY KEY (operator_role, request_id),
    UNIQUE (run_id, step_number),
    FOREIGN KEY (operator_role, run_id)
        REFERENCES checklist_storage.runs(operator_role, id),
    FOREIGN KEY (run_id, step_number)
        REFERENCES checklist_storage.run_steps(run_id, step_number)
);

ALTER TABLE checklist_storage.operators ENABLE ROW LEVEL SECURITY;
ALTER TABLE checklist_storage.runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE checklist_storage.run_steps ENABLE ROW LEVEL SECURITY;
ALTER TABLE checklist_storage.completions ENABLE ROW LEVEL SECURITY;
CREATE POLICY operator_scope ON checklist_storage.operators
    USING (role_name = current_user) WITH CHECK (role_name = current_user);
CREATE POLICY run_scope ON checklist_storage.runs
    USING (operator_role = current_user) WITH CHECK (operator_role = current_user);
CREATE POLICY step_scope ON checklist_storage.run_steps
    USING (operator_role = current_user) WITH CHECK (operator_role = current_user);
CREATE POLICY completion_scope ON checklist_storage.completions
    USING (operator_role = current_user) WITH CHECK (operator_role = current_user);

-- Views keep storage private and preserve the requesting role's RLS policies.
CREATE VIEW checklist_api.templates WITH (security_invoker = true) AS
    SELECT id, version, title, steps FROM checklist_storage.templates;
CREATE VIEW checklist_api.runs WITH (security_invoker = true) AS
    SELECT id::text AS id, template_id, template_version, template_title, label, total_steps,
        completed_steps, completed_at, created_at
    FROM checklist_storage.runs;
CREATE VIEW checklist_api.run_steps WITH (security_invoker = true) AS
    SELECT run_id::text AS run_id, step_number, title FROM checklist_storage.run_steps;
CREATE VIEW checklist_api.completions WITH (security_invoker = true) AS
    SELECT run_id::text AS run_id, step_number, note, completed_at FROM checklist_storage.completions;

-- Cast IDs stay exact on the JSON wire. Explicit computed relationships keep
-- embeds available without exposing a second numeric representation.
CREATE FUNCTION checklist_api.run_steps(parent checklist_api.runs)
RETURNS SETOF checklist_api.run_steps ROWS 10
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = pg_catalog AS $$
    SELECT s.run_id::text, s.step_number, s.title
    FROM checklist_storage.run_steps AS s
    WHERE s.run_id = parent.id::bigint ORDER BY s.step_number ASC;
$$;
CREATE FUNCTION checklist_api.completions(parent checklist_api.runs)
RETURNS SETOF checklist_api.completions ROWS 10
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = pg_catalog AS $$
    SELECT c.run_id::text, c.step_number, c.note, c.completed_at
    FROM checklist_storage.completions AS c
    WHERE c.run_id = parent.id::bigint ORDER BY c.step_number ASC;
$$;

CREATE FUNCTION checklist_storage.check_request() RETURNS void
LANGUAGE plpgsql STABLE SECURITY INVOKER
SET search_path = pg_catalog AS $$
DECLARE
    claims jsonb := nullif(current_setting('request.jwt.claims', true), '')::jsonb;
    issued bigint;
    expires bigint;
BEGIN
    IF current_user NOT IN ('checklist_north', 'checklist_south')
        OR claims->>'role' IS DISTINCT FROM current_user::text
        OR claims->>'aud' IS DISTINCT FROM 'checklist-runs'
        OR jsonb_typeof(claims->'iat') IS DISTINCT FROM 'number'
        OR jsonb_typeof(claims->'exp') IS DISTINCT FROM 'number'
        OR (claims->>'iat') !~ '^[0-9]{10}$'
        OR (claims->>'exp') !~ '^[0-9]{10}$'
    THEN
        RAISE SQLSTATE 'PT401' USING MESSAGE = 'A scoped short-lived token is required.';
    END IF;
    issued := (claims->>'iat')::bigint;
    expires := (claims->>'exp')::bigint;
    IF expires <= issued OR expires - issued > 900 THEN
        RAISE SQLSTATE 'PT401' USING MESSAGE = 'Token lifetime must be at most 15 minutes.';
    END IF;
END;
$$;

CREATE FUNCTION checklist_api.list_runs(p_after bigint DEFAULT 0, p_limit integer DEFAULT 20)
RETURNS SETOF checklist_api.runs
LANGUAGE plpgsql STABLE SECURITY INVOKER
SET search_path = pg_catalog AS $$
BEGIN
    IF p_after IS NULL OR p_after < 0 OR p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 20 THEN
        RAISE SQLSTATE 'PT422' USING MESSAGE = 'Use a nonnegative cursor and a limit from 1 through 20.';
    END IF;
    RETURN QUERY SELECT r.id::text, r.template_id, r.template_version,
        r.template_title, r.label, r.total_steps, r.completed_steps,
        r.completed_at, r.created_at FROM checklist_storage.runs AS r
        WHERE r.id > p_after ORDER BY r.id ASC LIMIT p_limit;
END;
$$;

CREATE FUNCTION checklist_api.start_run(p_request_id uuid, p_template_id uuid, p_label text)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY INVOKER
SET search_path = pg_catalog AS $$
DECLARE
    canonical_label text;
    payload jsonb;
    existing checklist_storage.runs%ROWTYPE;
    template checklist_storage.templates%ROWTYPE;
    new_id bigint;
    result jsonb;
BEGIN
    IF p_request_id IS NULL OR p_template_id IS NULL OR p_label IS NULL
        OR octet_length(p_label) > 320 OR p_label ~ '[[:cntrl:]]'
        OR char_length(btrim(p_label)) NOT BETWEEN 1 AND 80
    THEN
        RAISE SQLSTATE 'PT422' USING MESSAGE = 'Provide request/template UUIDs and a label of 1 through 80 characters without controls.';
    END IF;
    canonical_label := btrim(p_label);
    payload := jsonb_build_object('template_id', p_template_id, 'label', canonical_label);

    -- All starts in this scope serialize the retry check and the 100-run quota.
    PERFORM 1 FROM checklist_storage.operators AS o
        WHERE o.role_name = current_user FOR UPDATE;
    IF NOT FOUND THEN
        RAISE SQLSTATE 'PT403' USING MESSAGE = 'No operator scope is available.';
    END IF;
    SELECT r.* INTO existing FROM checklist_storage.runs AS r
        WHERE r.operator_role = current_user AND r.request_id = p_request_id;
    IF FOUND THEN
        IF existing.start_payload <> payload THEN
            RAISE SQLSTATE 'PT409' USING MESSAGE = 'This start request key has a different payload.';
        END IF;
        RETURN existing.start_result;
    END IF;
    IF (SELECT count(*) FROM checklist_storage.runs AS r
        WHERE r.operator_role = current_user) >= 100 THEN
        RAISE SQLSTATE 'PT409' USING MESSAGE = 'This operator has reached the 100-run limit.';
    END IF;
    SELECT t.* INTO template FROM checklist_storage.templates AS t WHERE t.id = p_template_id;
    IF NOT FOUND THEN
        RAISE SQLSTATE 'PT404' USING MESSAGE = 'Template not found.';
    END IF;

    INSERT INTO checklist_storage.runs
        (operator_role, request_id, start_payload, start_result, template_id,
         template_version, template_title, template_snapshot, label, total_steps)
    VALUES (current_user, p_request_id, payload, '{}'::jsonb, template.id,
        template.version, template.title, template.steps, canonical_label,
        jsonb_array_length(template.steps)) RETURNING id INTO new_id;

    result := jsonb_build_object('run_id', new_id::text, 'template_id', template.id,
        'template_version', template.version, 'template_title', template.title,
        'label', canonical_label, 'total_steps', jsonb_array_length(template.steps),
        'completed_steps', 0, 'status', 'open');
    UPDATE checklist_storage.runs SET start_result = result WHERE id = new_id;
    INSERT INTO checklist_storage.run_steps (operator_role, run_id, step_number, title)
        SELECT current_user, new_id, s.ordinality::integer, s.title
        FROM jsonb_array_elements_text(template.steps) WITH ORDINALITY AS s(title, ordinality);
    RETURN result;
END;
$$;

CREATE FUNCTION checklist_api.complete_step(
    p_request_id uuid, p_run_id bigint, p_step_number integer, p_note text DEFAULT '')
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY INVOKER
SET search_path = pg_catalog AS $$
DECLARE
    canonical_note text;
    payload jsonb;
    retained checklist_storage.completions%ROWTYPE;
    locked_run checklist_storage.runs%ROWTYPE;
    completed_time timestamptz;
    new_count integer;
    result jsonb;
BEGIN
    IF p_request_id IS NULL OR p_run_id IS NULL OR p_run_id < 1
        OR p_step_number IS NULL OR p_step_number NOT BETWEEN 1 AND 10
        OR p_note IS NULL OR octet_length(p_note) > 1600
        OR char_length(p_note) > 400 OR p_note ~ '[[:cntrl:]]'
    THEN
        RAISE SQLSTATE 'PT422' USING MESSAGE = 'Provide a run, step from 1 through 10 and a note of at most 400 characters without controls.';
    END IF;
    canonical_note := btrim(p_note);
    payload := jsonb_build_object('run_id', p_run_id::text, 'step_number', p_step_number, 'note', canonical_note);

    SELECT r.* INTO locked_run FROM checklist_storage.runs AS r
        WHERE r.operator_role = current_user AND r.id = p_run_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE SQLSTATE 'PT404' USING MESSAGE = 'Run not found.';
    END IF;
    SELECT c.* INTO retained FROM checklist_storage.completions AS c
        WHERE c.operator_role = current_user AND c.request_id = p_request_id;
    IF FOUND THEN
        IF retained.payload <> payload THEN
            RAISE SQLSTATE 'PT409' USING MESSAGE = 'This completion request key has a different payload.';
        END IF;
        RETURN retained.result;
    END IF;
    IF locked_run.completed_at IS NOT NULL THEN
        RAISE SQLSTATE 'PT409' USING MESSAGE = 'This run is completed.';
    END IF;
    IF NOT EXISTS (SELECT FROM checklist_storage.run_steps AS s
        WHERE s.run_id = p_run_id AND s.step_number = p_step_number) THEN
        RAISE SQLSTATE 'PT404' USING MESSAGE = 'Step not found.';
    END IF;
    IF EXISTS (SELECT FROM checklist_storage.completions AS c
        WHERE c.run_id = p_run_id AND c.step_number = p_step_number) THEN
        RAISE SQLSTATE 'PT409' USING MESSAGE = 'This step already has a different completion key.';
    END IF;

    completed_time := clock_timestamp();
    new_count := locked_run.completed_steps + 1;
    UPDATE checklist_storage.runs SET completed_steps = new_count,
        completed_at = CASE WHEN new_count = total_steps THEN completed_time ELSE NULL END
        WHERE id = p_run_id;
    result := jsonb_build_object('run_id', p_run_id::text, 'step_number', p_step_number,
        'note', canonical_note, 'completed_at', completed_time,
        'completed_steps', new_count,
        'status', CASE WHEN new_count = locked_run.total_steps THEN 'completed' ELSE 'open' END);
    INSERT INTO checklist_storage.completions
        (operator_role, request_id, run_id, step_number, payload, result, note, completed_at)
    VALUES (current_user, p_request_id, p_run_id, p_step_number, payload, result,
        canonical_note, completed_time);
    RETURN result;
END;
$$;

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA checklist_api FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA checklist_storage FROM PUBLIC;
NOTIFY pgrst, 'reload schema';
