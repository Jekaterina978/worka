import { t } from '../i18n';
import { usePayments } from '../store/PaymentsStore';

export function CheckoutSummary() {
  const { pendingCheckout, lang } = usePayments();
  if (!pendingCheckout) return null;

  const p = pendingCheckout.product;
  const title = lang === 'ru' ? p.title : p.titleEn;

  return (
    <div className="section-card">
      <h3 className="text-base font-bold text-brand-text">{title}</h3>
      <p className="mt-1 text-sm text-brand-muted">{t(lang, 'allPaymentsEur')}</p>
      <div className="mt-3 text-2xl font-extrabold text-brand-blue">€{p.amountEur.toFixed(2)}</div>
    </div>
  );
}
