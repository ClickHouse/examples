from .cluster import Cluster

def generate_cluster(args):
    c = Cluster(args)
    c.prepare()
    c.generate_obj()
    c.generate_docker_compose()
    c.generate_config()