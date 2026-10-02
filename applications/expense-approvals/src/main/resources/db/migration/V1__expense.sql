CREATE TABLE expenses.expense (
    id uuid PRIMARY KEY,
    owner_id varchar(64) NOT NULL,
    description varchar(300) NOT NULL CHECK (length(btrim(description)) > 0),
    amount numeric(8,2) NOT NULL CHECK (amount > 0 AND amount <= 100000.00),
    currency varchar(3) NOT NULL CHECK (currency = 'GBP'),
    status varchar(16) NOT NULL CHECK (status IN ('DRAFT', 'SUBMITTED', 'APPROVED', 'REJECTED')),
    version bigint NOT NULL DEFAULT 0 CHECK (version >= 0),
    created_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL,
    submitted_at timestamptz,
    decided_at timestamptz,
    decided_by varchar(64),
    decision_note varchar(500),
    CHECK ((status = 'DRAFT') = (submitted_at IS NULL)),
    CHECK (
        (status IN ('APPROVED', 'REJECTED') AND decided_at IS NOT NULL AND decided_by IS NOT NULL)
        OR (status IN ('DRAFT', 'SUBMITTED') AND decided_at IS NULL AND decided_by IS NULL)
    ),
    CHECK (decided_by IS NULL OR decided_by <> owner_id),
    CHECK (status <> 'REJECTED' OR (decision_note IS NOT NULL AND length(btrim(decision_note)) > 0))
);
