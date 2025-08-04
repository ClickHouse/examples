ALTER TABLE lineitem
UPDATE l_comment = 'Backfill historical', l_discount = 0.01, l_tax = 0.09
WHERE l_orderkey = 93311302 AND l_linenumber = 2;