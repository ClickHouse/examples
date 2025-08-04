ALTER TABLE lineitem
UPDATE l_comment = 'Preferred supplier', l_discount = 0.02
WHERE l_orderkey = 596681795 AND l_linenumber = 6;