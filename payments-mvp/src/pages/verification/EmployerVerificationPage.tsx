import { useNavigate } from 'react-router-dom';
import { Button } from '../../components/Button';
import { Card } from '../../components/Card';
import { Screen } from '../../components/Screen';
import { EMPLOYER_VERIFICATION } from '../../lib/pricing';
import { t } from '../../i18n';
import { usePayments } from '../../store/PaymentsStore';

export function EmployerVerificationPage() {
  const navigate = useNavigate();
  const { lang, employer, beginCheckout } = usePayments();

  return (
    <Screen title={t(lang, 'becomeVerified')}>
      <Card>
        <p className="text-sm text-brand-muted">{t(lang, 'status')}: <b>{employer.verificationStatus}</b></p>
        <h3 className="mt-2 text-lg font-extrabold text-brand-text">{lang === 'ru' ? EMPLOYER_VERIFICATION.title : EMPLOYER_VERIFICATION.titleEn}</h3>
        <p className="mt-1 text-2xl font-extrabold text-brand-orange">€{EMPLOYER_VERIFICATION.amountEur.toFixed(2)}</p>
        <div className="mt-3 space-y-2">
          <Button
            onClick={() =>
              beginCheckout({
                product: EMPLOYER_VERIFICATION,
                mode: 'one_time',
                isBusiness: employer.isBusiness,
                vatId: employer.vatId,
                successPath: '/employer/verification/upload',
              })
            }
          >
            {t(lang, 'openCheckout')}
          </Button>
          <Button variant="outline" onClick={() => navigate('/employer/verification/status')}>
            {t(lang, 'status')}
          </Button>
        </div>
      </Card>
    </Screen>
  );
}
