"""Typed, environment-only runtime settings with secrets kept out of repr output."""

from __future__ import annotations

from functools import lru_cache
from typing import Literal

from pydantic import SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Settings accepted by the API and worker processes."""

    model_config = SettingsConfigDict(
        env_prefix="JOURNALWICK_",
        case_sensitive=False,
        extra="ignore",
        env_file=None,
    )

    environment: Literal["development", "test", "production"] = "development"
    process_role: Literal["api", "worker", "migrator", "reporter", "recovery"] = "api"
    database_url: SecretStr | None = None
    database_auth_mode: Literal["dsn", "rds_iam"] = "dsn"
    public_origin: str = "http://localhost:5203"
    webauthn_rp_id: str = "localhost"
    provider_mode: Literal["fixture", "sandbox"] = "fixture"
    key_provider: Literal["ephemeral_fixture", "aws_kms"] = "ephemeral_fixture"
    api_host: str = "127.0.0.1"
    api_port: int = 8003
    database_pool_min_size: int = 1
    database_pool_max_size: int = 8


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    """Return the immutable process settings read from the environment."""
    return Settings()
