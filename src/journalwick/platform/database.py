"""Role-specific, bounded PostgreSQL connection pools."""

from __future__ import annotations

from psycopg import AsyncConnection
from psycopg_pool import AsyncConnectionPool

from journalwick.platform.errors import RuntimeConfigurationError
from journalwick.platform.settings import Settings

ApiPool = AsyncConnectionPool[AsyncConnection]


def create_api_pool(settings: Settings) -> ApiPool | None:
    """Create the API pool without opening a connection or exposing the DSN."""
    if settings.database_url is None:
        return None
    if settings.database_auth_mode == "rds_iam":
        raise RuntimeConfigurationError(
            "The managed PostgreSQL IAM connection adapter is not enabled in this build."
        )

    if settings.environment == "production":
        raise RuntimeConfigurationError("The production database connection is not configured.")

    return AsyncConnectionPool(
        conninfo=settings.database_url.get_secret_value(),
        connection_class=AsyncConnection,
        kwargs={
            "application_name": "journalwick-api",
            "connect_timeout": settings.database_connect_timeout_seconds,
        },
        min_size=settings.database_pool_min_size,
        max_size=settings.database_pool_max_size,
        max_waiting=settings.database_pool_max_waiting,
        timeout=settings.database_pool_timeout_seconds,
        max_idle=300,
        max_lifetime=1800,
        reconnect_timeout=30,
        open=False,
    )
