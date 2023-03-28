#!/usr/bin/env bash


find  fs/volumes/ -type f -name "*.log" | xargs tail -n10 -F