\set ON_ERROR_STOP on
GRANT USAGE ON SCHEMA capacity_board TO capacity_app;
GRANT SELECT ON capacity_board.boards, capacity_board.work_items, capacity_board.saves TO capacity_app;
GRANT UPDATE (revision) ON capacity_board.boards TO capacity_app;
GRANT INSERT, DELETE ON capacity_board.work_items TO capacity_app;
GRANT INSERT ON capacity_board.saves TO capacity_app;
