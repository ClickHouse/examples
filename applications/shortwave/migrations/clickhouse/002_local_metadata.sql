-- LOCAL DEVELOPMENT ONLY. Cloud uses a ClickPipes-managed cdc_links table.
CREATE TABLE IF NOT EXISTS cdc_links (
  id UUID,
  account_id UUID,
  slug String,
  title String,
  tags Array(String),
  _peerdb_version UInt64,
  _peerdb_is_deleted UInt8
)
ENGINE = ReplacingMergeTree(_peerdb_version)
ORDER BY id;
