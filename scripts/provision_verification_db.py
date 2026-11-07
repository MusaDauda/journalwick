"""Create a new local database for the PostgreSQL integration checks."""

from __future__ import annotations

import argparse
import hashlib
import uuid
from pathlib import Path

import psycopg
from psycopg import sql
from pydantic import SecretStr

from journalwick import __version__
from journalwick.migrations.manifest import MIGRATION_IDS, RELEASED_MIGRATION_IDS
from journalwick.migrations.runner import apply_migrations
from journalwick.platform.settings import Settings

PROJECT_ROOT = Path(__file__).resolve().parents[1]
LOCAL_POSTGRES = "postgresql://postgres@127.0.0.1:55003/postgres"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--journal-draft",
        action="store_true",
        help="Install the unreleased journal migration in a new concurrency test database.",
    )
    arguments = parser.parse_args()

    prefix = "journalwick_verify_race_" if arguments.journal_draft else "journalwick_verify_"
    database_name = prefix + uuid.uuid4().hex[:16]
    admin_dsn = f"postgresql://postgres@127.0.0.1:55003/{database_name}"
    migrator_dsn = f"postgresql://journalwick_migrator@127.0.0.1:55003/{database_name}"

    with psycopg.connect(LOCAL_POSTGRES, autocommit=True) as connection:
        version = connection.execute("SHOW server_version_num").fetchone()
        if version is None or not 180000 <= int(version[0]) < 190000:
            raise RuntimeError("The isolated local PostgreSQL 18 cluster is required")
        connection.execute(
            sql.SQL("CREATE DATABASE {} WITH TEMPLATE template0 ENCODING 'UTF8' LOCALE 'C'").format(
                sql.Identifier(database_name)
            )
        )

    bootstrap = (PROJECT_ROOT / "scripts/dev-bootstrap.sql").read_text()
    if bootstrap.count("DATABASE journalwick") != 2:
        raise RuntimeError(f"Inspect the bootstrap SQL before using {database_name}")
    bootstrap = bootstrap.replace("DATABASE journalwick", f'DATABASE "{database_name}"')
    with psycopg.connect(admin_dsn) as connection:
        connection.execute(bootstrap, prepare=False)

    settings = Settings(
        environment="test",
        process_role="migrator",
        database_auth_mode="dsn",
        database_url=SecretStr(migrator_dsn),
    )
    applied = apply_migrations(settings, PROJECT_ROOT / "migrations")
    print(f"Created {database_name}; applied {len(applied)} released migrations.")

    if arguments.journal_draft:
        draft_id = MIGRATION_IDS[3]
        if draft_id in RELEASED_MIGRATION_IDS:
            raise RuntimeError(
                "The journal migration is released; use the normal migration command"
            )
        source = (PROJECT_ROOT / "migrations" / f"{draft_id}.sql").read_bytes()
        with psycopg.connect(migrator_dsn) as connection:
            connection.execute("SET LOCAL ROLE journalwick_kernel_owner")
            connection.execute(source.decode("utf-8"), prepare=False)
            connection.execute(
                "INSERT INTO jw.schema_migrations "
                "(migration_id,checksum,source_revision,runner_version) VALUES (%s,%s,%s,%s)",
                (draft_id, hashlib.sha256(source).digest(), "verification-fixture", __version__),
            )
        print("Installed the journal draft in this isolated database for concurrency checks.")

    variable = "JW_TEST_COMMITTED_DSN" if arguments.journal_draft else "JW_TEST_ADMIN_DSN"
    print(f"{variable}={admin_dsn}")


if __name__ == "__main__":
    main()
