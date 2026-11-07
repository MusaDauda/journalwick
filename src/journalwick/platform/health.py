"""Process liveness only; database readiness is added with the DB lifecycle."""

from __future__ import annotations

from typing import Literal

from fastapi import APIRouter
from pydantic import BaseModel


class LivenessResponse(BaseModel):
    status: Literal["alive"] = "alive"
    service: Literal["journalwick"] = "journalwick"


router = APIRouter(prefix="/api/v1/health", tags=["health"])


@router.get("/live")
async def liveness() -> LivenessResponse:
    """Report that the HTTP process can serve requests, not that the DB is ready."""
    return LivenessResponse()
