-- Insert 20 billion rows into hits_100B table by cross joining hits_1B table
INSERT INTO `test.hits_100B`
SELECT t.*
FROM `test.hits_1B` AS t
CROSS JOIN UNNEST(GENERATE_ARRAY(1, 20));
