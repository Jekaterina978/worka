import { t } from '../i18n';
import { usePayments } from '../store/PaymentsStore';

export function VatSection() {
  const { employer, lang, updateEmployer } = usePayments();

  return (
    <div className="space-y-2 rounded-xl border border-brand-border bg-white p-3">
      <label className="flex items-center justify-between text-sm font-medium text-brand-text">
        {t(lang, 'businessToggle')}
        <input
          type="checkbox"
          checked={employer.isBusiness}
          onChange={(e) => void updateEmployer({ isBusiness: e.target.checked })}
        />
      </label>
      {employer.isBusiness && (
        <input
          className="field"
          placeholder={t(lang, 'vatId')}
          value={employer.vatId ?? ''}
          onChange={(e) => void updateEmployer({ vatId: e.target.value })}
        />
      )}
      <p className="text-xs text-brand-muted">{t(lang, 'editVat')}</p>
    </div>
  );
}
