INSERT INTO playlist_api.accounts(id) VALUES('00000000-0000-4000-8000-000000000001'),('00000000-0000-4000-8000-000000000002') ON CONFLICT DO NOTHING;
INSERT INTO playlist_api.tracks(id,title,artist,duration_seconds)
SELECT ('10000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'Synthetic Track '||n,'Example Ensemble',90+n FROM generate_series(1,60) AS n ON CONFLICT DO NOTHING;
