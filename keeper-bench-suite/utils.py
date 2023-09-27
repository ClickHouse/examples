import os
import uuid
import hashlib
import clickhouse_connect
from pathlib import Path
from jinja2 import Environment, FileSystemLoader

def get_clickhouse_connect_client():
    """
    client for clickhouse_connect
    """
    from dotenv import load_dotenv

    load_dotenv()
    HOST = os.getenv("clickhouse_host")
    USERNAME = os.getenv("clickhouse_username")
    PASSWORD = os.getenv("clickhouse_password")
    PORT = os.getenv("clickhouse_port")

    return clickhouse_connect.get_client(host=HOST, port=PORT, username=USERNAME, password=PASSWORD, secure=True)

def create_keeper_bench_config(args):
    """
    Add additional configs
    """
    if args.keeper_type == "chkeeper":
        keeper_ports = [str(19181 + x) for x in range(args.keeper_count)]
    elif args.keeper_type == "zookeeper":
        keeper_ports = [str(12181 + x) for x in range(args.keeper_count)]
    
    keeper_bench_config = {
        "num_connections": args.keeper_count,
        "keeper_type": args.keeper_type,
        "keeper_ports": keeper_ports,
    }
    keeper_bench_config.update(vars(args))
    return keeper_bench_config

def generate_keeper_bench_yaml(keeper_bench_config):
    """
    1. Get configuration
    2. Refer to a template and generate keeper bench yaml
    """
    # Environment
    environment = Environment(loader=FileSystemLoader(f"{Path(__file__).parent}/keeper-bench-config-template/"))

    template = environment.get_template(keeper_bench_config['workload_file'])

    # Generate yaml file
    content = template.render(keeper_bench_config)
    filename_generated = (
        f"{Path(__file__).resolve().parent}/keeper-bench-config/benchmark.yaml"
    )
    print("filename_generated: " + filename_generated)
    with open(filename_generated, mode="w", encoding="utf-8") as f:
        f.write(content)

def get_experiment_id(keeper_bench_config):
    """
    experiment_id is the same if they have the same value for:
        - host_info
        - keeper_count
        - keeper_cpu
        - keeper_memory
        - keeeper_jvm_memory
        - config_concurrency
        - config_iterations
        - workload_file
    """
    _ = {
        "host_info": keeper_bench_config['host_info'],
        "keeper_count": keeper_bench_config['keeper_count'],
        "keeper_cpu": keeper_bench_config['keeper_cpu'],
        "keeper_memory": keeper_bench_config['keeper_memory'],
        "keeeper_jvm_memory": keeper_bench_config['keeper_jvm_memory'],
        "config_concurrency": keeper_bench_config['config_concurrency'],
        "config_iterations": keeper_bench_config['config_iterations'],
        "workload_file": keeper_bench_config['workload_file'],
    }

    _hash = hashlib.sha256(str(_).encode("utf-8"))
    return str(uuid.UUID(_hash.hexdigest()[::2]))


