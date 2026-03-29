import { Navigate, Route, Routes } from 'react-router-dom';
import { ToastViewport } from './components/ToastViewport';
import { CheckoutPage } from './pages/CheckoutPage';
import { CreditsWalletPage } from './pages/employer/CreditsWalletPage';
import { PaymentFailedPage } from './pages/payment/PaymentFailedPage';
import { PaymentSuccessPage } from './pages/payment/PaymentSuccessPage';
import { BoostProfilePage } from './pages/paywall/BoostProfilePage';
import { ContactPaywallPage } from './pages/paywall/ContactPaywallPage';
import { PromoteJobPage } from './pages/paywall/PromoteJobPage';
import { ManageSubscriptionPage } from './pages/plans/ManageSubscriptionPage';
import { PlansPage } from './pages/plans/PlansPage';
import { EmployerVerificationPage } from './pages/verification/EmployerVerificationPage';
import { EmployerVerificationStatusPage } from './pages/verification/EmployerVerificationStatusPage';
import { EmployerVerificationUploadPage } from './pages/verification/EmployerVerificationUploadPage';

export default function App() {
  return (
    <>
      <Routes>
        <Route path="/" element={<Navigate to="/paywall/contact" replace />} />

        <Route path="/paywall/contact" element={<ContactPaywallPage />} />
        <Route path="/paywall/promote-job" element={<PromoteJobPage />} />
        <Route path="/paywall/boost-profile" element={<BoostProfilePage />} />

        <Route path="/checkout" element={<CheckoutPage />} />
        <Route path="/payment/success" element={<PaymentSuccessPage />} />
        <Route path="/payment/failed" element={<PaymentFailedPage />} />

        <Route path="/employer/verification" element={<EmployerVerificationPage />} />
        <Route path="/employer/verification/upload" element={<EmployerVerificationUploadPage />} />
        <Route path="/employer/verification/status" element={<EmployerVerificationStatusPage />} />

        <Route path="/employer/credits" element={<CreditsWalletPage />} />
        <Route path="/employer/plans" element={<PlansPage />} />
        <Route path="/employer/plans/manage" element={<ManageSubscriptionPage />} />

        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
      <ToastViewport />
    </>
  );
}
