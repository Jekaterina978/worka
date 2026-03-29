import type {
  CheckoutPayload,
  CreditsHistoryItem,
  EmployerState,
  EntitlementApplyPayload,
} from '../types';

let employerMock: EmployerState = {
  vatId: '',
  credits: 0,
  plan: 'none',
  verificationStatus: 'none',
  isBusiness: false,
};

let creditsHistoryMock: CreditsHistoryItem[] = [];

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

export const api = {
  async createPaymentIntent(body: { productId: string; quantity?: number; vatId?: string }) {
    await sleep(400);
    return { clientSecret: `pi_mock_${body.productId}_${Date.now()}` };
  },

  async createSubscription(body: { planId: string; vatId?: string }) {
    await sleep(500);
    return { clientSecret: `sub_mock_${body.planId}_${Date.now()}` };
  },

  async applyEntitlement(input: EntitlementApplyPayload) {
    await sleep(250);
    if (input.type === 'credits') {
      const add = Number(input.payload.quantity ?? 0);
      employerMock.credits += add;
      creditsHistoryMock = [
        {
          id: `h_${Date.now()}`,
          createdAt: new Date().toISOString(),
          delta: add,
          reason: `Top-up package (${add})`,
        },
        ...creditsHistoryMock,
      ];
    }
    if (input.type === 'subscription') {
      employerMock.plan = String(input.payload.planId) as EmployerState['plan'];
    }
    if (input.type === 'employer_verification') {
      employerMock.verificationStatus = 'pending';
    }
    return { ok: true };
  },

  async getEmployer() {
    await sleep(250);
    return structuredClone(employerMock);
  },

  async updateEmployer(data: Partial<EmployerState>) {
    await sleep(200);
    employerMock = { ...employerMock, ...data };
    return structuredClone(employerMock);
  },

  async uploadVerification() {
    await sleep(500);
    employerMock.verificationStatus = 'pending';
    return { ok: true };
  },

  async getCreditsHistory() {
    await sleep(250);
    return { items: structuredClone(creditsHistoryMock) };
  },

  async consumeContactCredit() {
    await sleep(150);
    if (employerMock.credits <= 0) {
      throw new Error('No credits');
    }
    employerMock.credits -= 1;
    creditsHistoryMock = [
      {
        id: `h_${Date.now()}`,
        createdAt: new Date().toISOString(),
        delta: -1,
        reason: 'Unlock candidate contact',
      },
      ...creditsHistoryMock,
    ];
    return { ok: true };
  },

  async checkout(payload: CheckoutPayload) {
    if (payload.mode === 'subscription') {
      return this.createSubscription({ planId: payload.product.id, vatId: payload.vatId });
    }
    return this.createPaymentIntent({
      productId: payload.product.id,
      quantity: payload.product.quantity,
      vatId: payload.vatId,
    });
  },
};
