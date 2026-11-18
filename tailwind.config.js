/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        bgMain:    '#FBFAF6', // Warm cream surface
        cardBg:    '#FFFFFF',
        brand: {
          black:      '#7A1220', // Deep maroon/red — YG Enterprises primary
          dark:       '#5C0D18', // Darker maroon
          gold:       '#D4AF37',
          goldHover:  '#C5A059',
          goldLight:  '#FBF6E9',
          goldBorder: '#E8D399',
        },
        gold: {
          DEFAULT: '#D4AF37',
          dark:    '#B48811',
          light:   '#FBF6E9',
          border:  '#E8D399',
        },
        maroon: {
          DEFAULT: '#8B1A1A',
          dark:    '#5C0D18',
          light:   '#F7E8E8',
        },
        // Branch accents for POS 1 / POS 2 — resolved from CSS custom properties so
        // each branch's Store Settings > Appearance color can override them at
        // runtime (see src/index.css :root for defaults, src/App.tsx for the sync).
        posOne: {
          DEFAULT: 'var(--pos-one, #8B1A1A)',
          dark:    'var(--pos-one-dark, #5C0D18)',
          light:   'var(--pos-one-light, #F7E8E8)',
        },
        posTwo: {
          DEFAULT: 'var(--pos-two, #B8860B)',
          dark:    'var(--pos-two-dark, #8A6508)',
          light:   'var(--pos-two-light, #FBF3DE)',
        },
        posThree: {
          DEFAULT: 'var(--pos-three, #1E7B43)',
          dark:    'var(--pos-three-dark, #14532D)',
          light:   'var(--pos-three-light, #E4F3EA)',
        },
        textMain:  '#1A0E0E',
        textMuted: '#6B7280',
        borderLight: '#E5E7EB', // Neutral clean border
      },
      fontFamily: {
        sans:      ['"DM Sans"', '"Outfit"', '"Noto Sans Tamil"', 'system-ui', '-apple-system', 'sans-serif'],
        dmsans:    ['"DM Sans"', 'sans-serif'],
        'dm-sans': ['"DM Sans"', 'sans-serif'],
        outfit:    ['"Outfit"', 'sans-serif'],
        brand:     ['"Cinzel"', '"DM Sans"', '"Outfit"', '"Noto Sans Tamil"', 'serif'],
        headline:  ['"DM Sans"', '"Outfit"', '"Noto Sans Tamil"', 'sans-serif'],
      },
      boxShadow: {
        soft:   '0 1px 3px rgba(0,0,0,0.05)',
        gold:   '0 4px 20px -2px rgba(212, 175, 55, 0.25)',
      },
      borderRadius: {
        'card': '12px',
        'btn': '10px',
        'input': '10px',
        'table': '12px',
      },
      animation: {
        'float': 'float 4s ease-in-out infinite',
        'floatDelay': 'float 4s ease-in-out 1.5s infinite',
        'slideUp': 'slideUp 0.6s ease forwards',
        'fadeIn': 'fadeIn 0.5s ease forwards',
      },
      keyframes: {
        float: {
          '0%, 100%': { transform: 'translateY(0px)' },
          '50%': { transform: 'translateY(-10px)' },
        },
        slideUp: {
          from: { opacity: '0', transform: 'translateY(30px)' },
          to: { opacity: '1', transform: 'translateY(0)' },
        },
        fadeIn: {
          from: { opacity: '0' },
          to: { opacity: '1' },
        },
      },
    },
  },
  plugins: [],
}
