#!/usr/bin/env bash

# run one off to create the network

docker network create \
  --driver=bridge \
  --subnet=192.168.1.0/24 \
  --gateway=192.168.1.254 \
  ch-and-grafana