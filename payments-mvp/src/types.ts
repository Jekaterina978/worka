export type Lang = 'ru' | 'en';

export type VerificationStatus = 'none' | 'pending' | 'approved' | 'rejected';

export type PlanId = 'basic' | 'pro' | 'agency' | 'none';

export type PaymentMethod = 'card' | 'apple_pay' | 'google_pay';

export type CheckoutMode = 'one_time' | 'subscription';

export type ProductType =
  | 'employer_verification'
  | 'credits'
  | 'job_promotion'
  | 'subscription'
  | 'job_seeker_boost';

export interface Product {
  id: string;
  type: ProductType;
  title: string;
  titleEn: string;
  amountEur: number;
  quantity?: number;
  metadata?: Record<string, string | number | boolean>;
}

export interface EmployerState {
  vatId?: string;
  credits: number;
  plan: PlanId;
  verificationStatus: VerificationStatus;
  isBusiness: boolean;
}

export interface CreditsHistoryItem {
  id: string;
  createdAt: string;
  delta: number;
  reason: string;
}

export interface CheckoutPayload {
  product: Product;
  vatId?: string;
  isBusiness: boolean;
  mode: CheckoutMode;
  successPath?: string;
}

export interface EntitlementApplyPayload {
  type: ProductType;
  payload: Record<string, unknown>;
}
