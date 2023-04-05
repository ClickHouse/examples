#!/usr/bin/env bash

# run one off to create the network

docker network create \
  --driver=bridge \
  --subnet=192.168.3.0/24 \
  --gateway=192.168.3.254 \
  ch-and-openldap