CREATE DATABASE demo_db;

\c demo_db

CREATE TABLE IF NOT EXISTS demo_table1 (
  id SERIAL PRIMARY KEY,
  message VARCHAR(255)
);

CREATE TABLE IF NOT EXISTS demo_table2 (
  id SERIAL PRIMARY KEY,
  message VARCHAR(255)
);

ALTER TABLE demo_table1 REPLICA IDENTITY FULL;
ALTER TABLE demo_table2 REPLICA IDENTITY FULL;

INSERT INTO demo_table1(message) VALUES ('demo1 message1');
INSERT INTO demo_table1(message) VALUES ('demo1 message2');
INSERT INTO demo_table2(message) VALUES ('demo2 message1');
INSERT INTO demo_table2(message) VALUES ('demo2 message2');
