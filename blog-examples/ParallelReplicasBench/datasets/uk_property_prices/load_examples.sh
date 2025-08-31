#!/bin/bash
set -euo pipefail

# 1 billion rows → database: uk_b1
./load_data.sh 1000000000

# 10 billion rows → database: uk_b10
./load_data.sh 10000000000

# 30 billion rows → database: uk_b30
./load_data.sh 30000000000

# 50 billion rows → database: uk_b50
./load_data.sh 50000000000

# 100 billion rows → database: uk_b100
./load_data.sh 100000000000

# 1 trillion rows → database: uk_t1
./load_data.sh 1000000000000