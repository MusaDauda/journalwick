"""FastAPI application entry point."""

from __future__ import annotations

from fastapi import FastAPI

from journalwick import __version__
from journalwick.platform.health import router as health_router
from journalwick.platform.settings import get_settings

settings = get_settings()
is_production = settings.environment == "production"

app = FastAPI(
    title="Journalwick API",
    description="Exact multi-currency ledger and reconciliation API.",
    version=__version__,
    debug=False,
    docs_url=None if is_production else "/docs",
    redoc_url=None,
    openapi_url=None if is_production else "/api/v1/openapi.json",
)
app.include_router(health_router)
