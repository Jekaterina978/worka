import { useState } from 'react';
import { Button } from '../../components/Button';
import { Card } from '../../components/Card';
import { Screen } from '../../components/Screen';
import { CREDIT_PACKAGES } from '../../lib/pricing';
import { t } from '../../i18n';
import { usePayments } from '../../store/PaymentsStore';

export function ContactPaywallPage() {
  const { employer, lang, beginCheckout, consumeContactCredit, reloadEmployer, toasts } = usePayments();
  const [open, setOpen] = useState(false);
  const [unlocked, setUnlocked] = useState(false);

  const handleContact = async () => {
    if (employer.credits > 0) {
      const ok = await consumeContactCredit();
      if (ok) {
        setUnlocked(true);
      }
      return;
    }
    setOpen(true);
  };

  return (
    <Screen title={t(lang, 'unlockContact')}>
      <div className="space-y-3">
        <Card>
          <p className="text-sm font-semibold text-brand-text">{t(lang, 'creditsBalance')}: {employer.credits}</p>
          <p className="mt-1 text-sm text-brand-muted">{t(lang, 'contactCandidate')}</p>
          <div className="mt-3">
            <Button onClick={() => void handleContact()}>{t(lang, 'contactCandidate')}</Button>
          </div>
          {unlocked && <p className="mt-2 text-sm font-semibold text-green-600">{t(lang, 'contactUnlocked')}</p>}
        </Card>

        {open && (
          <div className="fixed inset-0 z-40 flex items-end bg-black/40 p-3">
            <div className="mx-auto w-full max-w-[480px] rounded-2xl bg-white p-4">
              <p className="text-base font-bold">{t(lang, 'notEnoughCredits')}</p>
              <div className="mt-3 space-y-2">
                {CREDIT_PACKAGES.map((p) => (
                  <button
                    key={p.id}
                    className="w-full rounded-xl border border-brand-border p-3 text-left"
                    onClick={() => {
                      beginCheckout({
                        product: p,
                        mode: 'one_time',
                        isBusiness: employer.isBusiness,
                        vatId: employer.vatId,
                        successPath: '/payment/success',
                      });
                      setOpen(false);
                    }}
                  >
                    <div className="flex items-center justify-between">
                      <span className="font-semibold">{lang === 'ru' ? p.title : p.titleEn}</span>
                      <span className="font-bold text-brand-orange">€{p.amountEur.toFixed(2)}</span>
                    </div>
                  </button>
                ))}
              </div>
              <div className="mt-3 flex gap-2">
                <Button variant="outline" onClick={() => setOpen(false)}>Close</Button>
                <Button variant="orange" onClick={() => void reloadEmployer()}>{t(lang, 'done')}</Button>
              </div>
            </div>
          </div>
        )}
        {toasts.length === 0 ? null : null}
      </div>
    </Screen>
  );
}
