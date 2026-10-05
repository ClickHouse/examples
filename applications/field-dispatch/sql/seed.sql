\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE dispatch_owner;
INSERT INTO dispatch.areas (id,name,color,boundary) VALUES
  ('20000000-0000-4000-8000-000000000001','West garden','#648662',
   public.ST_GeomFromText('POLYGON((-1.495 53.345,-1.465 53.345,-1.465 53.379,-1.495 53.379,-1.495 53.345))',4326)),
  ('20000000-0000-4000-8000-000000000002','Riverside','#46858d',
   public.ST_GeomFromText('POLYGON((-1.465 53.345,-1.435 53.345,-1.435 53.379,-1.465 53.379,-1.465 53.345))',4326)),
  ('20000000-0000-4000-8000-000000000003','North common','#b28544',
   public.ST_GeomFromText('POLYGON((-1.49 53.376,-1.44 53.376,-1.44 53.402,-1.49 53.402,-1.49 53.376))',4326))
ON CONFLICT (id) DO NOTHING;
INSERT INTO dispatch.teams (id,name,area_id,depot) VALUES
  ('30000000-0000-4000-8000-000000000001','Garden crew','20000000-0000-4000-8000-000000000001',public.ST_SetSRID(public.ST_MakePoint(-1.482,53.36),4326)),
  ('30000000-0000-4000-8000-000000000002','River crew','20000000-0000-4000-8000-000000000002',public.ST_SetSRID(public.ST_MakePoint(-1.451,53.354),4326)),
  ('30000000-0000-4000-8000-000000000003','Common crew','20000000-0000-4000-8000-000000000003',public.ST_SetSRID(public.ST_MakePoint(-1.469,53.392),4326))
ON CONFLICT (id) DO NOTHING;
INSERT INTO dispatch.jobs (id,code,title,priority,geom) VALUES
  ('40000000-0000-4000-8000-000000000001','FD-001','Repair garden gate','urgent',
   public.ST_SetSRID(public.ST_MakePoint(-1.481,53.361),4326)),
  ('40000000-0000-4000-8000-000000000002','FD-002','Clear riverside drain','urgent',
   public.ST_SetSRID(public.ST_MakePoint(-1.448,53.36),4326)),
  ('40000000-0000-4000-8000-000000000003','FD-003','Replace path light','routine',
   public.ST_SetSRID(public.ST_MakePoint(-1.467,53.391),4326)),
  ('40000000-0000-4000-8000-000000000004','FD-004','Inspect common bench','routine',
   public.ST_SetSRID(public.ST_MakePoint(-1.475,53.377),4326)),
  ('40000000-0000-4000-8000-000000000005','FD-005','Repair play-area fence','routine',
   public.ST_SetSRID(public.ST_MakePoint(-1.486,53.352),4326)),
  ('40000000-0000-4000-8000-000000000006','FD-006','Clear fallen branch','urgent',
   public.ST_SetSRID(public.ST_MakePoint(-1.442,53.373),4326)),
  ('40000000-0000-4000-8000-000000000007','FD-007','Fix fountain valve','routine',
   public.ST_SetSRID(public.ST_MakePoint(-1.478,53.367),4326)),
  ('40000000-0000-4000-8000-000000000008','FD-008','Reset crossing bollard','routine',
   public.ST_SetSRID(public.ST_MakePoint(-1.452,53.367),4326)),
  ('40000000-0000-4000-8000-000000000009','FD-009','Replace notice board','routine',
   public.ST_SetSRID(public.ST_MakePoint(-1.482,53.389),4326)),
  ('40000000-0000-4000-8000-000000000010','FD-010','Collect damaged bin','urgent',
   public.ST_SetSRID(public.ST_MakePoint(-1.462,53.381),4326)),
  ('40000000-0000-4000-8000-000000000011','FD-011','Repair picnic table','routine',
   public.ST_SetSRID(public.ST_MakePoint(-1.473,53.356),4326)),
  ('40000000-0000-4000-8000-000000000012','FD-012','Clear footbridge debris','routine',
   public.ST_SetSRID(public.ST_MakePoint(-1.454,53.353),4326)),
  ('40000000-0000-4000-8000-000000000013','FD-013','Inspect gravel path','routine',
   public.ST_SetSRID(public.ST_MakePoint(-1.449,53.393),4326)),
  ('40000000-0000-4000-8000-000000000014','FD-014','Replace bike rack','routine',
   public.ST_SetSRID(public.ST_MakePoint(-1.49,53.373),4326)),
  ('40000000-0000-4000-8000-000000000015','FD-015','Repair allotment tap','routine',
   public.ST_SetSRID(public.ST_MakePoint(-1.479,53.398),4326)),
  ('40000000-0000-4000-8000-000000000016','FD-016','Clear blocked culvert','urgent',
   public.ST_SetSRID(public.ST_MakePoint(-1.44,53.382),4326)),
  ('40000000-0000-4000-8000-000000000017','FD-017','Inspect boundary sign','routine',
   public.ST_SetSRID(public.ST_MakePoint(-1.501,53.375),4326)),
  ('40000000-0000-4000-8000-000000000018','FD-018','Repair orchard fence','routine',
   public.ST_SetSRID(public.ST_MakePoint(-1.501,53.39),4326))
ON CONFLICT (id) DO NOTHING;
INSERT INTO dispatch.map_state (id,longitude,latitude,zoom,area_id,mode)
VALUES ('dispatch',-1.467,53.373,13,'20000000-0000-4000-8000-000000000001','assignments')
ON CONFLICT (id) DO NOTHING;
COMMIT;
