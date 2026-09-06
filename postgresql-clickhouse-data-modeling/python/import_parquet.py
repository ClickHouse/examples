"""Optional large Stack Overflow import; run in the recipe's loader container."""
from contextlib import closing
from pathlib import Path
import sys
from urllib.request import urlopen

import psycopg2
from psycopg2 import sql
import pyarrow as pa
import pyarrow.csv as csv
import pyarrow.parquet as parquet

datasets = {
    "posts": [
        "https://datasets-documentation.s3.eu-west-3.amazonaws.com/stackoverflow/parquet/posts/2023.parquet",
        "https://datasets-documentation.s3.eu-west-3.amazonaws.com/stackoverflow/parquet/posts/2024.parquet"
    ],
    "votes": [
        "https://datasets-documentation.s3.eu-west-3.amazonaws.com/stackoverflow/parquet/votes/2023.parquet",
        "https://datasets-documentation.s3.eu-west-3.amazonaws.com/stackoverflow/parquet/votes/2024.parquet"
    ],
    "comments": [
        "https://datasets-documentation.s3.eu-west-3.amazonaws.com/stackoverflow/parquet/comments/2023.parquet",
        "https://datasets-documentation.s3.eu-west-3.amazonaws.com/stackoverflow/parquet/comments/2024.parquet"
    ],
    "users": [
        "https://datasets-documentation.s3.eu-west-3.amazonaws.com/stackoverflow/parquet/users.parquet"
    ]
}


def download_parquet(url, output_path):
    """Publish a complete download only; HTTP and transport errors propagate."""
    partial = output_path.with_suffix(output_path.suffix + ".part")
    try:
        print(f"Downloading {url}", flush=True)
        with urlopen(url, timeout=60) as response, partial.open("wb") as output:
            while chunk := response.read(1024 * 1024):
                output.write(chunk)
        partial.replace(output_path)
    finally:
        partial.unlink(missing_ok=True)


def import_file(conn, table, path, batch_size):
    """Bound memory by Arrow batches and keep COPY headers/column order explicit."""
    count = 0
    with parquet.ParquetFile(path) as source, conn.cursor() as cursor:
        for batch in source.iter_batches(batch_size=batch_size):
            columns = sql.SQL(", ").join(sql.Identifier(name.lower()) for name in batch.schema.names)
            statement = sql.SQL("COPY {} ({}) FROM STDIN WITH (FORMAT CSV, HEADER TRUE)").format(
                sql.Identifier(table), columns
            )
            buffer = pa.BufferOutputStream()
            # Every COPY receives its own header, including the second and later batches.
            csv.write_csv(batch, buffer, write_options=csv.WriteOptions(include_header=True))
            with pa.BufferReader(buffer.getvalue()) as stream:
                cursor.copy_expert(statement.as_string(conn), stream)
            count += batch.num_rows
        cursor.execute(
            sql.SQL("SELECT setval(pg_get_serial_sequence(%s, 'id'), COALESCE(max(id), 1), count(*) > 0) FROM {}").format(sql.Identifier(table)),
            (table,),
        )
    return count


def main():
    if len(sys.argv) != 7:
        raise SystemExit("Usage: import_parquet.py <database> <user> <password> <host> <port> <batch_size>")
    database, user, password, host, port, batch_size = sys.argv[1:]
    batch_size = int(batch_size)
    if batch_size < 1:
        raise SystemExit("batch_size must be positive")
    cache = Path("data")
    cache.mkdir(exist_ok=True)
    with closing(psycopg2.connect(dbname=database, user=user, password=password,
                                host=host, port=port, connect_timeout=10)) as conn:
        for table, urls in datasets.items():
            for url in urls:
                path = cache / (table + "-" + url.rsplit("/", 1)[-1])
                download_parquet(url, path)
                # Roll back the current file and stop on any COPY error; never report false success.
                with conn:
                    count = import_file(conn, table, path, batch_size)
                path.unlink()
                print(f"Imported {count} rows into {table}", flush=True)
    print("All imports completed successfully!")


if __name__ == "__main__":
    main()
