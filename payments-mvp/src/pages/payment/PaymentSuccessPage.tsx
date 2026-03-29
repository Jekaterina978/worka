import { Link } from 'react-router-dom';
import { Button } from '../../components/Button';
import { Screen } from '../../components/Screen';
import { t } from '../../i18n';
import { usePayments } from '../../store/PaymentsStore';

export function PaymentSuccessPage() {
  const { lang } = usePayments();
  return (
    <Screen title={t(lang, 'success')}>
      <div className="section-card space-y-4 text-center">
        <div className="text-5xl">✅</div>
        <p className="text-sm text-brand-muted">{t(lang, 'allPaymentsEur')}</p>
        <Link to="/employer/credits">
          <Button>{t(lang, 'creditsHistory')}</Button>
        </Link>
      </div>
    </Screen>
  );
}
