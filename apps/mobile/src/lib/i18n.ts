type Locale = 'en';

const catalogue: Record<Locale, Record<string, string>> = {
  en: {
    'menu.title': 'Main menu',
    'flow.next': 'Next',
    'flow.back': 'Back',
    'flow.done': 'Done',
    'auth.signIn': 'Sign in',
    'auth.signInWithMicrosoft': 'Sign in with Microsoft',
  },
};

let current: Locale = 'en';
export function setLocale(l: Locale): void { current = l; }
export function t(key: string, fallback?: string): string {
  return catalogue[current]?.[key] ?? fallback ?? key;
}
