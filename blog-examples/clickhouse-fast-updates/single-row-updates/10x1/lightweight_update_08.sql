UPDATE lineitem
SET l_returnflag = 'A', l_shipinstruct = 'NONE', l_comment = 'Legacy return policy'
WHERE l_orderkey = 349980483 AND l_linenumber = 1;