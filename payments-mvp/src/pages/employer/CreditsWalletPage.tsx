import { Card } from '../../components/Card';
import { Screen } from '../../components/Screen';
import { t } from '../../i18n';
import { usePayments } from '../../store/PaymentsStore';

export function CreditsWalletPage() {
  const { lang, employer, creditsHistory } = usePayments();

  return (
    <Screen title={t(lang, 'creditsHistory')}>
      <div className="space-y-3">
        <Card>
          <p className="text-sm text-brand-muted">{t(lang, 'creditsBalance')}</p>
          <p className="mt-1 text-2xl font-extrabold text-brand-blue">{employer.credits}</p>
        </Card>
        <Card>
          <h3 className="text-base font-bold text-brand-text">{t(lang, 'creditsHistory')}</h3>
          {creditsHistory.length === 0 ? (
            <p className="mt-2 text-sm text-brand-muted">{t(lang, 'noHistory')}</p>
          ) : (
            <ul className="mt-2 space-y-2">
              {creditsHistory.map((item) => (
                <li key={item.id} className="flex items-start justify-between rounded-xl border border-brand-border px-3 py-2">
                  <div>
                    <p className="text-sm font-medium text-brand-text">{item.reason}</p>
                    <p className="text-xs text-brand-muted">{new Date(item.createdAt).toLocaleString()}</p>
                  </div>
                  <span className={`text-sm font-bold ${item.delta > 0 ? 'text-green-600' : 'text-red-500'}`}>
                    {item.delta > 0 ? '+' : ''}
                    {item.delta}
                  </span>
                </li>
              ))}
            </ul>
          )}
        </Card>
      </div>
    </Screen>
  );
}
