SELECT concat(
  toString((SELECT groupArray((id, displayname)) FROM
    (SELECT id, displayname FROM stackoverflow.users FINAL WHERE _peerdb_is_deleted = 0 ORDER BY id))), '|',
  toString((SELECT count() FROM stackoverflow.posts FINAL WHERE _peerdb_is_deleted = 0)), '|',
  toString((SELECT count() FROM stackoverflow.votes FINAL WHERE _peerdb_is_deleted = 0)), '|',
  toString((SELECT count() FROM stackoverflow.comments FINAL WHERE _peerdb_is_deleted = 0))) AS state
