#!/bin/bash

set -eu

# Load data: wrap TRUNCATE and \copy FREEZE in a single transaction
# If we dont' do this, Postgres will throw an error:
#     "ERROR: cannot perform COPY FREEZE because the table was not created or truncated in the current subtransaction"
# (i.e. Postgres requires that the table be either created or truncated in the current subtransaction)
sudo -u postgres psql bench <<'EOF'
BEGIN;
TRUNCATE TABLE lineitem;
\copy "lineitem" from '/tmp/lineitem.tbl' DELIMITER '|' CSV;
COMMIT;
EOF

sudo -u postgres psql bench -t -c 'VACUUM ANALYZE lineitem'