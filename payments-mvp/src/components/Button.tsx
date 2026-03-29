import React from 'react';

type Variant = 'blue' | 'orange' | 'outline';

interface Props extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  loading?: boolean;
  variant?: Variant;
  fullWidth?: boolean;
}

export function Button({ loading, children, variant = 'blue', fullWidth = true, className = '', disabled, ...rest }: Props) {
  const base = 'h-12 rounded-full px-5 text-sm font-semibold transition disabled:cursor-not-allowed';
  const map: Record<Variant, string> = {
    blue: 'bg-brand-blue text-white hover:bg-brand-blueHover disabled:bg-blue-300',
    orange: 'bg-brand-orange text-white hover:bg-brand-orangeHover disabled:bg-orange-300',
    outline: 'border border-brand-blue text-brand-blue bg-white hover:bg-blue-50 disabled:text-blue-300 disabled:border-blue-200',
  };

  return (
    <button
      className={`${base} ${map[variant]} ${fullWidth ? 'w-full' : ''} ${className}`}
      disabled={disabled || loading}
      {...rest}
    >
      {loading ? '...' : children}
    </button>
  );
}
