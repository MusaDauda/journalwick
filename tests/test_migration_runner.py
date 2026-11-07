from __future__ import annotations

import hashlib
from datetime import UTC, datetime
from pathlib import Path

import pytest

from journalwick.migrations.manifest import MIGRATION_IDS
from journalwick.migrations.runner import (
    AppliedMigration,
    Migration,
    MigrationRunnerError,
    _validate_history,
    discover_migrations,
)


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
