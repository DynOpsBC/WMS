/**
 * Minimal i18n shim. English is the only language at GA per the M9 scope.
 * The catalogue + lookup are wired so adding locales later is a non-breaking change.
 */

type Locale = 'en';

const catalogue: Record<Locale, Record<string, string>> = {
  en: {
    'app.name': 'BCWMSApp',
    'nav.dashboard': 'Dashboard',
    'nav.setup': 'Setup',
    'nav.menuDesigner': 'Menu Designer',
    'nav.receipts': 'Receipts',
    'nav.shipments': 'Shipments',
    'nav.counts': 'Counts',
    'nav.production': 'Production',
    'nav.shipping': 'Shipping',
    'auth.signIn': 'Sign in',
    'auth.signInWithMicrosoft': 'Sign in with Microsoft',
    'auth.signOut': 'Sign out',
  },
};

let current: Locale = 'en';

export function setLocale(l: Locale): void {
  current = l;
}

export function t(key: string, fallback?: string): string {
  return catalogue[current]?.[key] ?? fallback ?? key;
}
