########################################
##### Part 0 - get config
########################################
import os
import time
import yaml
import argparse
import itertools
from pathlib import Path

from run import start
from clickhouse_docker_cluster import cluster, docker_compose

try:
    with open(Path(__file__).resolve().parent /'config.yaml', 'r') as file:
        f = yaml.safe_load(file)
except Exception as e:
    raise e

# info
host_info = f['keeper']['host_info']
keeper_count = f['keeper']['keeper_count']
no_keeper_prometheus_metric = f['keeper']['no_keeper_prometheus_metric']

# experiment_config
num_repeat = range(f['experiment']['num_repeat'])
config_concurrency = f['experiment']['config_concurrency'] 
config_iterations = f['experiment']['config_iterations'] 
workload_file = f['experiment']['workload_file'] 
keeper_type = f['keeper']['keeper_type'] 
resource = f['keeper']['resource']

# generate combinations
combinations = []
for combination in itertools.product(num_repeat, config_concurrency, config_iterations, workload_file, keeper_type, resource):
    experiment_config = {}
    experiment_config['config_concurrency'] = combination[1]
    experiment_config['config_iterations'] = combination[2]
    experiment_config['workload_file'] = combination[3]
    experiment_config['keeper_type'] = combination[4]
    experiment_config['resource'] = combination[5]
    combinations.append(experiment_config)

########################################
##### Part 1 - experiment
########################################
for experiment_config in combinations[:10]:
    cluster_config = {}
    cluster_config['cluster_directory'] = Path(__file__).resolve().parent / 'docker_cluster' / 'cluster_1'
    cluster_config['shard'] = 0 # remove?
    cluster_config['replica'] = 0 # remove?
    cluster_config['keeper_type'] = experiment_config['keeper_type']
    cluster_config['keeper_count'] = keeper_count
    cluster_config['keeper_cpu'] = experiment_config['resource']['keeper_cpu']
    cluster_config['keeper_memory'] = experiment_config['resource']['keeper_memory']
    cluster_config['native_protocol_port'] = 9000
    cluster_config['http_api_port'] = 8123
    cluster_config['keeper_raft_port'] = 9234
    cluster_config['chnode_prefix'] = 'chnode'
    cluster_config['cluster_name'] = 'default'
    cluster_config['jinja_template_directory'] = 'default'
    cluster_config['keeper_extra_memory_percent'] = 20

    # values depend on keeper_type
    if cluster_config['keeper_type'] == "chkeeper":
        cluster_config['keeper_prefix'] = "chkeeper"
        cluster_config['keeper_port'] = 9181
        cluster_config['keeper_version'] = "23.8"
        cluster_config['keeper_prometheus_port'] = 9363
        cluster_config['keeper_jvm_memory'] = '0m'
    elif cluster_config['keeper_type'] == "zookeeper":
        cluster_config['keeper_prefix'] = "zookeeper"
        cluster_config['keeper_port'] = 2181
        cluster_config['keeper_version'] = "3.8"
        cluster_config['keeper_prometheus_port'] = 7000
        cluster_config['keeper_jvm_memory'] = cluster_config['keeper_memory']
        cluster_config['keeper_memory'] = f"{int(int(cluster_config['keeper_memory'][:-1]) * (cluster_config['keeper_extra_memory_percent'] + 100)/100)}m" 

    ########################################
    ##### Part 1.1 - create cluster
    ########################################
    docker_compose.clean()
    cluster.generate(cluster_config)
    docker_compose.up(cluster_config['cluster_directory'])

    # wait for cluster to be ready
    time.sleep(5)

    ########################################
    ##### Part 1.2 - benchmarking
    ########################################

    args = argparse.Namespace()
    args.keeper_type = experiment_config['keeper_type']
    args.keeper_count = keeper_count
    args.keeper_cpu = cluster_config['keeper_cpu']
    args.keeper_memory = cluster_config['keeper_memory']
    args.keeper_jvm_memory = cluster_config['keeper_jvm_memory']
    args.host_info = host_info
    args.config_concurrency = experiment_config['config_concurrency']
    args.config_iterations = experiment_config['config_iterations']
    args.workload_file = experiment_config['workload_file']
    args.no_keeper_prometheus_metric = no_keeper_prometheus_metric

    start(args)
    docker_compose.clean()