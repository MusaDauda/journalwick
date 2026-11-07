import { Link } from 'react-router-dom'
import { Icon } from '../../components/Icon'
import { demoBoundary, demoCurrency, demoJournals, demoPosition, demoWorkItems } from './demo'
import { formatMinorUnits } from './money'

function formatBoundaryTime(value: string): string {
  return new Intl.DateTimeFormat('en-GB', {
    day: 'numeric',
    month: 'short',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    timeZone: 'UTC',
    timeZoneName: 'short',
  }).format(new Date(value))
}

function StateBadge({ label, tone }: { label: string; tone: 'accepted' | 'review' }) {
  return <span className="state-badge" data-tone={tone}>{label}</span>
}

export function OverviewPage() {
  return (
    <main id="main-content" className="overview-page" tabIndex={-1}>
      <div className="page-heading">
        <div>
          <p className="page-heading__date">Saturday, 7 November 2026</p>
          <h1>Ledger overview</h1>
          <p className="page-heading__description">
            Current position and open work for the selected operating book.
          </p>
        </div>
        <Link className="page-heading__action" to="/operations">
          Review open work <Icon name="arrow" />
        </Link>
      </div>

      <section className="position-strip" aria-label="Current USD position">
        <div className="position-item">
          <span className="position-item__label">Posted balance</span>
          <strong className="position-item__amount">
            {formatMinorUnits(demoPosition.postedMinor, demoCurrency)}
          </strong>
          <span className="position-item__note">Accepted journals through {demoBoundary.journalSequence}</span>
        </div>
        <div className="position-item">
          <span className="position-item__label">Reserved</span>
          <strong className="position-item__amount">
            {formatMinorUnits(demoPosition.reservedMinor, demoCurrency)}
          </strong>
          <span className="position-item__note">Active holds and unresolved provider exposure</span>
        </div>
        <div className="position-item">
          <span className="position-item__label">Available</span>
          <strong className="position-item__amount">
            {formatMinorUnits(demoPosition.availableMinor, demoCurrency)}
          </strong>
          <span className="position-item__note">Current spendable amount at state {demoBoundary.stateSequence}</span>
        </div>
      </section>

      <div className="boundary-line" aria-label="Observation boundary">
        <span>One currency · {demoCurrency.code}</span>
        <span>Observed {formatBoundaryTime(demoBoundary.observedAt)}</span>
        <span>Evidence epoch {demoBoundary.evidenceEpoch}</span>
      </div>

      <div className="overview-grid">
        <section className="content-panel journal-panel" aria-labelledby="journal-panel-title">
          <header className="content-panel__header">
            <div>
              <h2 className="content-panel__title" id="journal-panel-title">Recent journal activity</h2>
              <p className="content-panel__subhead">Accepted, immutable entries in this book</p>
            </div>
            <Link className="text-link" to="/journals">
              View journals <Icon name="arrow" />
            </Link>
          </header>
          <div className="table-scroll">
            <table className="ledger-table">
              <caption className="visually-hidden">Recent synthetic USD journal entries</caption>
              <thead>
                <tr>
                  <th scope="col">Journal</th>
                  <th scope="col">Effective time</th>
                  <th scope="col" className="numeric-heading">Debit</th>
                  <th scope="col" className="numeric-heading">Credit</th>
                  <th scope="col">State</th>
                </tr>
              </thead>
              <tbody>
                {demoJournals.map((journal) => (
                  <tr key={journal.sequence}>
                    <td>
                      <span className="journal-name">{journal.description}</span>
                      <span className="journal-ref">{journal.reference} · #{journal.sequence}</span>
                    </td>
                    <td className="date-cell">{formatBoundaryTime(journal.effectiveAt)}</td>
                    <td className="amount-cell">{formatMinorUnits(journal.debitMinor, journal.currency)}</td>
                    <td className="amount-cell">{formatMinorUnits(journal.creditMinor, journal.currency)}</td>
                    <td><StateBadge label="Accepted" tone="accepted" /></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <p className="panel-footnote">
            Debit and credit totals balance independently in {demoCurrency.code}. No cross-currency total is shown.
          </p>
        </section>

        <section className="content-panel work-panel" aria-labelledby="work-panel-title">
          <header className="content-panel__header">
            <div>
              <h2 className="content-panel__title" id="work-panel-title">Needs attention</h2>
              <p className="content-panel__subhead">Evidence and review work still open</p>
            </div>
            <StateBadge label={`${demoWorkItems.length} open`} tone="review" />
          </header>
          <ul className="work-list">
            {demoWorkItems.map((item) => (
              <li className="work-list__item" data-tone={item.tone} key={item.reference}>
                <span className="work-list__marker" aria-hidden="true" />
                <div>
                  <p className="work-list__title">{item.title}</p>
                  <p className="work-list__description">{item.description}</p>
                  <div className="work-list__meta">
                    <span className="work-list__reference">{item.reference} · {item.state}</span>
                    <Link className="work-list__action" to={item.to}>{item.action}</Link>
                  </div>
                </div>
              </li>
            ))}
          </ul>
          <p className="panel-footnote">
            An unknown provider outcome stays unresolved until supported evidence confirms its result.
          </p>
        </section>
      </div>
    </main>
  )
}
