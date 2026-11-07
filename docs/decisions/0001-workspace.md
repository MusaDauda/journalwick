# Decision 0001: Keep Journalwick in the selected workspace

**Status:** Accepted by the user on 2026-11-07

## Context

The Day 03 handbook identifies `/home/musa/Documents/github-legend/Projects/journalwick` as its intended implementation path and says not to put application source in the handbook folder. That target directory does not exist. The active application workspace is `/home/musa/Documents/portfolio-projects/journalwick`, which was empty when work began.

## Decision

All Journalwick application source, project documentation, local acceptance evidence, and future release material live in `/home/musa/Documents/portfolio-projects/journalwick`. The handbook remains a read-only source of requirements unless the user separately asks to edit it.

## Consequences

- Setup commands and paths from the handbook must be adapted to this repository.
- References to the separate `github-legend` handbook are explanatory inputs, not runtime imports or startup dependencies.
- The copied acceptance gate must retain the original scenario IDs and `not_run` state until actual observations are recorded.
- The separate handbook repository's existing modified/untracked files remain untouched.
