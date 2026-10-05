BEGIN;
CREATE TABLE claims (
 id INTEGER PRIMARY KEY,
 employee TEXT NOT NULL,
 category TEXT NOT NULL CHECK(category IN ('Travel','Meals','Equipment','Training')),
 submitted_at TIMESTAMPTZ NOT NULL,
 status TEXT NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','approved','rejected')),
 revision INTEGER NOT NULL DEFAULT 0 CHECK(revision>=0),
 memo TEXT NOT NULL CHECK(length(memo) BETWEEN 3 AND 300)
);
CREATE TABLE line_items (
 claim_id INTEGER NOT NULL REFERENCES claims(id),
 position INTEGER NOT NULL CHECK(position BETWEEN 0 AND 7),
 description TEXT NOT NULL CHECK(length(description) BETWEEN 2 AND 80),
 amount_cents INTEGER NOT NULL CHECK(amount_cents BETWEEN 1 AND 10000000),
 PRIMARY KEY(claim_id,position)
);
CREATE TABLE decisions (
 id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 claim_id INTEGER NOT NULL REFERENCES claims(id),
 reviewed_revision INTEGER NOT NULL CHECK(reviewed_revision>=0),
 decision TEXT NOT NULL CHECK(decision IN ('approved','rejected')),
 reason TEXT NOT NULL CHECK(length(reason) BETWEEN 8 AND 300),
 total_cents INTEGER NOT NULL CHECK(total_cents>0),
 memo_snapshot TEXT NOT NULL CHECK(length(memo_snapshot) BETWEEN 3 AND 300),
 line_snapshot JSONB NOT NULL CHECK(jsonb_typeof(line_snapshot)='array'),
 decided_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
 UNIQUE(claim_id,reviewed_revision)
);
INSERT INTO claims(id,employee,category,submitted_at,memo)
SELECT n, (ARRAY['Morgan Reed','Ellis Park','Taylor Quinn','Casey Lane','Robin Wells','Avery Scott','Jamie Moss','Drew Hart'])[(n-1)%8+1],
 (ARRAY['Travel','Meals','Equipment','Training'])[(n-1)%4+1],
 TIMESTAMPTZ '2026-10-01T09:00:00Z' + ((n-1)%30)*INTERVAL '1 hour',
 (ARRAY['Client workshop travel','Project lunch with team','Replacement workshop supplies','Technical training materials'])[(n-1)%4+1] || ' — claim ' || n
FROM generate_series(1,500) AS n;
INSERT INTO line_items(claim_id,position,description,amount_cents)
SELECT id,0,'Main expense',1200+(id%40)*175 FROM claims
UNION ALL SELECT id,1,'Related expense',350+(id%15)*80 FROM claims;
COMMIT;
