#!/usr/bin/env python3
"""chDB equivalent of the NPY -> Parquet conversion in the article.
Run ./generate.sh first to create ./data/readings.npy and ./data/embeddings.npy.
Same SQL as the CLI, in-process, no server."""
import os
import chdb

os.chdir(os.path.join(os.path.dirname(__file__), "data"))

# 1. Convert NPY -> Parquet, renaming the always-named `array` column.
chdb.query(
    "SELECT array AS reading FROM file('readings.npy') "
    "INTO OUTFILE 'readings_chdb.parquet' TRUNCATE FORMAT Parquet"
)
print("wrote readings_chdb.parquet")
print(chdb.query("DESCRIBE file('readings_chdb.parquet')", "CSV"), end="")

# 2. Convert the 2D matrix, keeping each row vector as an Array column.
chdb.query(
    "SELECT array AS embedding FROM file('embeddings.npy') "
    "INTO OUTFILE 'embeddings_chdb.parquet' TRUNCATE FORMAT Parquet"
)
print(
    chdb.query(
        "SELECT count() AS rows, length(any(embedding)) AS dims "
        "FROM file('embeddings_chdb.parquet')",
        "CSV",
    ),
    end="",
)
