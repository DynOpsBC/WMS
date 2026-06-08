import type { Config } from 'tailwindcss';

export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        brand: {
          50: '#eaf3fb',
          100: '#cde0f3',
          500: '#1670c0',
          700: '#0b3b66',
          900: '#062441',
        },
      },
    },
  },
  plugins: [],
} satisfies Config;
