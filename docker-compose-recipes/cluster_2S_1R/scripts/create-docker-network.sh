#!/usr/bin/env bash

# run one off to create the network

docker network create \
  --driver=bridge \
  --subnet=172.30.0.0/16 \
  --ip-range=172.30.5.0/24 \
  --gateway=172.30.5.254 \
  network_cluster_2S_1R