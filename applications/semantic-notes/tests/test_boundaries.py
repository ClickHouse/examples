import json
import unittest
from unittest.mock import patch

import numpy as np
from pydantic import ValidationError

from semantic_notes.embeddings import checked_vector
from semantic_notes.spec import SPEC, check_source_spec
from semantic_notes.validation import NoteInput, SearchInput, UpdateInput


class Boundaries(unittest.TestCase):
    def test_vector_rejects_wrong_shape_zero_and_nonfinite_values(self):
        for value in [
            np.ones(383),
            np.zeros(384),
            np.full(384, np.nan),
            np.full(384, np.inf),
        ]:
            with self.assertRaises(ValueError):
                checked_vector(value)
        self.assertEqual(checked_vector(np.ones(384)).dtype, np.float32)

    def test_revision_requires_integer_not_bool_or_coerced_string(self):
        for value in [True, "1", 0, 2147483647]:
            with self.assertRaises(ValidationError):
                UpdateInput(title="Title", body="Body", revision=value)

    def test_unicode_controls_and_unknown_fields_are_rejected(self):
        for title in ["Bad\x7f", "Bad\u0085", "Bad\ud800"]:
            with self.assertRaises(ValidationError):
                NoteInput(title=title, body="Body")
        with self.assertRaises(ValidationError):
            NoteInput(title="Title", body="Body", model="other")
        with self.assertRaises(ValidationError):
            SearchInput(q="Bad\ud800")
        self.assertEqual(NoteInput(title=" T ", body="Line one\nLine two").title, "T")

    def test_search_bounds_and_collection_format_are_fixed(self):
        for values in [
            {"q": ""},
            {"q": "x", "k": 11},
            {"q": "x", "title_filter": "x" * 81},
        ]:
            with self.assertRaises(ValidationError):
                SearchInput(**values)
        for key, value in [
            ("document_format", "body only"),
            ("dtype", "float64"),
            ("normalize_embeddings", False),
        ]:
            with patch(
                "pathlib.Path.read_text", return_value=json.dumps({**SPEC, key: value})
            ):
                with self.assertRaises(ValueError):
                    check_source_spec()
