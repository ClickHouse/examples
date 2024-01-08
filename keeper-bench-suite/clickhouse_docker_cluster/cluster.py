import shutil
from pprint import pprint
from pathlib import Path
from jinja2 import Environment, FileSystemLoader


class Keeper:
    def __init__(
        self,
        hostname,
        version,
        server_id,
        cpu,
        memory,
        jvm_memory,
        keeper_port,
        keeper_port_external,
        keeper_raft_port,
        keeper_raft_port_external,
        keeper_prometheus_port,
        keeper_prometheus_port_external,
        # internal_replication,
        cluster_directory,
    ):
        self.hostname = hostname
        self.version = version
        self.server_id = server_id
        self.cpu = cpu
        self.memory = memory
        self.jvm_memory = jvm_memory
        self.keeper_port = keeper_port
        self.keeper_port_external = keeper_port_external
        self.keeper_raft_port = keeper_raft_port
        self.keeper_raft_port_external = keeper_raft_port_external
        self.keeper_prometheus_port = keeper_prometheus_port
        self.keeper_prometheus_port_external = keeper_prometheus_port_external
        # self.internal_replication = internal_replication
        self.config_directory = str(Path(cluster_directory) / "configs" / hostname)

    def __repr__(self):
        return str(self.__dict__)

    def prepare():
        return None


class Cluster:
    def __init__(self, args):
        # self.args = vars(args)
        self.args = args
        self._keepers = None
        self._chnodes = None

    def __repr__(self) -> str:
        x = ""
        for n in self._keepers + self._chnodes:
            x += str(n) + "\n"
        return x.strip()

    def generate_keeper_obj(self):
        keepers = []
        for count in range(1, self.args['keeper_count'] + 1):
            hostname = f"{self.args['keeper_prefix']}{count}"
            version = self.args['keeper_version']
            server_id = f"{count}"
            cpu = self.args['keeper_cpu']
            memory = self.args['keeper_memory']
            jvm_memory = self.args['keeper_jvm_memory']
            keeper_port = self.args['keeper_port']
            keeper_port_external = self.args['keeper_port'] + count - 1 + 10_000
            keeper_raft_port = self.args['keeper_raft_port']
            keeper_raft_port_external = self.args['keeper_raft_port'] + count - 1 + 10_000
            keeper_prometheus_port = self.args['keeper_prometheus_port']
            keeper_prometheus_port_external = (
                self.args['keeper_prometheus_port'] + count - 1 + 10_000
            )
            # internal_replication = self.args['keeper_internal_replication']
            cluster_directory = self.args['cluster_directory']
            k = Keeper(
                hostname,
                version,
                server_id,
                cpu,
                memory,
                jvm_memory,
                keeper_port,
                keeper_port_external,
                keeper_raft_port,
                keeper_raft_port_external,
                keeper_prometheus_port,
                keeper_prometheus_port_external,
                # internal_replication,
                cluster_directory,
            )
            keepers.append(k)
        return keepers

    def _delete_cluster_directory(self):
        """Delete cluster directories"""
        path = Path(self.args['cluster_directory'])
        if path.is_dir():
            shutil.rmtree(path)

    def _create_cluster_directory(self):
        """Create cluster directories"""
        Path(self.args['cluster_directory']).mkdir(parents=True, exist_ok=True)
        Path(f"{self.args['cluster_directory']}/configs").mkdir(
            parents=True, exist_ok=True
        )

    def prepare(self):
        """Delete and create cluster directory"""
        self._delete_cluster_directory()
        self._create_cluster_directory()

    def generate_obj(self):
        """Generate objects"""
        self._keepers = self.generate_keeper_obj()

    def objs_to_context(self):
        context = {
            "keeper_hostnames": [keeper.hostname for keeper in self._keepers],
            "keeper_versions": [keeper.version for keeper in self._keepers],
            "keeper_server_ids": [keeper.server_id for keeper in self._keepers],
            "keeper_cpus": [keeper.cpu for keeper in self._keepers],
            "keeper_memorys": [keeper.memory for keeper in self._keepers],
            "keeper_jvm_memorys": [keeper.jvm_memory for keeper in self._keepers],
            "keeper_ports_external": [
                keeper.keeper_port_external for keeper in self._keepers
            ],
            "keeper_prometheus_ports_external": [
                keeper.keeper_prometheus_port_external for keeper in self._keepers
            ],
            "keeper_config_directorys": [
                keeper.config_directory for keeper in self._keepers
            ],
        }
        return context

    def generate_docker_compose(self):
        """Generate docker compose file"""
        environment = Environment(
            loader=FileSystemLoader(f"{Path(__file__).parent}/templates/")
        )

        if self.args['shard'] == 0 or self.args['replica'] == 0:  # only keepers
            if self.args['keeper_type'] == "chkeeper":
                template = environment.get_template(
                    f"docker-compose-clickhousekeeper-only.yml.jinja"
                )
            elif self.args['keeper_type'] == "zookeeper":
                template = environment.get_template(
                    "docker-compose-zookeeper-only.yml.jinja"
                )
        else:  # CH with keepers
            if self.args['keeper_type'] == "chkeeper":
                template = environment.get_template(
                    f"docker-compose-clickhousekeeper.yml.jinja"
                )
            elif self.args['keeper_type'] == "zookeeper":
                template = environment.get_template(
                    "docker-compose-zookeeper.yml.jinja"
                )

        filename = f"{self.args['cluster_directory']}/docker-compose.yml"
        context = self.objs_to_context()

        content = template.render(context)
        with open(filename, mode="w", encoding="utf-8") as f:
            f.write(content)

    def generate_config(self):
        environment = Environment(
            loader=FileSystemLoader(f"{Path(__file__).parent}/templates/configs/")
        )

        context = (
            self.objs_to_context()
        )  # duplicated, to update - let's not generated twice
        keeper_hostnames = context["keeper_hostnames"]

        if self.args['keeper_type'] == "chkeeper":
            # [keeper+chnode] create configs directory using hostname
            for hostname in keeper_hostnames:
                Path(f"{self.args['cluster_directory']}/configs/{hostname}").mkdir(
                    parents=True, exist_ok=True
                )

            # [keeper+chnode] create prometheus directory
            Path(f"{self.args['cluster_directory']}/configs/prometheus").mkdir(
                parents=True, exist_ok=True
            )

            # [keeper+chnode] create grafana directory
            Path(f"{self.args['cluster_directory']}/configs/grafana").mkdir(
                parents=True, exist_ok=True
            )
            Path(f"{self.args['cluster_directory']}/configs/grafana/dashboards").mkdir(
                parents=True, exist_ok=True
            )

            # [keeper] keeper_config.xml
            template = environment.get_template("keeper_config.xml.jinja")

            for count, keeper_hostname in enumerate(keeper_hostnames):
                filename_generated = f"{self.args['cluster_directory']}/configs/{keeper_hostname}/keeper_config.xml"
                content = template.render(
                    context,
                    keeper_server_id=context["keeper_server_ids"][count],
                    keeper_port=self.args['keeper_port'],  # static port
                    keeper_raft_port=self.args['keeper_raft_port'],  # static port
                )
                with open(filename_generated, mode="w", encoding="utf-8") as f:
                    f.write(content)

def generate(args):
    c = Cluster(args)
    c.prepare()
    c.generate_obj()
    c.generate_docker_compose()
    c.generate_config()