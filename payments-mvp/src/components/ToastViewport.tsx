import { usePayments } from '../store/PaymentsStore';

export function ToastViewport() {
  const { toasts, dismissToast } = usePayments();
  return (
    <div className="fixed bottom-4 left-1/2 z-50 w-[calc(100%-24px)] max-w-[460px] -translate-x-1/2 space-y-2">
      {toasts.map((t) => (
        <button
          key={t.id}
          onClick={() => dismissToast(t.id)}
          className={`w-full rounded-xl px-4 py-3 text-left text-sm font-medium text-white shadow ${
            t.type === 'error' ? 'bg-red-500' : 'bg-brand-text'
          }`}
        >
          {t.message}
        </button>
      ))}
    </div>
  );
}
