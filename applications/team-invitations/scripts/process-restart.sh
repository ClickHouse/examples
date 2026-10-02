#!/usr/bin/env bash
set -euo pipefail
: "${TEST_RESTART_FIXTURE:?Set the private fixture produced by cloud.py}"
: "${TEST_EVIDENCE_DIR:?Set a directory outside the repository}"
python3 checks/restart.py
