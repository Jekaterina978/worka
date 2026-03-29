import { Button } from '../../components/Button';
import { Card } from '../../components/Card';
import { Screen } from '../../components/Screen';
import { JOB_PROMOTIONS } from '../../lib/pricing';
import { t } from '../../i18n';
import { usePayments } from '../../store/PaymentsStore';

export function PromoteJobPage() {
  const { lang, employer, beginCheckout } = usePayments();

  return (
    <Screen title={t(lang, 'promoteJob')}>
      <div className="space-y-3">
        {JOB_PROMOTIONS.map((p) => (
          <Card key={p.id}>
            <div className="flex items-start justify-between gap-4">
              <div>
                <h3 className="font-bold text-brand-text">{lang === 'ru' ? p.title : p.titleEn}</h3>
                <p className="text-sm text-brand-muted">One-time purchase</p>
              </div>
              <p className="text-lg font-extrabold text-brand-orange">€{p.amountEur.toFixed(2)}</p>
            </div>
            <div className="mt-3">
              <Button
                variant="orange"
                onClick={() =>
                  beginCheckout({
                    product: p,
                    mode: 'one_time',
                    isBusiness: employer.isBusiness,
                    vatId: employer.vatId,
                  })
                }
              >
                {t(lang, 'openCheckout')}
              </Button>
            </div>
          </Card>
        ))}
      </div>
    </Screen>
  );
}
