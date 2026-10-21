| Format | Columns | Query elapsed ms, median (range) | Process wall ms | Process CPU ms | Peak RSS MiB | CH tracked peak MiB | File read bytes, separate trace |
|---|---|---|---:|---:|---:|---:|---:|
| Avro | two | 228 (215–237) | 258.7 | 267.2 | 239.6 | 8.1 | 70,484,749 |
| Avro | all | 349 (340–360) | 381.3 | 393.6 | 270.2 | 50.0 | 70,484,749 |
| Parquet | two | 8 (7–8) | 38.5 | 42.4 | 244.3 | 9.1 | 2,986,857 |
| Parquet | all | 99 (97–112) | 130.0 | 188.1 | 310.2 | 122.1 | 55,178,653 |
