"""Explicit transaction scope for one local database command."""

from __future__ import annotations

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from psycopg import AsyncConnection

from journalwick.platform.database import ApiPool


@asynccontextmanager
async def unit_of_work(
    pool: ApiPool,
    *,
    timeout_seconds: float,
) -> AsyncIterator[AsyncConnection]:
    """Borrow one pooled connection; the pool context commits or rolls back as a unit."""
    async with pool.connection(timeout=timeout_seconds) as connection:
        yield connection
