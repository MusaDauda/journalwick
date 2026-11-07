export type CurrencyDefinition = {
  code: string
  exponent: number
  version: string
}

export type JournalRow = {
  sequence: string
  reference: string
  description: string
  effectiveAt: string
  debitMinor: string
  creditMinor: string
  currency: CurrencyDefinition
}

export type WorkItem = {
  reference: string
  title: string
  description: string
  state: string
  tone: 'review' | 'danger'
  action: string
  to: string
}

export const demoCurrency: CurrencyDefinition = {
  code: 'USD',
  exponent: 2,
  version: 'usd-cent-v1',
}

export const demoBoundary = {
  journalSequence: '4829',
  stateSequence: '5104',
  evidenceEpoch: '113',
  observedAt: '2026-11-07T13:42:00Z',
}

export const demoPosition = {
  postedMinor: '2849620',
  reservedMinor: '425000',
  availableMinor: '2249420',
}

export const demoJournals: readonly JournalRow[] = [
  {
    sequence: '4829',
    reference: 'jnl_01JX8WQ4',
    description: 'Settlement funding recognized',
    effectiveAt: '2026-11-07T13:39:00Z',
    debitMinor: '182300',
    creditMinor: '182300',
    currency: demoCurrency,
  },
  {
    sequence: '4828',
    reference: 'jnl_01JX8VN2',
    description: 'Processor fee accrued',
    effectiveAt: '2026-11-07T13:21:00Z',
    debitMinor: '2150',
    creditMinor: '2150',
    currency: demoCurrency,
  },
  {
    sequence: '4827',
    reference: 'jnl_01JX8T9A',
    description: 'Merchant payout released',
    effectiveAt: '2026-11-07T12:56:00Z',
    debitMinor: '487500',
    creditMinor: '487500',
    currency: demoCurrency,
  },
  {
    sequence: '4826',
    reference: 'jnl_01JX8R3F',
    description: 'Customer reserve captured',
    effectiveAt: '2026-11-07T12:32:00Z',
    debitMinor: '62500',
    creditMinor: '62500',
    currency: demoCurrency,
  },
]

export const demoWorkItems: readonly WorkItem[] = [
  {
    reference: 'case_01JX8V6P',
    title: 'Transfer response not confirmed',
    description: 'Read the original provider reference before considering another attempt.',
    state: 'Unknown outcome',
    tone: 'danger',
    action: 'Investigate',
    to: '/operations',
  },
  {
    reference: 'case_01JX8S2D',
    title: 'Statement fee differs',
    description: 'The imported amount needs evidence review before it can be resolved.',
    state: 'Review needed',
    tone: 'review',
    action: 'Open case',
    to: '/reconciliation',
  },
  {
    reference: 'case_01JX8Q0B',
    title: 'Repeated source observation',
    description: 'Two event identifiers refer to one provider object.',
    state: 'Evidence check',
    tone: 'review',
    action: 'Compare facts',
    to: '/reconciliation',
  },
]
