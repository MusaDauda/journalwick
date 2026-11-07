"""Typed, environment-only runtime settings with secrets kept out of repr output."""

from __future__ import annotations

import os
from functools import lru_cache
from typing import Literal
from urllib.parse import urlsplit

from pydantic import Field, SecretStr, model_validator
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
    api_port: int = Field(default=8003, ge=1, le=65535)
    database_pool_min_size: int = Field(default=1, ge=1, le=10)
    database_pool_max_size: int = Field(default=10, ge=1, le=10)
    database_pool_max_waiting: int = Field(default=32, ge=0, le=100)
    database_pool_timeout_seconds: float = Field(default=2.0, gt=0, le=30)
    database_connect_timeout_seconds: int = Field(default=2, ge=1, le=10)
    database_statement_timeout_ms: int = Field(default=5_000, ge=100, le=60_000)
    database_lock_timeout_ms: int = Field(default=2_000, ge=50, le=15_000)

    @model_validator(mode="after")
    def validate_configuration(self) -> Settings:
        known_keys = {
            f"JOURNALWICK_{field_name}".upper()
            for field_name in self.__class__.model_fields
        }
        unknown_keys = sorted(
            name
            for name in os.environ
            if name.upper().startswith("JOURNALWICK_") and name.upper() not in known_keys
        )
        if unknown_keys:
            raise ValueError(f"Unknown Journalwick setting: {unknown_keys[0]}")

        if self.database_pool_max_size < self.database_pool_min_size:
            raise ValueError("The database pool maximum must be at least its minimum.")

        origin = urlsplit(self.public_origin)
        if not origin.scheme or not origin.hostname:
            raise ValueError("The configured public origin must be an absolute HTTP URL.")
        if origin.username or origin.password or origin.query or origin.fragment:
            raise ValueError("The public origin cannot contain credentials or URL parameters.")

        if self.environment == "production":
            if origin.scheme != "https":
                raise ValueError("Production requires an HTTPS public origin.")
            if self.webauthn_rp_id != origin.hostname:
                raise ValueError("The production relying-party ID must match the public hostname.")
            if self.database_auth_mode != "rds_iam":
                raise ValueError(
                    "Production requires the managed database IAM authentication mode."
                )
            if self.database_url is not None:
                raise ValueError(
                    "Production database connection details must use typed host settings."
                )
            if self.key_provider != "aws_kms":
                raise ValueError("Production cannot use an ephemeral encryption key provider.")

        return self


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    """Return the immutable process settings read from the environment."""
    return Settings()
