#!/bin/bash

echo "[*] Taking snapshot of PostgreSQL data"
echo "[*] Stopping PostgreSQL"
sudo systemctl stop postgresql
echo "[*] Taking snapshot"
sudo mkdir -p /var/lib/postgresql/17/clean_snapshot
sudo rsync -a --delete /var/lib/postgresql/17/main/ /var/lib/postgresql/17/clean_snapshot/
echo "[*] Starting PostgreSQL"
sudo systemctl start postgresql
echo "[*] Done. PostgreSQL snapshot is taken."