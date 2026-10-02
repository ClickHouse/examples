"""Download the exact public CPU model once; no database is needed."""

import argparse
import json
import time
from importlib.metadata import version

import numpy as np

from semantic_notes.embeddings import MODEL_ID, MODEL_REVISION, Encoder, TokenLimitError

parser = argparse.ArgumentParser()
parser.add_argument("--download", action="store_true")
args = parser.parse_args()
start = time.monotonic()
encoder = Encoder(download=args.download)
texts = [
    "Postgres row locks protect concurrent updates to the same record.",
    "Locking a database row coordinates competing edits.",
    "The garden needs watering before the tomatoes ripen.",
]
vectors = [encoder.embed(text) for text in texts]
assert all(
    v.shape == (384,) and np.isfinite(v).all() and np.linalg.norm(v) > 0
    for v in vectors
)
related = float(np.dot(vectors[0], vectors[1]))
unrelated = float(np.dot(vectors[0], vectors[2]))
assert related > unrelated
assert encoder.token_count("hello " * 254) == 256
encoder.embed("hello " * 254)
assert encoder.token_count("hello " * 255) == 257
try:
    encoder.embed("hello " * 255)
except TokenLimitError:
    pass
else:
    raise AssertionError("257-token input must be rejected before silent truncation")
print(
    json.dumps(
        {
            "model": MODEL_ID,
            "revision": MODEL_REVISION,
            "cpu": str(encoder.model.device),
            "safetensors": True,
            "remote_custom_code": False,
            "dimensions": 384,
            "finite_nonzero": True,
            "inclusive_token_boundary": [256, 257],
            "related_fixture_cosine": related,
            "unrelated_fixture_cosine": unrelated,
            "mode": "cold-download" if args.download else "cached-only",
            "elapsed_seconds_observed_not_benchmark": round(
                time.monotonic() - start, 3
            ),
            "versions": {
                p: version(p)
                for p in [
                    "torch",
                    "sentence-transformers",
                    "transformers",
                    "sqlmodel",
                    "SQLAlchemy",
                    "fastapi",
                    "psycopg",
                    "pgvector",
                ]
            },
        },
        indent=2,
    )
)
