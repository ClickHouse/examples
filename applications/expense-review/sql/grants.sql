GRANT SELECT ON expense_review.claims,expense_review.line_items,expense_review.decisions TO expense_review_app;
GRANT UPDATE(memo,status,revision) ON expense_review.claims TO expense_review_app;
GRANT INSERT,DELETE ON expense_review.line_items TO expense_review_app;
GRANT INSERT ON expense_review.decisions TO expense_review_app;
GRANT USAGE,SELECT ON SEQUENCE expense_review.decisions_id_seq TO expense_review_app;
