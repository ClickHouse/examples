import os
import argparse
from pathlib import Path

def up(cluster_directory):
    """
    Start cluster
    """
    os.system(f"docker compose -f {cluster_directory}/docker-compose.yml up -d")


def clean():
    """
    Remove all containers and volumes related to the experiment
    """
    os.system("docker ps -aq --filter 'label=type=keeper_bench_suite' | xargs docker stop | xargs docker rm -v")
    os.system("docker volume ls --filter 'label=type=keeper_bench_suite' -q | xargs docker volume rm")
