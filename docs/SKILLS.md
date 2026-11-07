# Skills used for Journalwick

The user asked that skills be found, installed when appropriate, and read before implementation. Searches use the `find-skills` workflow and the skills.sh leaderboard. Skills are guidance; the reviewed Journalwick contract and current official library/provider documentation control product behavior.

## Installed and available

| Skill | Source | Catalog installs at discovery | Use |
|---|---|---:|---|
| `frontend-design` | `anthropics/skills` | 1.1M | Product-specific visual direction and design critique; already installed globally |
| `vercel-react-best-practices` | `vercel-labs/agent-skills` | 877K+ | React/TypeScript component and performance guidance; already installed globally |
| `web-design-guidelines` | `vercel-labs/agent-skills` | — | Fresh review of UI behavior against current interface guidance; already installed globally |
| `improve-codebase-architecture` | `mattpocock/skills` | 1.2M | Architecture review after real code exists; installed globally. Its current workflow asks for sub-agent exploration, so that portion is not applicable in this single-agent run. |
| `spec-driven-development` | `addyosmani/agent-skills` | 73.3K | Capability map and scope before code; installed globally and applied to this design |
| `planning-and-task-breakdown` | `addyosmani/agent-skills` | 72.2K | Dependency-aware milestones and small implementation tasks; installed globally |
| `fastapi` | `fastapi/fastapi` | 14.7K | API routing, typed DTOs, OpenAPI, and serving the built console; official FastAPI source |
| `supabase-postgres-best-practices` | `supabase/agent-skills` | 476.8K | Generic PostgreSQL schema/query/connection guidance only; Supabase features are not part of Journalwick |
| `accessibility` | `addyosmani/web-quality-skills` | 67.9K | WCAG 2.2 review and keyboard/screen-reader work |
| `python-testing-patterns` | `wshobson/agents` | 39.8K | Python unit, database, and async integration testing |
| `tdd` | `mattpocock/skills` | 800.9K | Small behavior-first test/implementation cycles at agreed product seams |
| `playwright-cli` | `microsoft/playwright-cli` | 210K | Browser journey inspection and responsive/accessibility review |
| `security-and-hardening` | `addyosmani/agent-skills` | 79.9K | Input, auth, authorization, privacy, and dependency hardening |
| `security-best-practices` | `openai/skills` | 12K | Secure-by-default Python and TypeScript review; installed. The repository is now marked deprecated, so use as supplemental guidance only. |
| `stripe-integration` | `wshobson/agents` | 13.8K | Stripe API/webhook guidance, filtered through the narrower Journalwick ledger-evidence contract |
| `database-migration` | `wshobson/agents` | 18K | Installed for schema work; its ORM-specific examples are supplemental because Journalwick uses raw SQL migrations and a custom checksum runner |

The CLI reports an unsupported PromptScript integration for global installs after copying selected skills under `/home/musa/.agents/skills`; `npx skills list --global --json` confirms the copies are available to Codex. No skill files were added to the project repository.

## Search coverage and exclusions

Searched the skills catalog for portfolio/website, Python/FastAPI, PostgreSQL, React/TypeScript, accessibility, testing/Playwright, security, architecture, documentation/planning, payments/Stripe, ledger/accounting/reconciliation, passkeys/WebAuthn, AWS/Terraform, and cryptography/KMS.

- Portfolio/Awwwards skills target marketing or personal showcase sites, not Journalwick's operational finance console.
- No credible high-install ledger/accounting or passkey-specific skill surfaced. Search results for these were low-install or poorly sourced; use the reviewed accounting blueprint and primary WebAuthn/provider docs instead.
- Postgres skills tied to Drizzle, Prisma, or Supabase runtime are not a fit for this Python/Psycopg product; only generic SQL guidance will be used.
- AWS deployment skills will be searched and installed before implementing Terraform/release infrastructure.

## Installation and use rule

Before starting a new implementation area, run a focused `npx skills find` query, select an appropriate credible source, install it if missing, and read its `SKILL.md` plus the relevant reference files. Avoid loading unrelated guidance and record any material new choice here.
