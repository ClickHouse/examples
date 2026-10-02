\set ON_ERROR_STOP on
INSERT INTO expenses.expense (
    id, owner_id, description, amount, currency, status, version,
    created_at, updated_at, submitted_at
)
VALUES
    ('00000000-0000-0000-0000-000000000001', 'employee-a', 'Notebook',
     12.34, 'GBP', 'DRAFT', 0, now(), now(), NULL),
    ('00000000-0000-0000-0000-000000000002', 'employee-b', 'Train ticket',
     45.60, 'GBP', 'SUBMITTED', 0, now(), now(), now())
ON CONFLICT (id) DO NOTHING;
