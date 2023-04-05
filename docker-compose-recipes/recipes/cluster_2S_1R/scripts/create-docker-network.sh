#!/usr/bin/env bash

# run one off to create the network

docker network create \
  --driver=bridge \
  --subnet=192.168.6.0/24 \
  --gateway=192.168.6.254 \
  cluster_2S_1R