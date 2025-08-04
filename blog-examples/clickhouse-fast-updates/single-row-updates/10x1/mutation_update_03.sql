ALTER TABLE lineitem
UPDATE l_extendedprice = 777.77, l_returnflag = 'S', l_linestatus = 'N', l_tax = 0.02
WHERE l_orderkey = 431195557 AND l_linenumber = 3;