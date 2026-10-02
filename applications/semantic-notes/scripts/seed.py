"""Add synthetic sample notes through the actual CPU encoder and restricted role."""

import json
from pathlib import Path

from semantic_notes.database import make_engine
from semantic_notes.embeddings import Encoder
from semantic_notes.service import create_note, verify_collection
from semantic_notes.validation import NoteInput


def main():
    encoder = Encoder()
    engine = make_engine()
    try:
        verify_collection(engine)
        for raw in json.loads(
            (Path(__file__).resolve().parent.parent / "samples/notes.json").read_text()
        ):
            fields = NoteInput.model_validate(raw)
            vector = encoder.embed(encoder.document_text(fields.title, fields.body))
            note = create_note(engine, fields, vector)
            print(note["id"], note["title"])
    finally:
        engine.dispose()


if __name__ == "__main__":
    main()
