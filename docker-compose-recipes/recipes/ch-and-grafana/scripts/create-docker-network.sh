#!/usr/bin/env bash

# run one off to create the network

docker network create \
  --driver=bridge \
  --subnet=172.51.0.0/16 \
  --ip-range=172.51.5.0/24 \
  --gateway=172.51.5.254 \
  ch-and-grafana