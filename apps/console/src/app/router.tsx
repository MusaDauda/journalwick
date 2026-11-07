import { createBrowserRouter } from 'react-router-dom'
import { AppShell } from './AppShell'
import { OverviewPage } from '../features/overview/OverviewPage'
import { SectionPage } from '../features/overview/SectionPage'

export const router = createBrowserRouter([
  {
    path: '/',
    element: <AppShell />,
    children: [
      { index: true, element: <OverviewPage /> },
      { path: 'accounts', element: <SectionPage section="Accounts" /> },
      { path: 'journals', element: <SectionPage section="Journals" /> },
      { path: 'operations', element: <SectionPage section="Operations" /> },
      { path: 'reservations', element: <SectionPage section="Reservations" /> },
      { path: 'reconciliation', element: <SectionPage section="Reconciliation" /> },
      { path: 'reports', element: <SectionPage section="Reports" /> },
      { path: 'governance', element: <SectionPage section="Governance" /> },
      { path: 'audit', element: <SectionPage section="Audit history" /> },
      { path: '*', element: <SectionPage section="Page not found" /> },
    ],
  },
])
