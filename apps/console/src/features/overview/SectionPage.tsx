type SectionPageProps = {
  section: string
}

export function SectionPage({ section }: SectionPageProps) {
  const isNotFound = section === 'Page not found'

  return (
    <main id="main-content" className="section-page" tabIndex={-1}>
      <div className="page-heading">
        <div>
          <p className="page-heading__date">Northstar Finance · Operating book</p>
          <h1>{section}</h1>
          <p className="page-heading__description">
            {isNotFound
              ? 'This page is not part of the current workspace.'
              : `Review ${section.toLocaleLowerCase()} within the selected book.`}
          </p>
        </div>
      </div>
      <section className="section-empty" aria-labelledby="section-empty-title">
        <h2 id="section-empty-title">This demo section is not connected yet</h2>
        <p>
          The current build shows a synthetic overview. This area will be connected to its
          scoped API and database workflow as the corresponding feature is implemented.
        </p>
      </section>
    </main>
  )
}
