"""Process liveness only; database readiness is added with the DB lifecycle."""

from __future__ import annotations

from typing import Literal, cast

from fastapi import APIRouter, Request, Response, status
from psycopg import Error as PsycopgError
from psycopg_pool import PoolTimeout
from pydantic import BaseModel

from journalwick.migrations.manifest import MIGRATION_IDS, REQUIRED_KERNEL_FUNCTIONS
from journalwick.platform.database import ApiPool
from journalwick.platform.settings import Settings, get_settings
from journalwick.platform.unit_of_work import unit_of_work

ReadinessCode = Literal[
    "DATABASE_NOT_CONFIGURED",
    "DATABASE_UNAVAILABLE",
    "SCHEMA_NOT_INITIALIZED",
    "SCHEMA_INCOMPLETE",
    "KERNEL_INTERFACE_INCOMPLETE",
]


class LivenessResponse(BaseModel):
    status: Literal["alive"] = "alive"
    service: Literal["journalwick"] = "journalwick"


class ReadinessResponse(BaseModel):
    status: Literal["ready", "not_ready"]
    database: Literal["available", "unavailable", "not_configured"]
    schema_state: Literal["compatible", "incomplete", "not_initialized", "unavailable"]
    code: ReadinessCode | None = None


router = APIRouter(prefix="/api/v1/health", tags=["health"])


@router.get("/live")
async def liveness() -> LivenessResponse:
    """Report that the HTTP process can serve requests, not that the DB is ready."""
    return LivenessResponse()


@router.get("/ready")
async def readiness(request: Request, response: Response) -> ReadinessResponse:
    """Check database reachability and the complete migration/kernel interface."""
    settings = cast(Settings, getattr(request.app.state, "settings", get_settings()))
    pool = cast(ApiPool | None, getattr(request.app.state, "database_pool", None))

    def not_ready(
        *,
        database: Literal["available", "unavailable", "not_configured"],
        schema_state: Literal["incomplete", "not_initialized", "unavailable"],
        code: ReadinessCode,
    ) -> ReadinessResponse:
        response.status_code = status.HTTP_503_SERVICE_UNAVAILABLE
        return ReadinessResponse(
            status="not_ready",
            database=database,
            schema_state=schema_state,
            code=code,
        )

    if pool is None:
        return not_ready(
            database="not_configured",
            schema_state="not_initialized",
            code="DATABASE_NOT_CONFIGURED",
        )

    try:
        async with unit_of_work(
            pool,
            timeout_seconds=settings.database_pool_timeout_seconds,
        ) as connection:
            cursor = await connection.execute(
                "SELECT to_regclass(%s)::text",
                ("jw.schema_migrations",),
            )
            relation_row = await cursor.fetchone()
            if relation_row is None or relation_row[0] is None:
                return not_ready(
                    database="available",
                    schema_state="not_initialized",
                    code="SCHEMA_NOT_INITIALIZED",
                )

            cursor = await connection.execute("SELECT migration_id FROM jw.schema_migrations")
            applied_rows = await cursor.fetchall()
            applied_migrations = {str(row[0]) for row in applied_rows if row}
            if any(migration_id not in applied_migrations for migration_id in MIGRATION_IDS):
                return not_ready(
                    database="available",
                    schema_state="incomplete",
                    code="SCHEMA_INCOMPLETE",
                )

            cursor = await connection.execute(
                """
                SELECT p.proname
                FROM pg_catalog.pg_proc AS p
                JOIN pg_catalog.pg_namespace AS n ON n.oid = p.pronamespace
                WHERE n.nspname = %s AND p.proname = ANY(%s)
                """,
                ("jw_api", list(REQUIRED_KERNEL_FUNCTIONS)),
            )
            function_rows = await cursor.fetchall()
            available_functions = {str(row[0]) for row in function_rows if row}
            missing_functions = [
                function_name
                for function_name in REQUIRED_KERNEL_FUNCTIONS
                if function_name not in available_functions
            ]
            if missing_functions:
                return not_ready(
                    database="available",
                    schema_state="incomplete",
                    code="KERNEL_INTERFACE_INCOMPLETE",
                )
    except (PsycopgError, PoolTimeout):
        return not_ready(
            database="unavailable",
            schema_state="unavailable",
            code="DATABASE_UNAVAILABLE",
        )

    response.status_code = status.HTTP_200_OK
    return ReadinessResponse(
        status="ready",
        database="available",
        schema_state="compatible",
    )
