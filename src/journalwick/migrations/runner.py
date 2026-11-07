"""Checksum-checked SQL migrations with one transaction per migration."""

from __future__ import annotations

import hashlib
import re
import subprocess
from collections.abc import Iterator
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from typing import Literal

import psycopg
from psycopg import Connection
from psycopg import Error as PsycopgError

from journalwick import __version__
from journalwick.migrations.manifest import MIGRATION_IDS
from journalwick.platform.settings import Settings

_MIGRATION_FILE = re.compile(r"^(\d{4}_[a-z0-9_]+)\.sql$")
_MAX_MIGRATION_BYTES = 5_000_000
_MIGRATION_LOCK = (19_031, 1)


class MigrationRunnerError(RuntimeError):
    """A safe, stable failure from migration discovery or execution."""

    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code
        self.message = message


@dataclass(frozen=True, slots=True)
class Migration:
    migration_id: str
    path: Path
    sql: str
    checksum: bytes


@dataclass(frozen=True, slots=True)
class AppliedMigration:
    checksum: bytes
    applied_at: datetime


@dataclass(frozen=True, slots=True)
class MigrationStatus:
    migration_id: str
    state: Literal["applied", "pending", "not_authored"]
    source_checksum: str | None
    applied_at: datetime | None


def default_migrations_directory() -> Path:
    """Find the repository migration directory for editable and image installs."""
    candidates = (
        Path.cwd() / "migrations",
        Path(__file__).resolve().parents[3] / "migrations",
    )
    for candidate in candidates:
        if candidate.is_dir():
            return candidate.resolve()
    raise MigrationRunnerError("MIGRATIONS_NOT_FOUND", "The SQL migration directory is missing.")


def discover_migrations(directory: Path | None = None) -> tuple[Migration, ...]:
    """Load a contiguous, size-bounded prefix of the reviewed migration series."""
    migration_directory = directory or default_migrations_directory()
    if not migration_directory.is_dir():
        raise MigrationRunnerError(
            "MIGRATIONS_NOT_FOUND",
            "The SQL migration directory is missing.",
        )

    migrations: list[Migration] = []
    for path in sorted(migration_directory.glob("*.sql")):
        match = _MIGRATION_FILE.fullmatch(path.name)
        if match is None:
            raise MigrationRunnerError(
                "MIGRATION_FILENAME_INVALID",
                "A SQL migration filename does not match the released naming convention.",
            )

        migration_id = match.group(1)
        if migration_id not in MIGRATION_IDS:
            raise MigrationRunnerError(
                "MIGRATION_UNKNOWN",
                f"Migration {migration_id} is not part of the reviewed baseline.",
            )

        try:
            raw_sql = path.read_bytes()
        except OSError:
            raise MigrationRunnerError(
                "MIGRATION_READ_FAILED",
                f"Migration {migration_id} could not be read.",
            ) from None
        if not raw_sql or len(raw_sql) > _MAX_MIGRATION_BYTES:
            raise MigrationRunnerError(
                "MIGRATION_SIZE_INVALID",
                f"Migration {migration_id} is empty or exceeds the local size bound.",
            )
        try:
            sql = raw_sql.decode("utf-8")
        except UnicodeDecodeError:
            raise MigrationRunnerError(
                "MIGRATION_ENCODING_INVALID",
                f"Migration {migration_id} is not valid UTF-8.",
            ) from None

        migrations.append(
            Migration(
                migration_id=migration_id,
                path=path,
                sql=sql,
                checksum=hashlib.sha256(raw_sql).digest(),
            )
        )

    if not migrations:
        raise MigrationRunnerError("MIGRATIONS_NOT_FOUND", "No SQL migrations are available.")

    discovered_ids = tuple(migration.migration_id for migration in migrations)
    if discovered_ids != MIGRATION_IDS[: len(discovered_ids)]:
        raise MigrationRunnerError(
            "MIGRATION_SEQUENCE_GAP",
            "Available SQL migrations must form a contiguous prefix of the baseline.",
        )
    return tuple(migrations)


def _database_url(settings: Settings) -> str:
    if settings.database_url is None:
        raise MigrationRunnerError(
            "DATABASE_NOT_CONFIGURED",
            "Set JOURNALWICK_DATABASE_URL to the approved migration connection profile.",
        )
    if settings.database_auth_mode != "dsn":
        raise MigrationRunnerError(
            "DATABASE_AUTH_MODE_UNSUPPORTED",
            "This migration runner currently supports only the local DSN profile.",
        )
    return settings.database_url.get_secret_value()


@contextmanager
def _migration_connection(settings: Settings) -> Iterator[Connection[tuple[object, ...]]]:
    try:
        connection: Connection[tuple[object, ...]] = psycopg.connect(
            _database_url(settings),
            autocommit=True,
            connect_timeout=settings.database_connect_timeout_seconds,
            application_name="journalwick-migrator",
        )
    except PsycopgError:
        raise MigrationRunnerError(
            "DATABASE_UNAVAILABLE",
            "The migration database connection could not be established.",
        ) from None

    lock_acquired = False
    role_selected = False
    try:
        session_user = connection.execute("SELECT session_user").fetchone()
        if session_user is None or session_user[0] != "journalwick_migrator":
            raise MigrationRunnerError(
                "MIGRATOR_IDENTITY_REQUIRED",
                "Database migrations must connect as journalwick_migrator.",
            )

        connection.execute("SELECT pg_advisory_lock(%s, %s)", _MIGRATION_LOCK)
        lock_acquired = True
        try:
            connection.execute("SET ROLE journalwick_kernel_owner")
        except PsycopgError:
            raise MigrationRunnerError(
                "KERNEL_OWNER_ROLE_UNAVAILABLE",
                "The migrator cannot assume the protected kernel-owner role.",
            ) from None
        role_selected = True
        try:
            yield connection
        except MigrationRunnerError:
            raise
        except PsycopgError as error:
            sqlstate = error.sqlstate or "unknown"
            raise MigrationRunnerError(
                "DATABASE_ERROR",
                f"The migration database operation failed (SQLSTATE {sqlstate}).",
            ) from None
    finally:
        try:
            if role_selected:
                connection.execute("RESET ROLE")
            if lock_acquired:
                connection.execute("SELECT pg_advisory_unlock(%s, %s)", _MIGRATION_LOCK)
        except PsycopgError:
            pass
        finally:
            connection.close()


def _read_applied(
    connection: Connection[tuple[object, ...]],
) -> dict[str, AppliedMigration]:
    exists_row = connection.execute(
        "SELECT to_regclass(%s)::text",
        ("jw.schema_migrations",),
    ).fetchone()
    if exists_row is None or exists_row[0] is None:
        return {}

    rows = connection.execute(
        """
        SELECT migration_id, checksum, applied_at
        FROM jw.schema_migrations
        ORDER BY migration_id
        """
    ).fetchall()
    applied: dict[str, AppliedMigration] = {}
    for row in rows:
        migration_id = row[0]
        checksum = row[1]
        applied_at = row[2]
        if (
            not isinstance(migration_id, str)
            or not isinstance(checksum, (bytes, bytearray, memoryview))
            or len(checksum) != 32
            or not isinstance(applied_at, datetime)
        ):
            raise MigrationRunnerError(
                "MIGRATION_LEDGER_INVALID",
                "The migration ledger contains a malformed record.",
            )
        if migration_id in applied:
            raise MigrationRunnerError(
                "MIGRATION_LEDGER_INVALID",
                "The migration ledger contains a duplicate identifier.",
            )
        applied[migration_id] = AppliedMigration(
            checksum=bytes(checksum),
            applied_at=applied_at,
        )
    return applied


def _validate_history(
    applied: dict[str, AppliedMigration],
    migrations: tuple[Migration, ...],
) -> None:
    source_by_id = {migration.migration_id: migration for migration in migrations}
    for migration_id, record in applied.items():
        if migration_id not in MIGRATION_IDS:
            raise MigrationRunnerError(
                "MIGRATION_LEDGER_INVALID",
                f"The database contains an unknown migration: {migration_id}.",
            )
        source = source_by_id.get(migration_id)
        if source is None:
            raise MigrationRunnerError(
                "MIGRATION_SOURCE_MISSING",
                f"Applied migration {migration_id} is not present in this source tree.",
            )
        if record.checksum != source.checksum:
            raise MigrationRunnerError(
                "MIGRATION_CHECKSUM_MISMATCH",
                f"Applied migration {migration_id} differs from the recorded checksum.",
            )

    applied_ids = set(applied)
    for index, migration_id in enumerate(MIGRATION_IDS):
        if migration_id in applied_ids and any(
            earlier_id not in applied_ids for earlier_id in MIGRATION_IDS[:index]
        ):
            raise MigrationRunnerError(
                "MIGRATION_HISTORY_GAP",
                "The applied migration history is not a contiguous baseline prefix.",
            )


def _source_revision(migrations_directory: Path) -> str:
    project_directory = migrations_directory.parent
    try:
        status = subprocess.run(
            ["git", "status", "--porcelain"],
            cwd=project_directory,
            check=False,
            capture_output=True,
            text=True,
        )
    except OSError:
        return "working-tree"
    if status.returncode != 0 or status.stdout.strip():
        return "working-tree"

    try:
        revision = subprocess.run(
            ["git", "rev-parse", "--verify", "HEAD"],
            cwd=project_directory,
            check=False,
            capture_output=True,
            text=True,
        )
    except OSError:
        return "working-tree"
    value = revision.stdout.strip()
    if revision.returncode != 0 or re.fullmatch(r"[0-9a-f]{40}", value) is None:
        return "working-tree"
    return value


def migration_status(
    settings: Settings,
    directory: Path | None = None,
) -> tuple[MigrationStatus, ...]:
    migration_directory = directory or default_migrations_directory()
    migrations = discover_migrations(migration_directory)
    with _migration_connection(settings) as connection:
        applied = _read_applied(connection)
    _validate_history(applied, migrations)

    source_by_id = {migration.migration_id: migration for migration in migrations}
    result: list[MigrationStatus] = []
    for migration_id in MIGRATION_IDS:
        source = source_by_id.get(migration_id)
        record = applied.get(migration_id)
        if record is not None:
            state: Literal["applied", "pending", "not_authored"] = "applied"
        elif source is not None:
            state = "pending"
        else:
            state = "not_authored"
        result.append(
            MigrationStatus(
                migration_id=migration_id,
                state=state,
                source_checksum=source.checksum.hex() if source is not None else None,
                applied_at=record.applied_at if record is not None else None,
            )
        )
    return tuple(result)


def apply_migrations(settings: Settings, directory: Path | None = None) -> tuple[str, ...]:
    migration_directory = directory or default_migrations_directory()
    migrations = discover_migrations(migration_directory)
    source_revision = _source_revision(migration_directory)
    applied_ids: list[str] = []

    with _migration_connection(settings) as connection:
        applied = _read_applied(connection)
        _validate_history(applied, migrations)

        for migration in migrations:
            if migration.migration_id in applied:
                continue
            try:
                with connection.transaction():
                    connection.execute("SET LOCAL ROLE journalwick_kernel_owner")
                    connection.execute(migration.sql, prepare=False)
                    connection.execute(
                        """
                        INSERT INTO jw.schema_migrations
                            (migration_id, checksum, source_revision, runner_version)
                        VALUES (%s, %s, %s, %s)
                        """,
                        (
                            migration.migration_id,
                            migration.checksum,
                            source_revision,
                            __version__,
                        ),
                    )
            except PsycopgError as error:
                sqlstate = error.sqlstate or "unknown"
                raise MigrationRunnerError(
                    "MIGRATION_FAILED",
                    f"Migration {migration.migration_id} failed (SQLSTATE {sqlstate}).",
                ) from None
            applied_ids.append(migration.migration_id)
            applied[migration.migration_id] = AppliedMigration(
                checksum=migration.checksum,
                applied_at=datetime.now(UTC),
            )
            _validate_history(applied, migrations)

    return tuple(applied_ids)
