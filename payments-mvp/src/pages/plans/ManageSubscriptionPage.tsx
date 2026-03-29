import { Button } from '../../components/Button';
import { Card } from '../../components/Card';
import { Screen } from '../../components/Screen';
import { t } from '../../i18n';
import { usePayments } from '../../store/PaymentsStore';

export function ManageSubscriptionPage() {
  const { lang, employer, updateEmployer } = usePayments();

  return (
    <Screen title={t(lang, 'manageSubscription')}>
      <Card>
        <p className="text-sm text-brand-muted">{t(lang, 'planActive')}</p>
        <p className="mt-1 text-lg font-bold text-brand-text">{employer.plan}</p>
        <div className="mt-4">
          <Button variant="outline" onClick={() => void updateEmployer({ plan: 'none' })}>
            Cancel subscription
          </Button>
        </div>
      </Card>
    </Screen>
  );
}
