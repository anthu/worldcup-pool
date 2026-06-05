from __future__ import annotations

import logging
import os
import threading
from contextlib import contextmanager
from pathlib import Path
from typing import Generator

import snowflake.connector

logger = logging.getLogger(__name__)

_TOKEN_PATH = "/snowflake/session/token"

# Persistent connection cache — one connection per process, reused across requests
_conn_lock = threading.Lock()
_cached_conn: snowflake.connector.SnowflakeConnection | None = None


def _read_oauth_token() -> str:
    """Read the SPCS-injected OAuth token from the mounted volume."""
    path = os.environ.get("SNOWFLAKE_TOKEN_PATH", _TOKEN_PATH)
    return Path(path).read_text().strip()


def _new_connection() -> snowflake.connector.SnowflakeConnection:
    """Open a fresh Snowflake connection via SPCS OAuth."""
    from worldcup_app.config import get_settings
    settings = get_settings()
    token = _read_oauth_token()
    host = os.environ.get("SNOWFLAKE_HOST", f"{settings.snowflake_account}.snowflakecomputing.com")
    account = os.environ.get("SNOWFLAKE_ACCOUNT", settings.snowflake_account)
    return snowflake.connector.connect(
        host=host,
        account=account,
        authenticator="oauth",
        token=token,
        database=settings.snowflake_database,
        schema=settings.snowflake_schema,
        client_session_keep_alive=True,
    )


def get_connection() -> snowflake.connector.SnowflakeConnection:
    """Return the cached connection, reconnecting if stale or dead."""
    global _cached_conn
    with _conn_lock:
        if _cached_conn is None or _cached_conn.is_closed():
            logger.info("Opening new Snowflake connection")
            _cached_conn = _new_connection()
        else:
            # Refresh token on every request — SPCS rotates the file
            try:
                _cached_conn._rest._token = _read_oauth_token()
            except Exception:
                pass
        return _cached_conn


@contextmanager
def get_cursor() -> Generator[snowflake.connector.cursor.SnowflakeCursor, None, None]:
    """Context manager that yields a cursor, reconnecting on failure."""
    global _cached_conn
    conn = get_connection()
    try:
        cur = conn.cursor(snowflake.connector.DictCursor)
        try:
            yield cur
        finally:
            cur.close()
    except snowflake.connector.errors.DatabaseError:
        # Connection went stale — drop the cache and retry once
        logger.warning("Connection error, reconnecting...")
        with _conn_lock:
            _cached_conn = None
        conn = get_connection()
        cur = conn.cursor(snowflake.connector.DictCursor)
        try:
            yield cur
        finally:
            cur.close()

