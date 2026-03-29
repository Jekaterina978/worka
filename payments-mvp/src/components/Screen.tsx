import { ReactNode } from 'react';
import { Link } from 'react-router-dom';
import { LanguageSwitcher } from './LanguageSwitcher';
import { t } from '../i18n';
import { usePayments } from '../store/PaymentsStore';

export function Screen({ title, children }: { title: string; children: ReactNode }) {
  const { lang } = usePayments();
  return (
    <div className="page">
      <header className="mb-4 flex items-center justify-between">
        <h1 className="text-xl font-extrabold text-brand-text">{title}</h1>
        <LanguageSwitcher />
      </header>

      <nav className="mb-4 overflow-x-auto whitespace-nowrap text-xs text-brand-muted">
        <div className="flex gap-3">
          <Link to="/paywall/contact" className="rounded-full border border-brand-border bg-white px-3 py-1">{t(lang, 'unlockContact')}</Link>
          <Link to="/paywall/promote-job" className="rounded-full border border-brand-border bg-white px-3 py-1">{t(lang, 'promoteJob')}</Link>
          <Link to="/employer/verification" className="rounded-full border border-brand-border bg-white px-3 py-1">{t(lang, 'becomeVerified')}</Link>
          <Link to="/employer/plans" className="rounded-full border border-brand-border bg-white px-3 py-1">{t(lang, 'plans')}</Link>
          <Link to="/paywall/boost-profile" className="rounded-full border border-brand-border bg-white px-3 py-1">{t(lang, 'boostProfile')}</Link>
          <Link to="/employer/credits" className="rounded-full border border-brand-border bg-white px-3 py-1">{t(lang, 'creditsHistory')}</Link>
        </div>
      </nav>
      {children}
    </div>
  );
}
