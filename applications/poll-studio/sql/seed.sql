\set ON_ERROR_STOP on
BEGIN;
SELECT NOT EXISTS (SELECT 1 FROM poll_studio.polls WHERE question = 'Which fictional workshop should we run?')
  AS seed_needed \gset
\if :seed_needed
INSERT INTO poll_studio.polls (question) VALUES ('Which fictional workshop should we run?')
  RETURNING id AS sample_poll_id \gset
INSERT INTO poll_studio.choices (poll_id, position, label) VALUES
  (:sample_poll_id, 1, 'Paper planets'),
  (:sample_poll_id, 2, 'Tiny gardens'),
  (:sample_poll_id, 3, 'Quiet circuits');
\endif
COMMIT;
