ALTER TABLE lineitem
UPDATE l_discount = 0.02, l_tax = 0.07, l_extendedprice = 321.99, l_returnflag = 'R', l_linestatus = 'Y', l_shipinstruct = 'NONE', l_comment = 'Return-flagged batch'
WHERE l_orderkey = 400574597 AND l_linenumber = 7;