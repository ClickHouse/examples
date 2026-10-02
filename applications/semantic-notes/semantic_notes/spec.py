import json
from pathlib import Path

MODEL_ID = "sentence-transformers/all-MiniLM-L6-v2"
MODEL_REVISION = "1110a243fdf4706b3f48f1d95db1a4f5529b4d41"
DIMENSIONS = 384
MAX_TOKENS = 256
SPEC = {
    "model_id": MODEL_ID,
    "revision": MODEL_REVISION,
    "dimensions": DIMENSIONS,
    "max_tokens_including_special": MAX_TOKENS,
    "normalize_embeddings": True,
    "dtype": "float32",
    "document_format": "title + two newlines + body",
}


def check_source_spec():
    actual = json.loads(
        (Path(__file__).resolve().parent.parent / "model-spec.json").read_text()
    )
    if actual != SPEC:
        raise ValueError(
            "The complete fixed model specification must match this collection."
        )
