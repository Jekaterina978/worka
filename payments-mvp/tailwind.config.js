/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        brand: {
          blue: '#3B82F6',
          blueHover: '#2563EB',
          orange: '#FF8A00',
          orangeHover: '#F97316',
          bg: '#F6F7FB',
          card: '#FFFFFF',
          border: '#E5E7EB',
          text: '#111827',
          muted: '#6B7280'
        }
      }
    }
  },
  plugins: []
};
