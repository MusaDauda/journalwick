"""FastAPI application entry point."""

from __future__ import annotations

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI

from journalwick import __version__
from journalwick.platform.database import create_api_pool
from journalwick.platform.health import router as health_router
from journalwick.platform.settings import get_settings

settings = get_settings()
is_production = settings.environment == "production"


@asynccontextmanager
async def lifespan(application: FastAPI) -> AsyncIterator[None]:
    pool = create_api_pool(settings)
    application.state.settings = settings
    application.state.database_pool = pool
    if pool is not None:
        await pool.open(wait=False)
    try:
        yield
    finally:
        if pool is not None:
            await pool.close(timeout=5.0)


app = FastAPI(
    title="Journalwick API",
    description="Exact multi-currency ledger and reconciliation API.",
    version=__version__,
    debug=False,
    docs_url=None if is_production else "/docs",
    redoc_url=None,
    openapi_url=None if is_production else "/api/v1/openapi.json",
    lifespan=lifespan,
)
app.include_router(health_router)
