ALTER TABLE lineitem
UPDATE l_discount = 0.015, l_tax = 0.03, l_extendedprice = 432.10, l_returnflag = 'B', l_linestatus = 'X', l_comment = 'Adjusted manually'
WHERE l_orderkey = 522639521 AND l_linenumber = 3;