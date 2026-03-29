import { createContext, useCallback, useContext, useEffect, useMemo, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { api } from '../api/mockApi';
import { t } from '../i18n';
import type {
  CheckoutPayload,
  CreditsHistoryItem,
  EmployerState,
  EntitlementApplyPayload,
  Lang,
  PaymentMethod,
} from '../types';

type Toast = { id: string; message: string; type: 'error' | 'info' };

interface PaymentsContextValue {
  lang: Lang;
  setLang: (l: Lang) => void;
  employer: EmployerState;
  creditsHistory: CreditsHistoryItem[];
  pendingCheckout: CheckoutPayload | null;
  loading: boolean;
  paying: boolean;
  toasts: Toast[];
  dismissToast: (id: string) => void;
  reloadEmployer: () => Promise<void>;
  reloadCreditsHistory: () => Promise<void>;
  updateEmployer: (partial: Partial<EmployerState>) => Promise<void>;
  beginCheckout: (payload: CheckoutPayload) => void;
  processCheckout: (method: PaymentMethod) => Promise<void>;
  applyEntitlement: (payload: EntitlementApplyPayload) => Promise<void>;
  consumeContactCredit: () => Promise<boolean>;
}

const PaymentsContext = createContext<PaymentsContextValue | null>(null);

const initialEmployer: EmployerState = {
  vatId: '',
  credits: 0,
  plan: 'none',
  verificationStatus: 'none',
  isBusiness: false,
};

export function PaymentsProvider({ children }: { children: React.ReactNode }) {
  const navigate = useNavigate();
  const [lang, setLang] = useState<Lang>('ru');
  const [employer, setEmployer] = useState<EmployerState>(initialEmployer);
  const [creditsHistory, setCreditsHistory] = useState<CreditsHistoryItem[]>([]);
  const [pendingCheckout, setPendingCheckout] = useState<CheckoutPayload | null>(null);
  const [loading, setLoading] = useState(false);
  const [paying, setPaying] = useState(false);
  const [toasts, setToasts] = useState<Toast[]>([]);

  const pushToast = useCallback((message: string, type: Toast['type'] = 'info') => {
    const id = `t_${Date.now()}_${Math.random()}`;
    setToasts((prev) => [{ id, message, type }, ...prev.slice(0, 3)]);
    setTimeout(() => setToasts((prev) => prev.filter((x) => x.id !== id)), 3000);
  }, []);

  const dismissToast = useCallback((id: string) => {
    setToasts((prev) => prev.filter((x) => x.id !== id));
  }, []);

  const reloadEmployer = useCallback(async () => {
    setLoading(true);
    try {
      const data = await api.getEmployer();
      setEmployer(data);
    } catch {
      pushToast(t(lang, 'genericError'), 'error');
    } finally {
      setLoading(false);
    }
  }, [lang, pushToast]);

  const reloadCreditsHistory = useCallback(async () => {
    try {
      const data = await api.getCreditsHistory();
      setCreditsHistory(data.items);
    } catch {
      pushToast(t(lang, 'genericError'), 'error');
    }
  }, [lang, pushToast]);

  useEffect(() => {
    void reloadEmployer();
    void reloadCreditsHistory();
  }, [reloadEmployer, reloadCreditsHistory]);

  const updateEmployer = useCallback(async (partial: Partial<EmployerState>) => {
    const updated = await api.updateEmployer(partial);
    setEmployer(updated);
  }, []);

  const beginCheckout = useCallback(
    (payload: CheckoutPayload) => {
      setPendingCheckout(payload);
      navigate('/checkout');
    },
    [navigate],
  );

  const applyEntitlement = useCallback(
    async (payload: EntitlementApplyPayload) => {
      await api.applyEntitlement(payload);
      await reloadEmployer();
      await reloadCreditsHistory();
    },
    [reloadCreditsHistory, reloadEmployer],
  );

  const processCheckout = useCallback(
    async (method: PaymentMethod) => {
      if (!pendingCheckout) {
        pushToast('No checkout payload', 'error');
        return;
      }
      setPaying(true);
      try {
        await api.checkout({
          ...pendingCheckout,
          isBusiness: employer.isBusiness,
          vatId: employer.vatId,
        });

        await applyEntitlement({
          type: pendingCheckout.product.type,
          payload: {
            productId: pendingCheckout.product.id,
            quantity: pendingCheckout.product.quantity,
            method,
            planId: pendingCheckout.product.id,
          },
        });

        const successPath = pendingCheckout.successPath ?? '/payment/success';
        setPendingCheckout(null);
        navigate(successPath);
      } catch {
        pushToast(t(lang, 'failed'), 'error');
        navigate('/payment/failed');
      } finally {
        setPaying(false);
      }
    },
    [applyEntitlement, employer.isBusiness, employer.vatId, lang, navigate, pendingCheckout, pushToast],
  );

  const consumeContactCredit = useCallback(async () => {
    try {
      await api.consumeContactCredit();
      await reloadEmployer();
      await reloadCreditsHistory();
      return true;
    } catch {
      return false;
    }
  }, [reloadCreditsHistory, reloadEmployer]);

  const value = useMemo<PaymentsContextValue>(
    () => ({
      lang,
      setLang,
      employer,
      creditsHistory,
      pendingCheckout,
      loading,
      paying,
      toasts,
      dismissToast,
      reloadEmployer,
      reloadCreditsHistory,
      updateEmployer,
      beginCheckout,
      processCheckout,
      applyEntitlement,
      consumeContactCredit,
    }),
    [
      lang,
      employer,
      creditsHistory,
      pendingCheckout,
      loading,
      paying,
      toasts,
      dismissToast,
      reloadEmployer,
      reloadCreditsHistory,
      updateEmployer,
      beginCheckout,
      processCheckout,
      applyEntitlement,
      consumeContactCredit,
    ],
  );

  return <PaymentsContext.Provider value={value}>{children}</PaymentsContext.Provider>;
}

export function usePayments() {
  const ctx = useContext(PaymentsContext);
  if (!ctx) throw new Error('usePayments must be used inside PaymentsProvider');
  return ctx;
}
