import { useEffect, useRef, useState } from 'react'
import { Link } from 'react-router-dom'
import type { IconName } from '../components/Icon'
import { Icon } from '../components/Icon'

export type SearchResult = {
  label: string
  detail: string
  keywords: string
  to: string
  icon: IconName
}

type QuickSearchDialogProps = {
  open: boolean
  items: readonly SearchResult[]
  onClose: () => void
}

export function QuickSearchDialog({ open, items, onClose }: QuickSearchDialogProps) {
  const dialogRef = useRef<HTMLDialogElement>(null)
  const [query, setQuery] = useState('')
  const normalizedQuery = query.trim().toLocaleLowerCase()
  const results = normalizedQuery
    ? items.filter((item) =>
        `${item.label} ${item.keywords}`.toLocaleLowerCase().includes(normalizedQuery),
      )
    : items

  useEffect(() => {
    const dialog = dialogRef.current
    if (!dialog) return

    if (open && !dialog.open) {
      dialog.showModal()
      return
    }

    if (!open && dialog.open) dialog.close()
  }, [open])

  function closeDialog() {
    setQuery('')
    onClose()
  }

  return (
    <dialog
      ref={dialogRef}
      id="quick-search-dialog"
      className="search-dialog"
      aria-labelledby="quick-search-title"
      onCancel={(event) => {
        event.preventDefault()
        closeDialog()
      }}
      onClose={closeDialog}
    >
      <div className="search-dialog__head">
        <h2 id="quick-search-title">Search this book</h2>
        <button className="icon-button" type="button" onClick={closeDialog} aria-label="Close search">
          <Icon name="close" />
        </button>
      </div>
      <div className="search-dialog__body">
        <label className="search-field">
          <Icon name="search" />
          <span className="visually-hidden">Search records and sections in the current book</span>
          <input
            autoFocus
            type="search"
            value={query}
            onChange={(event) => setQuery(event.currentTarget.value)}
            placeholder="Journal reference, case, account…"
          />
        </label>
        <ul className="search-results">
          {results.map((item) => (
            <li key={`${item.to}:${item.label}`}>
              <Link to={item.to} onClick={closeDialog}>
                <Icon name={item.icon} />
                <span>
                  <span className="search-results__label">{item.label}</span>
                  <span className="search-results__detail">{item.detail}</span>
                </span>
              </Link>
            </li>
          ))}
          {results.length === 0 && (
            <li className="search-empty" role="status">
              No matching records or sections in this book.
            </li>
          )}
        </ul>
        <p className="search-hint">Search is limited to records in the selected synthetic book.</p>
      </div>
    </dialog>
  )
}
