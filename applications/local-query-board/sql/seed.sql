BEGIN;
INSERT INTO planning.projects VALUES
('10000000-0000-4000-8000-000000000001','studio','Website','#5686d8'),
('10000000-0000-4000-8000-000000000002','studio','Launch','#de8054'),
('10000000-0000-4000-8000-000000000003','studio','Research','#7f9866'),
('10000000-0000-4000-8000-000000000099','private-lab','Hidden project','#999999');
INSERT INTO planning.tasks(id,board_id,project_id,title,status,priority) VALUES
('20000000-0000-4000-8000-000000000001','studio','10000000-0000-4000-8000-000000000001','Review the homepage copy','doing','high'),
('20000000-0000-4000-8000-000000000002','studio','10000000-0000-4000-8000-000000000001','Simplify the signup journey','todo','medium'),
('20000000-0000-4000-8000-000000000003','studio','10000000-0000-4000-8000-000000000002','Prepare the launch checklist','doing','high'),
('20000000-0000-4000-8000-000000000004','studio','10000000-0000-4000-8000-000000000003','Summarize interview findings','done','medium'),
('20000000-0000-4000-8000-000000000005','studio','10000000-0000-4000-8000-000000000002','Draft the announcement','todo','low'),
('20000000-0000-4000-8000-000000000099','private-lab','10000000-0000-4000-8000-000000000099','Private laboratory task','todo','high');
COMMIT;
