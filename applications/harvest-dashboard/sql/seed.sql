\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE harvest_owner;
INSERT INTO harvest.crops (id,name) VALUES
 ('10000000-0000-4000-8000-000000000001','Tomatoes'),
 ('10000000-0000-4000-8000-000000000002','Courgettes'),
 ('10000000-0000-4000-8000-000000000003','Beans'),
 ('10000000-0000-4000-8000-000000000004','Carrots') ON CONFLICT DO NOTHING;
INSERT INTO harvest.beds (id,name) VALUES
 ('20000000-0000-4000-8000-000000000001','South raised bed'),
 ('20000000-0000-4000-8000-000000000002','Kitchen plot'),
 ('20000000-0000-4000-8000-000000000003','Greenhouse') ON CONFLICT DO NOTHING;
INSERT INTO harvest.entries (id,crop_id,bed_id,harvested_on,grams,note)
SELECT ('30000000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid,
 ('10000000-0000-4000-8000-' || lpad(crop::text,12,'0'))::uuid,
 ('20000000-0000-4000-8000-' || lpad(bed::text,12,'0'))::uuid, d::date, g, note
FROM (VALUES
 (1,1,3,'2026-09-02',720,'The first ripe greenhouse basket.'),
 (2,2,1,'2026-09-04',960,'Two courgettes for dinner.'),
 (3,3,2,'2026-09-06',380,'Tender beans from the kitchen plot.'),
 (4,1,3,'2026-09-07',1150,'Monday tomatoes.'),
 (5,4,1,'2026-09-09',640,'A small row of carrots.'),
 (6,2,1,'2026-09-12',1250,'Collected before the rain.'),
 (7,3,2,'2026-09-13',540,'Sunday beans.'),
 (8,1,3,'2026-09-14',1380,'Another Monday basket.'),
 (9,2,1,'2026-09-17',790,'Picked young.'),
 (10,4,1,'2026-09-19',870,'Carrots for soup.'),
 (11,3,2,'2026-09-20',610,'Beans at the end of the week.'),
 (12,1,3,'2026-09-21',1540,'Peak tomato week.'),
 (13,2,1,'2026-09-24',680,'The last large courgettes.'),
 (14,4,1,'2026-09-26',1020,'A full basket from the south bed.'),
 (15,3,2,'2026-09-27',430,'Sunday picking.'),
 (16,1,3,'2026-09-28',920,'A quieter greenhouse morning.')
) AS seed(n,crop,bed,d,g,note)
ON CONFLICT DO NOTHING;
COMMIT;
