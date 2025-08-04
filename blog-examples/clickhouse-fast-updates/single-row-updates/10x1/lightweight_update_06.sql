UPDATE lineitem
SET l_shipinstruct = 'COLLECT COD', l_returnflag = 'P', l_comment = 'Priority order'
WHERE l_orderkey = 343206944 AND l_linenumber = 1;