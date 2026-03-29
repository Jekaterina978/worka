import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { api } from '../../api/mockApi';
import { Button } from '../../components/Button';
import { Card } from '../../components/Card';
import { Screen } from '../../components/Screen';
import { t } from '../../i18n';
import { usePayments } from '../../store/PaymentsStore';

export function EmployerVerificationUploadPage() {
  const navigate = useNavigate();
  const { lang, reloadEmployer } = usePayments();
  const [loading, setLoading] = useState(false);

  const upload = async () => {
    setLoading(true);
    await api.uploadVerification();
    await reloadEmployer();
    setLoading(false);
    navigate('/employer/verification/status');
  };

  return (
    <Screen title={t(lang, 'uploadDocs')}>
      <Card>
        <p className="text-sm text-brand-muted">PDF/JPG, up to 10 MB</p>
        <input className="field mt-3" type="file" />
        <div className="mt-3">
          <Button loading={loading} onClick={() => void upload()}>{t(lang, 'sendDocs')}</Button>
        </div>
      </Card>
    </Screen>
  );
}
