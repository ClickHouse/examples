import secrets
from typing import Annotated
from uuid import UUID

from fastapi import Depends, HTTPException, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

bearer = HTTPBearer(
    auto_error=False,
    description="An attendee token configured on the server in API_BEARER_TOKENS.",
)


def get_attendee_id(
    request: Request,
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)],
) -> UUID:
    candidate = credentials.credentials if credentials else ""
    matched = None
    # Compare every configured token rather than exposing a match's position.
    for attendee_id, token in request.app.state.settings.bearer_tokens.items():
        if secrets.compare_digest(candidate.encode(), token.encode()):
            matched = attendee_id
    if matched is None:
        raise HTTPException(
            status_code=401,
            detail="A valid attendee bearer token is required.",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return matched
