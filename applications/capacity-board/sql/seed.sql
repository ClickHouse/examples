\set ON_ERROR_STOP on
BEGIN;
SELECT pg_advisory_xact_lock(7311002);
DO $seed$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM capacity_board.boards WHERE id = '11111111-1111-4111-8111-111111111111') THEN
        INSERT INTO capacity_board.boards(id,title,capacity) VALUES
            ('11111111-1111-4111-8111-111111111111','Workshop sprint',30);
        INSERT INTO capacity_board.work_items(board_id,id,position,name,points) VALUES
            ('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222',0,'Prepare the demo',5),
            ('11111111-1111-4111-8111-111111111111','33333333-3333-4333-8333-333333333333',1,'Review the guide',3),
            ('11111111-1111-4111-8111-111111111111','44444444-4444-4444-8444-444444444444',2,'Record the walkthrough',1);
    END IF;
END
$seed$;
COMMIT;
