import { useEffect, useRef, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Link, NavLink, Outlet } from 'react-router-dom'
import { fetchLiveness } from '../api/health'
import { Icon } from '../components/Icon'
import { demoJournals, demoWorkItems } from '../features/overview/demo'
import { formatMinorUnits } from '../features/overview/money'
import { navigationGroups, navigationItems } from './navigation'
import { QuickSearchDialog, type SearchResult } from './QuickSearchDialog'

const searchResults: SearchResult[] = [
  ...navigationItems.map((item) => ({
    ...item,
    detail: 'Book section',
  })),
  ...demoJournals.map((journal) => ({
    label: journal.description,
    detail: `Journal #${journal.sequence} · ${formatMinorUnits(journal.debitMinor, journal.currency)}`,
    keywords: `${journal.reference} ${journal.sequence} ${journal.description}`,
    to: '/journals',
    icon: 'journals' as const,
  })),
  ...demoWorkItems.map((item) => ({
    label: item.title,
    detail: `${item.state} · ${item.reference}`,
    keywords: `${item.reference} ${item.state} ${item.description}`,
    to: item.to,
    icon: 'reconciliation' as const,
  })),
]

function Navigation({ onNavigate }: { onNavigate?: () => void }) {
  return (
    <nav className="sidebar-nav" aria-label="Primary navigation">
      {navigationGroups.map((group) => (
        <section className="sidebar-nav__group" key={group.label}>
          <h2 className="sidebar-nav__heading">{group.label}</h2>
          <ul className="sidebar-nav__list">
            {group.items.map((item) => (
              <li key={item.to}>
                <NavLink
                  to={item.to}
                  end={item.to === '/'}
                  className="sidebar-nav__link"
                  onClick={onNavigate}
                >
                  <Icon name={item.icon} />
                  <span>{item.label}</span>
                </NavLink>
              </li>
            ))}
          </ul>
        </section>
      ))}
    </nav>
  )
}

function MobileNavigationDialog({ open, onClose }: { open: boolean; onClose: () => void }) {
  const dialogRef = useRef<HTMLDialogElement>(null)

  useEffect(() => {
    const dialog = dialogRef.current
    if (!dialog) return

    if (open && !dialog.open) {
      dialog.showModal()
      return
    }

    if (!open && dialog.open) dialog.close()
  }, [open])

  return (
    <dialog
      ref={dialogRef}
      id="mobile-navigation"
      className="mobile-nav-dialog"
      aria-labelledby="mobile-navigation-title"
      onCancel={(event) => {
        event.preventDefault()
        onClose()
      }}
      onClose={onClose}
      onClick={(event) => {
        if (event.target === event.currentTarget) onClose()
      }}
    >
      <div className="mobile-nav-dialog__head">
        <h2 id="mobile-navigation-title">Journalwick navigation</h2>
        <button className="icon-button" type="button" onClick={onClose} aria-label="Close navigation">
          <Icon name="close" />
        </button>
      </div>
      <div className="mobile-nav-dialog__body">
        <Navigation onNavigate={onClose} />
      </div>
    </dialog>
  )
}

export function AppShell() {
  const [searchOpen, setSearchOpen] = useState(false)
  const [mobileNavigationOpen, setMobileNavigationOpen] = useState(false)
  const liveness = useQuery({
    queryKey: ['system', 'liveness'],
    queryFn: fetchLiveness,
    refetchInterval: 30_000,
  })

  useEffect(() => {
    function handleShortcut(event: KeyboardEvent) {
      if ((event.metaKey || event.ctrlKey) && event.key.toLocaleLowerCase() === 'k') {
        event.preventDefault()
        setSearchOpen(true)
      }
    }

    window.addEventListener('keydown', handleShortcut)
    return () => window.removeEventListener('keydown', handleShortcut)
  }, [])

  const apiState = liveness.data
    ? { label: 'API responding', state: 'available' }
    : liveness.isPending
      ? { label: 'Checking API', state: 'checking' }
      : { label: 'API unavailable', state: 'unavailable' }

  return (
    <div className="app-frame">
      <a className="skip-link" href="#main-content">
        Skip to main content
      </a>

      <aside className="app-sidebar" aria-label="Journalwick workspace">
        <Link className="brand" to="/" aria-label="Journalwick home">
          <span className="brand-mark">
            <Icon name="book" />
          </span>
          <span className="brand-wordmark">
            Journalwick
            <span className="brand-subtitle">FINANCE OPERATIONS</span>
          </span>
        </Link>

        <div className="sidebar-scope" role="group" aria-label="Current organization and book">
          <span className="sidebar-scope__label">Organization</span>
          <span className="sidebar-scope__name">
            Northstar Finance <Icon name="chevron" />
          </span>
          <span className="sidebar-scope__book">Operating book · USD</span>
        </div>

        <Navigation />

        <div className="sidebar-footer">
          <div className="sidebar-footer__identity">
            <span className="identity-dot" aria-hidden="true">DO</span>
            <span>
              Demo operator
              <span className="sidebar-footer__role">Synthetic workspace</span>
            </span>
          </div>
        </div>
      </aside>

      <div className="workspace">
        <header className="workspace-header">
          <button
            className="mobile-menu-trigger"
            type="button"
            aria-label="Open navigation"
            aria-haspopup="dialog"
            aria-controls="mobile-navigation"
            aria-expanded={mobileNavigationOpen}
            onClick={() => setMobileNavigationOpen(true)}
          >
            <Icon name="menu" />
          </button>

          <div className="workspace-context" aria-label="Selected book context">
            <span className="workspace-context__org">Northstar Finance</span>
            <span className="context-divider" aria-hidden="true" />
            <span>Operating book</span>
            <span className="context-currency">USD</span>
          </div>

          <div className="workspace-actions">
            <button
              className="search-trigger"
              type="button"
              aria-label="Search records and sections in this book"
              aria-haspopup="dialog"
              aria-controls="quick-search-dialog"
              onClick={() => setSearchOpen(true)}
            >
              <Icon name="search" />
              <span className="search-trigger__label">Search this book</span>
              <kbd aria-hidden="true">Ctrl K / ⌘ K</kbd>
            </button>
            <span
              className="api-status"
              data-state={apiState.state}
              role="status"
              aria-live="polite"
            >
              <span className="api-status__dot" aria-hidden="true" />
              <span className="api-status__label">{apiState.label}</span>
            </span>
          </div>
        </header>

        <div className="workspace-content">
          <aside className="fixture-banner" aria-label="Data environment">
            <strong>Synthetic fixture</strong>
            <span>All displayed records are invented. No live provider is connected.</span>
          </aside>
          <Outlet />
        </div>
      </div>

      <MobileNavigationDialog
        open={mobileNavigationOpen}
        onClose={() => setMobileNavigationOpen(false)}
      />
      <QuickSearchDialog
        open={searchOpen}
        items={searchResults}
        onClose={() => setSearchOpen(false)}
      />
    </div>
  )
}
