#!/bin/bash
set -e
echo "[*] Resetting PostgreSQL to clean snapshot"
sudo systemctl stop postgresql
sudo rsync -a --delete /var/lib/postgresql/17/clean_snapshot/ /var/lib/postgresql/17/main/
sudo systemctl start postgresql
echo "[*] Done. PostgreSQL is reset to clean state."