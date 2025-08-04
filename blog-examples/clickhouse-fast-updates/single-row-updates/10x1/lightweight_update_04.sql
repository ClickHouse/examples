UPDATE lineitem
SET l_extendedprice = 654.32, l_linestatus = 'W', l_shipmode = 'FOB', l_comment = 'Warranty extension'
WHERE l_orderkey = 198133573 AND l_linenumber = 5;