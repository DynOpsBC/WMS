export interface Theme {
  id: string;
  name: string;
  background: string;
  surface: string;
  text: string;
  textMuted: string;
  primary: string;
  primaryText: string;
  border: string;
  scheme: 'light' | 'dark';
}

export const LIGHT_THEMES: Theme[] = [
  { id: 'light-default', name: 'Daylight (default)', background: '#f8fafc', surface: '#ffffff', text: '#0f172a', textMuted: '#64748b', primary: '#1670c0', primaryText: '#ffffff', border: '#e2e8f0', scheme: 'light' },
  { id: 'light-warm',    name: 'Warm',               background: '#fdf6e3', surface: '#fffaf0', text: '#3b2e1a', textMuted: '#8a7a5a', primary: '#b45309', primaryText: '#ffffff', border: '#f1e2c4', scheme: 'light' },
  { id: 'light-cool',    name: 'Cool mint',          background: '#f0fdf4', surface: '#ffffff', text: '#064e3b', textMuted: '#475569', primary: '#0d9488', primaryText: '#ffffff', border: '#d1fae5', scheme: 'light' },
];

export const DARK_THEMES: Theme[] = [
  { id: 'dark-default', name: 'Midnight (default)', background: '#0b1220', surface: '#1e293b', text: '#f8fafc', textMuted: '#94a3b8', primary: '#3b82f6', primaryText: '#ffffff', border: '#334155', scheme: 'dark' },
  { id: 'dark-amber',   name: 'Amber HUD',          background: '#1c1305', surface: '#2a1f0c', text: '#fcd34d', textMuted: '#a78b4d', primary: '#f59e0b', primaryText: '#000000', border: '#3f2e10', scheme: 'dark' },
  { id: 'dark-green',   name: 'Night ops',          background: '#0a1410', surface: '#0f1f17', text: '#a7f3d0', textMuted: '#6ee7b7', primary: '#10b981', primaryText: '#000000', border: '#1c2e22', scheme: 'dark' },
];

export const ALL_THEMES = [...LIGHT_THEMES, ...DARK_THEMES];
export const DEFAULT_THEME = LIGHT_THEMES[0]!;
