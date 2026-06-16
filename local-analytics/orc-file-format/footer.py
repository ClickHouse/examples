#!/usr/bin/env python3
# Crack the ORC footer with a standard ORC reader (pyarrow).
# ClickHouse reads ORC data natively but has no ORC-metadata FORMAT,
# so we use pyarrow.orc to expose the file's internal structure.
import sys
import pyarrow.orc as orc

path = sys.argv[1] if len(sys.argv) > 1 else "data/events.orc"
f = orc.ORCFile(path)

print(f"rows:             {f.nrows}")
print(f"stripes:          {f.nstripes}")
print(f"row_index_stride: {f.row_index_stride}")
print(f"row_index_groups: {f.nrows // f.row_index_stride}")
print(f"compression:      {f.compression}")
print(f"compression_block:{f.compression_size} bytes")
print(f"writer:           {f.writer}")
print(f"file_version:     {f.file_version}")
print(f"content_length:   {f.content_length} bytes (stripe data)")
print(f"footer_length:    {f.file_footer_length} bytes")
print(f"postscript_length:{f.file_postscript_length} bytes")
print(f"file_length:      {f.file_length} bytes total")
print()
print("schema:")
print(f.schema)
