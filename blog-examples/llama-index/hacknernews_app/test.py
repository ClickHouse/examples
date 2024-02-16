import clickhouse_connect
from llama_index.vector_stores.clickhouse import ClickHouseVectorStore

username = "default"
password = "s2nf.qI2UwGKl"
host = "w60d4cvz06.eu-central-1.aws.clickhouse.cloud"
native_port = 9440
http_port = 8443
secure = True
database = "default"
hackernews_table = "hackernews_llama"
stackoverflow_table = "surveys"

client = clickhouse_connect.get_client(
        host=host, port=http_port, username=username, password=password,
        secure=secure, settings={"max_parallel_replicas": "3", "use_hedged_requests": "0",
                                 "allow_experimental_parallel_reading_from_replicas": "1"}
    )

vector_store = ClickHouseVectorStore(clickhouse_client=client, table=hackernews_table)