#!/usr/bin/env bash

# run one off to create the network

docker network create \
  --driver=bridge \
  --subnet=192.168.8.0/24 \
  --gateway=192.168.8.254 \
  cluster_2S_2R