"""Command-line entry point for Journalwick operations."""

from __future__ import annotations

import argparse

from journalwick import __version__


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
    return parser


def main() -> None:
    """Show available operations until their guarded implementations exist."""
    build_parser().parse_args()


if __name__ == "__main__":
    main()
