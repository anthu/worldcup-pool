from __future__ import annotations

import os
from contextlib import contextmanager
from pathlib import Path
from typing import Generator

import snowflake.connector


_TOKEN_PATH = "/snowflake/session/token"


def _read_oauth_token() -> str:
    """Read the SPCS-injected OAuth token from the mounted volume."""
    path = os.environ.get("SNOWFLAKE_TOKEN_PATH", _TOKEN_PATH)
    return Path(path).read_text().strip()


def get_connection() -> snowflake.connector.SnowflakeConnection:
    """Create a new Snowflake connection using SPCS OAuth authentication.
    
    In SPCS, the connection goes through the internal Snowflake host.
    The SNOWFLAKE_HOST env var is automatically set by SPCS, or we
    construct it from the account identifier.
    """
    from worldcup_app.config import get_settings

    settings = get_settings()
    token = _read_oauth_token()
    
    # SPCS injects SNOWFLAKE_HOST and SNOWFLAKE_ACCOUNT automatically
    host = os.environ.get("SNOWFLAKE_HOST", f"{settings.snowflake_account}.snowflakecomputing.com")
    account = os.environ.get("SNOWFLAKE_ACCOUNT", settings.snowflake_account)
    
    return snowflake.connector.connect(
        host=host,
        account=account,
        authenticator="oauth",
        token=token,
        database=settings.snowflake_database,
        schema=settings.snowflake_schema,
    )


@contextmanager
def get_cursor() -> Generator[snowflake.connector.cursor.SnowflakeCursor, None, None]:
    """Context manager that yields a cursor and handles connection lifecycle."""
    conn = get_connection()
    try:
        cur = conn.cursor(snowflake.connector.DictCursor)
        try:
            yield cur
        finally:
            cur.close()
    finally:
        conn.close()
