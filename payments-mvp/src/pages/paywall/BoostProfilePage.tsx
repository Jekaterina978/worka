import { Button } from '../../components/Button';
import { Card } from '../../components/Card';
import { Screen } from '../../components/Screen';
import { JOB_SEEKER_BOOSTS } from '../../lib/pricing';
import { t } from '../../i18n';
import { usePayments } from '../../store/PaymentsStore';

export function BoostProfilePage() {
  const { lang, employer, beginCheckout } = usePayments();

  return (
    <Screen title={t(lang, 'boostProfile')}>
      <div className="space-y-3">
        {JOB_SEEKER_BOOSTS.map((p) => (
          <Card key={p.id}>
            <div className="flex items-center justify-between">
              <h3 className="font-bold">{lang === 'ru' ? p.title : p.titleEn}</h3>
              <p className="font-extrabold text-brand-orange">€{p.amountEur.toFixed(2)}</p>
            </div>
            <div className="mt-3">
              <Button
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
