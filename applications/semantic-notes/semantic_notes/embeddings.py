"""Fixed CPU encoder. Model/tokenizer work happens before database acquisition."""

from __future__ import annotations

import os
import threading
from pathlib import Path

import numpy as np
import torch
from huggingface_hub import snapshot_download
from sentence_transformers import SentenceTransformer

from .spec import DIMENSIONS, MAX_TOKENS, MODEL_ID, MODEL_REVISION, check_source_spec

MODEL_FILES = [
    "modules.json",
    "config.json",
    "config_sentence_transformers.json",
    "sentence_bert_config.json",
    "special_tokens_map.json",
    "tokenizer.json",
    "tokenizer_config.json",
    "vocab.txt",
    "1_Pooling/config.json",
    "model.safetensors",
]


class TokenLimitError(ValueError):
    pass


def checked_vector(value: object) -> np.ndarray:
    vector = np.asarray(value, dtype=np.float32)
    if vector.shape != (DIMENSIONS,) or not np.isfinite(vector).all():
        raise ValueError("Embedding must have exactly 384 finite dimensions.")
    norm = float(np.linalg.norm(vector))
    if not np.isfinite(norm) or norm <= 0:
        raise ValueError("Embedding must be nonzero with a finite norm.")
    return vector


class Encoder:
    def __init__(self, *, download: bool = False):
        check_source_spec()
        if (
            os.getenv("MODEL_ID", MODEL_ID) != MODEL_ID
            or os.getenv("MODEL_REVISION", MODEL_REVISION) != MODEL_REVISION
        ):
            raise ValueError(
                "This collection requires its fixed model ID and revision."
            )
        torch.set_num_threads(1)
        self._lock = threading.Lock()
        self.path = snapshot_download(
            MODEL_ID,
            revision=MODEL_REVISION,
            token=False,
            cache_dir=os.getenv("MODEL_CACHE_DIR"),
            allow_patterns=MODEL_FILES,
            local_files_only=not download,
        )
        self.model = SentenceTransformer(
            self.path,
            device="cpu",
            trust_remote_code=False,
            local_files_only=True,
            model_kwargs={"use_safetensors": True},
        )
        if (
            self.model.get_embedding_dimension() != DIMENSIONS
            or self.model.max_seq_length != MAX_TOKENS
        ):
            raise ValueError(
                "Cached model shape/token specification does not match the collection."
            )
        if not (Path(self.path) / "model.safetensors").is_file():
            raise ValueError("Pinned safetensors weights are required.")

    def token_count(self, text: str) -> int:
        return len(
            self.model.tokenizer(text, add_special_tokens=True, truncation=False)[
                "input_ids"
            ]
        )

    def embed(self, text: str) -> np.ndarray:
        # SentenceTransformer.encode changes module/device state; serialize shared-model access.
        # HTTP admission is separately bounded and rejects excess work instead of queuing jobs.
        with self._lock:
            count = self.token_count(text)
            if count > MAX_TOKENS:
                raise TokenLimitError(
                    f"Input contains {count} tokens; limit is 256 including special tokens."
                )
            value = self.model.encode(
                text,
                convert_to_numpy=True,
                normalize_embeddings=True,
                show_progress_bar=False,
            )
            return checked_vector(value)

    @staticmethod
    def document_text(title: str, body: str) -> str:
        return title + "\n\n" + body
