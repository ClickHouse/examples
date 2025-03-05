#!/bin/sh 

DOCKER="docker"

$DOCKER compose pull
$DOCKER compose -f docker-compose.yaml up --no-attach catalog --no-attach temporal --no-attach temporal-ui --no-attach temporal-admin-tools
