import { useNavigate } from 'react-router-dom';
import { Button } from '../components/Button';
import { CheckoutSummary } from '../components/CheckoutSummary';
import { Screen } from '../components/Screen';
import { VatSection } from '../components/VatSection';
import { t } from '../i18n';
import { usePayments } from '../store/PaymentsStore';
import type { PaymentMethod } from '../types';

export function CheckoutPage() {
  const navigate = useNavigate();
  const { lang, pendingCheckout, processCheckout, paying } = usePayments();

  if (!pendingCheckout) {
    return (
      <Screen title="Checkout">
        <div className="section-card">Nothing to pay yet.</div>
      </Screen>
    );
  }

  const methods: Array<{ id: PaymentMethod; label: string }> = [
    { id: 'card', label: 'Card' },
    { id: 'apple_pay', label: 'Apple Pay' },
    { id: 'google_pay', label: 'Google Pay' },
  ];

  return (
    <Screen title="Checkout">
      <div className="space-y-3">
        <CheckoutSummary />
        <VatSection />
        <div className="section-card space-y-2">
          <p className="text-sm font-semibold text-brand-text">{t(lang, 'paymentMethod')}</p>
          {methods.map((m) => (
            <Button key={m.id} variant="blue" loading={paying} onClick={() => void processCheckout(m.id)}>
              {t(lang, 'pay')} · {m.label}
            </Button>
          ))}
        </div>
        <Button variant="outline" onClick={() => navigate(-1)}>
          {t(lang, 'back')}
        </Button>
      </div>
    </Screen>
  );
}
