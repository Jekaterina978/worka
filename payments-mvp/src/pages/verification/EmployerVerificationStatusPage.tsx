import { Screen } from '../../components/Screen';
import { Card } from '../../components/Card';
import { t } from '../../i18n';
import { usePayments } from '../../store/PaymentsStore';

export function EmployerVerificationStatusPage() {
  const { lang, employer } = usePayments();

  const map = {
    none: t(lang, 'rejected'),
    pending: t(lang, 'pending'),
    approved: t(lang, 'approved'),
    rejected: t(lang, 'rejected'),
  };

  return (
    <Screen title={t(lang, 'status')}>
      <Card>
        <p className="text-sm text-brand-muted">{t(lang, 'status')}</p>
        <p className="mt-2 text-lg font-bold text-brand-text">{map[employer.verificationStatus]}</p>
      </Card>
    </Screen>
  );
}
