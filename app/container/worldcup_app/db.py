from __future__ import annotations

import logging
import os
import threading
from contextlib import contextmanager
from pathlib import Path
from typing import Generator

import snowflake.connector
from snowflake.connector.errors import DatabaseError, HttpError

logger = logging.getLogger(__name__)

_TOKEN_PATH = "/snowflake/session/token"

# Persistent connection cache
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


def _get_or_create_conn() -> snowflake.connector.SnowflakeConnection:
    """Return cached connection, creating one if needed."""
    global _cached_conn
    with _conn_lock:
        if _cached_conn is None or _cached_conn.is_closed():
            logger.info("Opening new Snowflake connection")
            _cached_conn = _new_connection()
        return _cached_conn


def _reset_conn() -> snowflake.connector.SnowflakeConnection:
    """Force-reset the cached connection and return a fresh one."""
    global _cached_conn
    with _conn_lock:
        logger.info("Resetting Snowflake connection")
        try:
            if _cached_conn and not _cached_conn.is_closed():
                _cached_conn.close()
        except Exception:
            pass
        _cached_conn = _new_connection()
        return _cached_conn


@contextmanager
def get_cursor() -> Generator[snowflake.connector.cursor.SnowflakeCursor, None, None]:
    """Yield a cursor, reconnecting automatically on 401/session errors."""
    conn = _get_or_create_conn()
    try:
        cur = conn.cursor(snowflake.connector.DictCursor)
        try:
            yield cur
        finally:
            cur.close()
    except (DatabaseError, HttpError) as exc:
        # 401 or session expired — reconnect with fresh token and retry once
        err_str = str(exc)
        if "401" in err_str or "290401" in err_str or "session" in err_str.lower():
            logger.warning("Session expired (401), reconnecting with fresh token: %s", err_str)
            conn = _reset_conn()
            cur = conn.cursor(snowflake.connector.DictCursor)
            try:
                yield cur
            finally:
                cur.close()
        else:
            raise


# Public alias kept for backward compat
def get_connection() -> snowflake.connector.SnowflakeConnection:
    return _get_or_create_conn()

