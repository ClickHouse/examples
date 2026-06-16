#!/usr/bin/env python3
"""chDB equivalent of the CLI conversion: read a .npy file and write CSV, in-process.
Run ./generate.sh first to create ./data/signal.npy.
Mirrors run.ipynb cell-for-cell."""
import os
import chdb

os.chdir(os.path.join(os.path.dirname(__file__), "data"))

# 1. Convert a 1D .npy to .csv in one process, no server.
chdb.query(
    "SELECT * FROM file('signal.npy') "
    "INTO OUTFILE 'signal_chdb.csv' TRUNCATE FORMAT CSVWithNames"
)
with open("signal_chdb.csv") as f:
    print(f.read().strip())

# 2. Or get the CSV straight back as a string, no file at all.
print(chdb.query("SELECT * FROM file('signal.npy') LIMIT 3 FORMAT CSV", "CSV"))
