#!/usr/bin/env bash
set -e

if [ "$1" = '/opt/mssql/bin/sqlservr' ]; then
  # If this is the container's first run, initialize the application database
  if [ ! -f /tmp/init_done ]; then
    function init_db() {
      sleep 10
      # get script from https://learn.microsoft.com/en-us/sql/samples/adventureworks-install-configure?view=sql-server-ver16&tabs=ssms#creation-scripts
      wget -O /tmp/adventureworks-oltp-install-script.zip https://github.com/Microsoft/sql-server-samples/releases/download/adventureworks/AdventureWorks-oltp-install-script.zip

      mkdir /usr/src/app/adventureworks-oltp-install-script
      unzip /tmp/adventureworks-oltp-install-script.zip -d /usr/src/app/adventureworks-oltp-install-script
      /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P mssqlpassword_123 -d master -i /usr/src/app/adventureworks-oltp-install-script/instawdb.sql

      #mark init done
      touch /tmp/init_done
    }
    init_db &
  fi
fi

exec "$@"
