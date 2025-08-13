UPDATE lineitem
SET l_extendedprice = 1111.11, l_tax = 0.06, l_linestatus = 'E', l_comment = 'Repricing event'
WHERE l_orderkey = 140916002 AND l_linenumber = 5;