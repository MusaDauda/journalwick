export type IconName =
  | 'overview'
  | 'accounts'
  | 'journals'
  | 'operations'
  | 'reservations'
  | 'reconciliation'
  | 'reports'
  | 'governance'
  | 'audit'
  | 'search'
  | 'menu'
  | 'close'
  | 'arrow'
  | 'chevron'
  | 'book'

type IconProps = {
  name: IconName
  className?: string
}

export function Icon({ name, className }: IconProps) {
  const classes = className ? `icon ${className}` : 'icon'
  const sharedProps = {
    className: classes,
    viewBox: '0 0 24 24',
    fill: 'none',
    stroke: 'currentColor',
    strokeWidth: 1.7,
    strokeLinecap: 'round' as const,
    strokeLinejoin: 'round' as const,
    'aria-hidden': true as const,
  }

  switch (name) {
    case 'overview':
      return <svg {...sharedProps}><rect x="3.5" y="3.5" width="7" height="7" rx="1" /><rect x="13.5" y="3.5" width="7" height="7" rx="1" /><rect x="3.5" y="13.5" width="7" height="7" rx="1" /><rect x="13.5" y="13.5" width="7" height="7" rx="1" /></svg>
    case 'accounts':
      return <svg {...sharedProps}><rect x="3" y="5" width="18" height="15" rx="2" /><path d="M3 9h18M7 5V3.5h10V5M15.5 14H18" /><circle cx="13" cy="14" r="1" /></svg>
    case 'journals':
      return <svg {...sharedProps}><path d="M5 4.5h12.5A1.5 1.5 0 0 1 19 6v14H6.5A1.5 1.5 0 0 1 5 18.5z" /><path d="M5 17.5A1.5 1.5 0 0 1 6.5 16H19M8.5 8.5h7M8.5 11.5h7" /></svg>
    case 'operations':
      return <svg {...sharedProps}><path d="M4 7h15m0 0-3-3m3 3-3 3M20 17H5m0 0 3-3m-3 3 3 3" /></svg>
    case 'reservations':
      return <svg {...sharedProps}><rect x="4" y="10" width="16" height="11" rx="2" /><path d="M8 10V7a4 4 0 0 1 8 0v3m-4 4v3" /></svg>
    case 'reconciliation':
      return <svg {...sharedProps}><path d="M20 11.5V12a8 8 0 1 1-2.35-5.65M20 5v6h-6" /><path d="m8.5 12.5 2.2 2.2 5-5" /></svg>
    case 'reports':
      return <svg {...sharedProps}><path d="M4 20V11m5 9V5m5 15v-7m5 7V8M2.5 20.5h19" /></svg>
    case 'governance':
      return <svg {...sharedProps}><circle cx="9" cy="8" r="3" /><path d="M3.5 19v-1.3A4.7 4.7 0 0 1 8.2 13h1.6a4.7 4.7 0 0 1 4.7 4.7V19zM16 5.5a3 3 0 0 1 0 5.8m2 2.2a4.6 4.6 0 0 1 2.5 4.2V19h-3" /></svg>
    case 'audit':
      return <svg {...sharedProps}><path d="M8 5h12M8 12h12M8 19h12M3.5 5h.01M3.5 12h.01M3.5 19h.01" /></svg>
    case 'search':
      return <svg {...sharedProps}><circle cx="10.8" cy="10.8" r="6.8" /><path d="m16 16 4.5 4.5" /></svg>
    case 'menu':
      return <svg {...sharedProps}><path d="M4 6.5h16M4 12h16M4 17.5h16" /></svg>
    case 'close':
      return <svg {...sharedProps}><path d="m6 6 12 12M18 6 6 18" /></svg>
    case 'arrow':
      return <svg {...sharedProps}><path d="M7 17 17 7M8 7h9v9" /></svg>
    case 'chevron':
      return <svg {...sharedProps}><path d="m7 10 5 5 5-5" /></svg>
    case 'book':
      return <svg {...sharedProps}><path d="M4 4.5h13.5A2.5 2.5 0 0 1 20 7v13H6.5A2.5 2.5 0 0 1 4 17.5z" /><path d="M4 17.5A2.5 2.5 0 0 1 6.5 15H20M8 8h8m-8 3h6" /></svg>
  }
}
