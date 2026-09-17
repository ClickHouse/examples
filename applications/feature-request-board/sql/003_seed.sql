-- Run as the migration role. Stable IDs make this safe to repeat.
-- Demo identities cannot sign in; replace them only if you intend to own these rows.
\set ON_ERROR_STOP on
BEGIN;

INSERT INTO feature_board.feature_requests
  (id, title, description, author_id, author_name, status, created_at, updated_at)
VALUES
  ('10000000-0000-4000-8000-000000000001', 'Save custom views for recurring work',
   'Let us save a set of filters as a named view, so the team can return to the same list without setting it up every morning.',
   'demo_avery', 'Avery', 'OPEN', CURRENT_TIMESTAMP - INTERVAL '1 day', CURRENT_TIMESTAMP),
  ('10000000-0000-4000-8000-000000000002', 'Export a filtered list as CSV',
   'A CSV export would help us share a weekly snapshot with colleagues who do not need access to the whole workspace.',
   'demo_jordan', 'Jordan', 'PLANNED', CURRENT_TIMESTAMP - INTERVAL '2 days', CURRENT_TIMESTAMP),
  ('10000000-0000-4000-8000-000000000003', 'Make keyboard navigation feel complete',
   'Support moving between records and opening the selected item with the keyboard. Visible focus states would make this useful for everyone.',
   'demo_sam', 'Sam', 'IN_PROGRESS', CURRENT_TIMESTAMP - INTERVAL '3 days', CURRENT_TIMESTAMP),
  ('10000000-0000-4000-8000-000000000004', 'Remember the last selected workspace',
   'Take me back to the workspace I used most recently when I sign in, so I can pick up where I left off.',
   'demo_robin', 'Robin', 'SHIPPED', CURRENT_TIMESTAMP - INTERVAL '4 days', CURRENT_TIMESTAMP)
ON CONFLICT (id) DO NOTHING;

INSERT INTO feature_board.votes (request_id, user_id)
VALUES
  ('10000000-0000-4000-8000-000000000001', 'demo_jordan'),
  ('10000000-0000-4000-8000-000000000001', 'demo_sam'),
  ('10000000-0000-4000-8000-000000000002', 'demo_avery'),
  ('10000000-0000-4000-8000-000000000002', 'demo_sam'),
  ('10000000-0000-4000-8000-000000000002', 'demo_robin'),
  ('10000000-0000-4000-8000-000000000003', 'demo_avery')
ON CONFLICT (request_id, user_id) DO NOTHING;

COMMIT;
