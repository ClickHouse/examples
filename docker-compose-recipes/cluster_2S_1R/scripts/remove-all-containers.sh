#!/usr/bin/env bash


docker ps -a |awk {'print $12'} | xargs docker rm