UPDATE lineitem
SET l_discount = 0.045, l_tax = 0.11, l_extendedprice = 888.88, l_returnflag = 'X', l_linestatus = 'Z', l_shipmode = 'SHIP', l_comment = 'Corrected entry'
WHERE l_orderkey = 503437255 AND l_linenumber = 3;