GRANT USAGE ON SCHEMA experiment_log TO experiment_app;
GRANT SELECT ON experiment_log.projects,experiment_log.runs,experiment_log.measurements TO experiment_app;
GRANT INSERT(id,project_id,request_id,title,config,request_payload) ON experiment_log.runs TO experiment_app;
GRANT INSERT(project_id,run_id,name,value) ON experiment_log.measurements TO experiment_app;
