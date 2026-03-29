import { Link } from 'react-router-dom';
import { Button } from '../../components/Button';
import { Card } from '../../components/Card';
import { Screen } from '../../components/Screen';
import { t } from '../../i18n';
import { PLANS } from '../../lib/pricing';
import { usePayments } from '../../store/PaymentsStore';

export function PlansPage() {
  const { lang, employer, beginCheckout } = usePayments();

  return (
    <Screen title={t(lang, 'plans')}>
      <div className="space-y-3">
        {PLANS.map((plan) => {
          const active = employer.plan === plan.id;
          return (
            <Card key={plan.id}>
              <div className="flex items-start justify-between">
                <div>
                  <h3 className="text-lg font-bold text-brand-text">{plan.title}</h3>
                  <p className="text-sm text-brand-muted">€{plan.amountEur}/mo</p>
                </div>
                {active ? <span className="rounded-full bg-blue-100 px-3 py-1 text-xs font-semibold text-brand-blue">{t(lang, 'current')}</span> : null}
              </div>
              <ul className="mt-2 space-y-1 text-sm text-brand-muted">
                {Object.entries(plan.metadata ?? {}).map(([k, v]) => (
                  <li key={k}>• {k}: {String(v)}</li>
                ))}
              </ul>
              <div className="mt-3">
                <Button
                  disabled={active}
                  onClick={() =>
                    beginCheckout({
                      product: plan,
                      mode: 'subscription',
                      isBusiness: employer.isBusiness,
                      vatId: employer.vatId,
                    })
                  }
                >
                  {active ? t(lang, 'planActive') : t(lang, 'subscribe')}
                </Button>
              </div>
            </Card>
          );
        })}
        <Link to="/employer/plans/manage" className="block">
          <Button variant="outline">{t(lang, 'manageSubscription')}</Button>
        </Link>
      </div>
    </Screen>
  );
}
