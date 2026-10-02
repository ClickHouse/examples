import unicodedata
from typing import Annotated

from pydantic import BaseModel, ConfigDict, Field, StringConstraints, field_validator

Title = Annotated[
    str,
    StringConstraints(strict=True, strip_whitespace=True, min_length=1, max_length=120),
]
Body = Annotated[
    str,
    StringConstraints(
        strict=True, strip_whitespace=True, min_length=1, max_length=4096
    ),
]


class NoteInput(BaseModel):
    model_config = ConfigDict(extra="forbid")
    title: Title
    body: Body

    @field_validator("title", "body", mode="before")
    @classmethod
    def controls(cls, value, info):
        if not isinstance(value, str):
            return value
        allowed = {"\n", "\t"} if info.field_name == "body" else set()
        if any(
            unicodedata.category(char) in {"Cc", "Cs"} and char not in allowed
            for char in value
        ):
            raise ValueError(
                "Controls and invalid Unicode are not allowed (body permits newline/tab)."
            )
        return value


class UpdateInput(NoteInput):
    revision: Annotated[int, Field(strict=True, ge=1, le=2147483646)]


class SearchInput(BaseModel):
    model_config = ConfigDict(extra="forbid")
    q: Annotated[
        str,
        StringConstraints(
            strict=True, strip_whitespace=True, min_length=1, max_length=512
        ),
    ]
    k: Annotated[int, Field(strict=True, ge=1, le=10)] = 5
    title_filter: Annotated[
        str, StringConstraints(strict=True, strip_whitespace=True, max_length=80)
    ] = ""

    @field_validator("q", "title_filter", mode="before")
    @classmethod
    def controls(cls, value):
        if not isinstance(value, str):
            return value
        if any(unicodedata.category(c) in {"Cc", "Cs"} for c in value):
            raise ValueError("Search cannot contain controls or invalid Unicode.")
        return value
