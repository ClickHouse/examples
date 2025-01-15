#!/bin/bash

curl https://clickhouse.com/ | sh
sudo ./clickhouse install --noninteractive
sudo clickhouse start

while true
do
    clickhouse-client --query "SELECT 1" && break
    sleep 1
done

