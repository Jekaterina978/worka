import { usePayments } from '../store/PaymentsStore';

export function LanguageSwitcher() {
  const { lang, setLang } = usePayments();

  return (
    <div className="inline-flex rounded-full border border-brand-border bg-white p-1">
      <button
        className={`rounded-full px-3 py-1 text-xs font-semibold ${lang === 'ru' ? 'bg-brand-blue text-white' : 'text-brand-muted'}`}
        onClick={() => setLang('ru')}
      >
        RU
      </button>
      <button
        className={`rounded-full px-3 py-1 text-xs font-semibold ${lang === 'en' ? 'bg-brand-blue text-white' : 'text-brand-muted'}`}
        onClick={() => setLang('en')}
      >
        EN
      </button>
    </div>
  );
}
