CREATE INDEX expense_owner_created ON expenses.expense (owner_id, created_at DESC);
CREATE INDEX expense_status_created ON expenses.expense (status, created_at DESC);
