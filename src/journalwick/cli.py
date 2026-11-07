"""Command-line entry point for Journalwick operations."""

from __future__ import annotations

import argparse
import sys
from datetime import UTC

from journalwick import __version__
from journalwick.migrations.runner import MigrationRunnerError, apply_migrations, migration_status
from journalwick.platform.settings import get_settings


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="journalwick",
        description="Operate the independent Journalwick ledger application.",
    )
    parser.add_argument(
        "--version",
        action="version",
        version=f"journalwick {__version__}",
    )
    commands = parser.add_subparsers(dest="command")
    database = commands.add_parser("db", help="Inspect or apply reviewed database migrations.")
    database_commands = database.add_subparsers(dest="database_command", required=True)
    database_commands.add_parser("status", help="Show applied and pending migration checksums.")
    database_commands.add_parser("migrate", help="Apply pending migrations transactionally.")
    return parser


def main() -> None:
    """Run a safe, non-secret database management command."""
    parser = build_parser()
    arguments = parser.parse_args()
    if arguments.command != "db":
        parser.print_help()
        return

    try:
        settings = get_settings()
        if arguments.database_command == "status":
            for item in migration_status(settings):
                checksum = item.source_checksum or "-"
                applied_at = (
                    item.applied_at.astimezone(UTC).isoformat()
                    if item.applied_at is not None
                    else "-"
                )
                print(f"{item.migration_id}\t{item.state}\t{checksum}\t{applied_at}")
            return

        if arguments.database_command == "migrate":
            applied = apply_migrations(settings)
            if not applied:
                print("No pending released SQL migrations.")
                return
            for migration_id in applied:
                print(f"Applied {migration_id}.")
            return
    except MigrationRunnerError as error:
        print(f"{error.code}: {error.message}", file=sys.stderr)
        raise SystemExit(2) from None
    except ValueError:
        print("INVALID_CONFIGURATION: Journalwick runtime settings are invalid.", file=sys.stderr)
        raise SystemExit(2) from None


if __name__ == "__main__":
    main()
