# Journalwick project instructions

## Workspace and source of truth

- The application repository is `/home/musa/Documents/portfolio-projects/journalwick`.
- The Day 03 blueprint is in `/home/musa/Documents/github-legend/Implementation/Day-03-Journalwick/`.
- The user explicitly selected this Journalwick workspace over the blueprint's suggested target path. Keep all application code, project documentation, and evidence in this workspace.
- Treat the reviewed Day 03 baseline and its 68-scenario `gate.json` as the behavioral source of truth. Do not edit the handbook while implementing this project.

## Skill workflow

Before each implementation area, search the skills catalog with `npx skills find <focused query>`, check source quality and scope fit, install a relevant skill if it is not already available, then read its `SKILL.md` and applicable references. Record material new skill choices in `docs/SKILLS.md`. Do not install low-quality or mismatched skills just to increase the count. Current availability and prior searches are listed in that file.

## Product boundaries

- Journalwick is a standalone financial ledger and reconciliation product. Stripe, Paystack, Keyrill, and every other portfolio runtime are optional integrations.
- The PostgreSQL journal and guarded database functions own accepted financial state. Do not substitute UI calculations, mock-only persistence, or direct table writes.
- Store and transport money as exact integer strings tied to immutable currency definitions. Do not use binary floating point or JavaScript `Number` for monetary values.
- Accepted journals and source observations are append-only. Fix history through reviewed corrective records.
- Keep provider network calls, file parsing, and report generation outside financial locks. Unknown external outcomes stay visible and allocated until supported evidence resolves them.
- Recheck current scoped authority for every protected read or mutation. Separate creator and reviewer identity.
- Fixtures and seeded examples must be clearly synthetic. Never write credentials, session proofs, payment secrets, or private financial artifacts into source or logs.
- Do not claim a scenario, provider sandbox, deployment, recovery drill, or operational capability passed without actual scoped evidence.

## Delivery

- Follow `docs/CAPABILITY_MAP.md`, `tasks/plan.md`, and the ordered work packages in the handbook.
- Keep each implementation change focused on one behavior. Use the installed testing skills for the matching Python, database, API, and browser acceptance work.
- Preserve local data and unrelated repositories. Never run destructive database or filesystem cleanup as a shortcut.
