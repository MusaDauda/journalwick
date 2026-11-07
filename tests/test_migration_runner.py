from __future__ import annotations

import hashlib
import os
import shutil
from datetime import UTC, datetime
from pathlib import Path

import psycopg
import pytest
from psycopg.conninfo import conninfo_to_dict, make_conninfo
from pydantic import SecretStr

from journalwick.migrations.manifest import MIGRATION_IDS
from journalwick.migrations.runner import (
    AppliedMigration,
    Migration,
    MigrationRunnerError,
    _validate_history,
    apply_migrations,
    discover_migrations,
    migration_status,
)
from journalwick.platform.settings import Settings


def _migration(directory: Path, migration_id: str, sql: bytes = b"SELECT 1;\n") -> Migration:
    path = directory / f"{migration_id}.sql"
    path.write_bytes(sql)
    return Migration(
        migration_id=migration_id,
        path=path,
        sql=sql.decode("utf-8"),
        checksum=hashlib.sha256(sql).digest(),
    )


def test_discover_migrations_returns_contiguous_prefix_and_checksum(tmp_path: Path) -> None:
    source = b"SELECT 'reviewed migration';\n"
    path = tmp_path / f"{MIGRATION_IDS[0]}.sql"
    path.write_bytes(source)

    discovered = discover_migrations(tmp_path)

    assert len(discovered) == 1
    assert discovered[0].migration_id == MIGRATION_IDS[0]
    assert discovered[0].checksum == hashlib.sha256(source).digest()


def test_discover_migrations_rejects_unknown_migration_id(tmp_path: Path) -> None:
    (tmp_path / "0001_unreviewed.sql").write_text("SELECT 1;\n")

    with pytest.raises(MigrationRunnerError) as raised:
        discover_migrations(tmp_path)

    assert raised.value.code == "MIGRATION_UNKNOWN"


def test_discover_migrations_rejects_a_gap_in_the_source_series(tmp_path: Path) -> None:
    _migration(tmp_path, MIGRATION_IDS[1])

    with pytest.raises(MigrationRunnerError) as raised:
        discover_migrations(tmp_path)

    assert raised.value.code == "MIGRATION_SEQUENCE_GAP"


def test_validate_history_refuses_a_changed_applied_checksum(tmp_path: Path) -> None:
    source = _migration(tmp_path, MIGRATION_IDS[0])
    applied = {
        source.migration_id: AppliedMigration(
            checksum=hashlib.sha256(b"different source").digest(),
            applied_at=datetime.now(UTC),
        )
    }

    with pytest.raises(MigrationRunnerError) as raised:
        _validate_history(applied, (source,))

    assert raised.value.code == "MIGRATION_CHECKSUM_MISMATCH"


def test_validate_history_rejects_a_missing_source_for_applied_migration(
    tmp_path: Path,
) -> None:
    source = _migration(tmp_path, MIGRATION_IDS[0])
    applied = {
        source.migration_id: AppliedMigration(
            checksum=source.checksum,
            applied_at=datetime.now(UTC),
        )
    }

    with pytest.raises(MigrationRunnerError) as raised:
        _validate_history(applied, ())

    assert raised.value.code == "MIGRATION_SOURCE_MISSING"


def test_validate_history_rejects_a_gap_in_applied_records(tmp_path: Path) -> None:
    first = _migration(tmp_path, MIGRATION_IDS[0])
    second = _migration(tmp_path, MIGRATION_IDS[1])
    applied = {
        second.migration_id: AppliedMigration(
            checksum=second.checksum,
            applied_at=datetime.now(UTC),
        )
    }

    with pytest.raises(MigrationRunnerError) as raised:
        _validate_history(applied, (first, second))

    assert raised.value.code == "MIGRATION_HISTORY_GAP"


def test_validate_history_refuses_an_unreleased_applied_migration(tmp_path: Path) -> None:
    sources = tuple(_migration(tmp_path, migration_id) for migration_id in MIGRATION_IDS[:4])
    applied = {
        migration.migration_id: AppliedMigration(
            checksum=migration.checksum,
            applied_at=datetime.now(UTC),
        )
        for migration in sources
    }

    with pytest.raises(MigrationRunnerError) as raised:
        _validate_history(applied, sources)

    assert raised.value.code == "MIGRATION_UNRELEASED_APPLIED"


def test_migrator_reports_and_skips_unreleased_draft(tmp_path: Path) -> None:
    admin_dsn = os.environ.get("JW_TEST_ADMIN_DSN")
    if not admin_dsn:
        pytest.skip("JW_TEST_ADMIN_DSN must name a dedicated local verification database")
    parts = conninfo_to_dict(admin_dsn)
    if (
        parts.get("host") != "127.0.0.1"
        or parts.get("port") != "55003"
        or parts.get("user") != "postgres"
        or not parts.get("dbname", "").startswith("journalwick_verify_")
    ):
        raise RuntimeError("Integration checks require a dedicated local verification database")

    for migration_id in MIGRATION_IDS[:3]:
        source = Path("migrations") / f"{migration_id}.sql"
        shutil.copyfile(source, tmp_path / source.name)
    _migration(tmp_path, MIGRATION_IDS[3], b"CREATE TABLE jw.draft_must_not_run (id integer);\n")
    settings = Settings(
        database_url=SecretStr(make_conninfo(admin_dsn, user="journalwick_migrator"))
    )

    status = migration_status(settings, tmp_path)
    assert status[3].state == "draft"
    assert apply_migrations(settings, tmp_path) == ()
    with psycopg.connect(admin_dsn) as connection:
        row = connection.execute("SELECT to_regclass('jw.draft_must_not_run')").fetchone()
        assert row is not None and row[0] is None
