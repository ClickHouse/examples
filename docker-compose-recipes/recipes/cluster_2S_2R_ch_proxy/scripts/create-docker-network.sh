#!/usr/bin/env bash

# run one off to create the network

docker network create \
  --driver=bridge \
  --subnet=172.28.0.0/16 \
  --ip-range=172.28.5.0/24 \
  --gateway=172.28.5.254 \
  network_cluster_2S_2R