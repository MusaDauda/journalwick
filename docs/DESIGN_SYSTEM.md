# Finance console design system

## Product and audience

The console is a finance operations workbench for people who need to understand what was accepted, what remains reserved, which provider evidence supports a result, and what action their current role permits. It is not a promotional dashboard. The design gives journal lines, currency units, evidence boundaries, and exceptions first-class visual structure.

## Design direction

**Ledger rail:** a cool, low-glare workspace with a deep ink navigation rail and a single teal transaction spine that connects current work, journal history, and evidence. Density belongs in legible tables and timelines, not in a wall of identical cards.

### Tokens

| Token | Value | Use |
|---|---|---|
| `ink` | `#142432` | Primary text and navigation |
| `canvas` | `#F2F6F8` | Main workspace background |
| `surface` | `#FFFFFF` | Tables, forms, review surfaces |
| `line` | `#D7E1E7` | Row separators and field boundaries |
| `muted` | `#536675` | Supporting labels and timestamps |
| `ledger` | `#087B72` | Accepted/active financial flow and focus accent |
| `link` | `#245DA8` | Navigation and evidence references |
| `review` | `#8A5700` | Pending review and unknown external outcome |
| `danger` | `#A23030` | Rejected, blocked, or failed states |

Use color with explicit text or icons. Statuses are never color-only. The teal is reserved for accepted/active workflow cues, not for a generic success glow.

### Type and number presentation

- IBM Plex Sans for navigation, instructions, headings, and form labels.
- IBM Plex Mono for exact amount strings and immutable IDs only, where aligned digits materially improve scanning.
- Use tabular figures for all amounts, right-align numeric columns, show currency code beside every amount, and distinguish debit and credit columns.
- Use sentence case, short active labels, and time-zone/source-boundary context near each financial view.

### Layout and hierarchy

- Persistent 228px organization/book rail on wide screens; compact drawer on small screens.
- A slim context header keeps organization, book, currency scope, identity, and observation boundary visible.
- The main content uses a 12-column grid with a readable max width. Ledger and audit tables may use the available width; explanatory prose stays narrower.
- High-impact actions sit beside the resource they affect and open an explicit review surface with amount, currency, source, target, evidence, and consequence.
- Avoid a single total across currencies and avoid oversized balance cards as the page's visual anchor.

## Overview wireframe

```text
┌──────────────┬─────────────────────────────────────────────────────────────┐
│ JOURNALWICK  │ Organization / Book / Currency scope / Identity / Boundary │
│              ├─────────────────────────────────────────────────────────────┤
│ Overview     │ Overview                              [Create proposal]     │
│ Accounts     │ State + selected currency + last observed sequence          │
│ Journals     ├─────────────────────────────────────────────────────────────┤
│ Operations   │ Current work queue                                         │
│ Reconcile    │ ┌─────────────────────────────┐ ┌────────────────────────┐ │
│ Reports      │ │ Reconciliation exceptions  │ │ Provider / worker state│ │
│ Governance   │ └─────────────────────────────┘ └────────────────────────┘ │
│              ├─────────────────────────────────────────────────────────────┤
│              │ Recent journal lines: date | account | debit | credit | ref │
└──────────────┴─────────────────────────────────────────────────────────────┘
```

## Two layout concepts considered

1. **Operations-first overview (selected):** an actionable review queue above a real ledger table, with provider state beside open exceptions. It makes uncertainty and the next safe task visible.
2. **Balance-first card wall (rejected):** a row of large totals, trend chart, and rounded metric cards. It implies comparable or current balances even when currencies and observation boundaries differ.

The selected direction makes the product's distinctive structure—the paired debit/credit rails and evidence trail—the visual anchor. It avoids the default SaaS metric-card dashboard and decorative gradients because neither helps an operator assess financial state.

## Interaction and accessibility

- Keyboard access and visible focus for every action; dialogs announce a title, move focus predictably, and restore it on close.
- Respect reduced motion. Motion responds only to a user's action and communicates the change.
- Every page distinguishes loading, empty, ready, stale, forbidden, missing, conflict, and unavailable.
- Errors identify the field or current version and preserve safe draft input. Unknown provider state stays explicit and never appears as success.
- Long tables keep headers and currency/sign readable. Narrow layouts provide a detail view without dropping accounting units.
- Allocation trees also have an accessible hierarchical table. Timelines use ordered text, not colored dots alone.
- Build and review against the installed accessibility skill and the applicable interface guidelines before calling a browser journey complete.
