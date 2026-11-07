import type { IconName } from '../components/Icon'

export type NavigationItem = {
  label: string
  to: string
  icon: IconName
  keywords: string
}

export type NavigationGroup = {
  label: string
  items: readonly NavigationItem[]
}

export const navigationGroups: readonly NavigationGroup[] = [
  {
    label: 'Finance',
    items: [
      { label: 'Overview', to: '/', icon: 'overview', keywords: 'home position balance' },
      { label: 'Accounts', to: '/accounts', icon: 'accounts', keywords: 'wallet funds chart' },
      { label: 'Journals', to: '/journals', icon: 'journals', keywords: 'entries ledger posting' },
      { label: 'Operations', to: '/operations', icon: 'operations', keywords: 'activity provider attempts' },
      { label: 'Reservations', to: '/reservations', icon: 'reservations', keywords: 'holds allocations' },
      {
        label: 'Reconciliation',
        to: '/reconciliation',
        icon: 'reconciliation',
        keywords: 'statements matches cases',
      },
      { label: 'Reports', to: '/reports', icon: 'reports', keywords: 'exports close' },
    ],
  },
  {
    label: 'Control',
    items: [
      { label: 'Governance', to: '/governance', icon: 'governance', keywords: 'members roles setup' },
      { label: 'Audit history', to: '/audit', icon: 'audit', keywords: 'events revisions' },
    ],
  },
]

export const navigationItems = navigationGroups.flatMap((group) => group.items)
