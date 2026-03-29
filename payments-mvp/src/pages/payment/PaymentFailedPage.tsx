import { Link } from 'react-router-dom';
import { Button } from '../../components/Button';
import { Screen } from '../../components/Screen';
import { t } from '../../i18n';
import { usePayments } from '../../store/PaymentsStore';

export function PaymentFailedPage() {
  const { lang } = usePayments();
  return (
    <Screen title={t(lang, 'failed')}>
      <div className="section-card space-y-4 text-center">
        <div className="text-5xl">❌</div>
        <Link to="/checkout">
          <Button>{t(lang, 'retry')}</Button>
        </Link>
      </div>
    </Screen>
  );
}
