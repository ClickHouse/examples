bq show --format=prettyjson test.hits \
  | jq '{
      table: .tableReference.tableId,
      numRows: (.numRows|tonumber),
      numActiveLogicalBytes: (.numActiveLogicalBytes|tonumber),
      numActivePhysicalBytes: (.numActivePhysicalBytes|tonumber),
      numLongTermLogicalBytes: (.numLongTermLogicalBytes|tonumber),
      numLongTermPhysicalBytes: (.numLongTermPhysicalBytes|tonumber)
    }'