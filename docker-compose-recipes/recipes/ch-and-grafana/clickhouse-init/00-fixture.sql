-- Three invented orders: the provisioned panel must display 45.
CREATE TABLE default.events (id UInt32, city String, amount UInt32)
ENGINE = MergeTree ORDER BY id;
INSERT INTO default.events VALUES (1, 'London', 10), (2, 'London', 20), (3, 'Paris', 15);
CREATE USER grafana_reader IDENTIFIED WITH sha256_password BY 'local-reader-password';
GRANT SELECT ON default.events TO grafana_reader;
