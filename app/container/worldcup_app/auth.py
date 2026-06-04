from __future__ import annotations

import dataclasses

from fastapi import HTTPException, Request

from worldcup_app.config import get_settings


@dataclasses.dataclass
class UserContext:
    user_id: str
    email: str | None = None


def get_user_context(request: Request) -> UserContext:
    """Extract user identity from SPCS ingress Sf-Context-Current-User header."""
    # SPCS sets this header when ingress authenticates the user via Snowflake SSO
    user = request.headers.get("sf-context-current-user")
    if not user:
        # Fallback: check x-forwarded-email (dev/proxy scenarios)
        user = request.headers.get("x-forwarded-email")
    if not user:
        raise HTTPException(status_code=401, detail="No user identity (Sf-Context-Current-User header missing)")

    user_id = user.strip().lower()
    # The header value is the Snowflake login name (typically an email)
    email = user_id if "@" in user_id else None
    return UserContext(user_id=user_id, email=email)


def is_admin(user: UserContext) -> bool:
    raw = (get_settings().admin_emails or "").strip()
    if not raw:
        return False
    admins = {e.strip().lower() for e in raw.split(",") if e.strip()}
    if user.email and user.email.lower() in admins:
        return True
    return user.user_id.lower() in admins
