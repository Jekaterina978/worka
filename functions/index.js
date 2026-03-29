require('dotenv').config();

const admin = require('firebase-admin');
const cors = require('cors');
const express = require('express');
const Busboy = require('busboy');
const Stripe = require('stripe');
// ai_parser is required lazily inside each route handler so that a missing
// openai package (or misconfigured key) only breaks the AI routes and never
// crashes the entire api function (which would take down payments too).
const { logger } = require('firebase-functions');
const { onRequest } = require('firebase-functions/v2/https');
const { onDocumentDeleted, onDocumentWritten } = require('firebase-functions/v2/firestore');

admin.initializeApp();
require('./firestore-maintenance-guard');

const db = admin.firestore();
const storage = admin.storage();

const REGION = 'europe-west3';
const CURRENCY = 'eur';

const RESPONSES_COLS = ['responses', 'responses_test'];
const BATCH_SIZE = 300;

const STRIPE_SECRET_KEY = process.env.STRIPE_SECRET_KEY || '';
const STRIPE_WEBHOOK_SECRET = process.env.STRIPE_WEBHOOK_SECRET || '';
const STRIPE_API_VERSION = process.env.STRIPE_API_VERSION || '2025-02-24.acacia';
const STRIPE_ENV = String(process.env.STRIPE_ENV || '').trim().toLowerCase();
const FRONTEND_WEB_BASE_URL = (
  process.env.FRONTEND_WEB_BASE_URL
  || 'https://worka-416c0.web.app'
).replace(/\/+$/, '');
const FRONTEND_WEB_ROUTING = (process.env.FRONTEND_WEB_ROUTING || 'hash').trim().toLowerCase();

function buildCheckoutReturnUrl(rawValue, fallbackPath, query = {}) {
  const fallbackUrl = new URL(fallbackPath, `${FRONTEND_WEB_BASE_URL}/`);
  const candidate = String(rawValue || '').trim();

  if (!candidate) {
    Object.entries(query).forEach(([key, value]) => {
      fallbackUrl.searchParams.set(key, value);
    });
    return fallbackUrl.toString();
  }

  try {
    const parsed = new URL(candidate);
    const normalizedPath = parsed.pathname.replace(/\/+$/, '') || '/';
    const isPlaceholderHost = parsed.hostname.includes('example.com');
    const isKnownInvalidPath = normalizedPath.toLowerCase().includes('site-not-found');
    const isWorkaHost = parsed.origin === fallbackUrl.origin;
    const isAllowedReturnPath = normalizedPath === fallbackUrl.pathname;

    if (isPlaceholderHost || isKnownInvalidPath || !isWorkaHost || !isAllowedReturnPath) {
      Object.entries(query).forEach(([key, value]) => {
        fallbackUrl.searchParams.set(key, value);
      });
      return fallbackUrl.toString();
    }

    const normalized = new URL(parsed.toString());
    Object.entries(query).forEach(([key, value]) => {
      normalized.searchParams.set(key, value);
    });
    return normalized.toString();
  } catch (_) {
    Object.entries(query).forEach(([key, value]) => {
      fallbackUrl.searchParams.set(key, value);
    });
    return fallbackUrl.toString();
  }
}

function appendQueryParams(urlString, query = {}) {
  const url = new URL(urlString);
  Object.entries(query).forEach(([key, value]) => {
    const normalized = asString(value);
    if (!normalized) return;
    url.searchParams.set(key, normalized);
  });
  return url.toString();
}

function toHashRoute(urlString) {
  const url = new URL(urlString);
  const path = url.pathname.replace(/^\//, '');
  const qs = url.searchParams.toString();
  url.pathname = '/';
  url.search = '';
  url.hash = `#/${path}${qs ? `?${qs}` : ''}`;
  return url.toString();
}

function getStripeClient() {
  const secretKey = process.env.STRIPE_SECRET_KEY || '';
  if (!secretKey || secretKey.includes('XXXX')) {
    throw new Error('STRIPE_SECRET_KEY is not properly configured');
  }
  return new Stripe(secretKey, { apiVersion: STRIPE_API_VERSION });
}

const stripe = STRIPE_SECRET_KEY
  ? new Stripe(process.env.STRIPE_SECRET_KEY, { apiVersion: STRIPE_API_VERSION })
  : null;

// ---------------------------------------------------------------------------
// Recruiting API forwarding (temporary bridge for jobs/apply/CV endpoints)
// ---------------------------------------------------------------------------
const RECRUITING_API_BASE_URL = (process.env.RECRUITING_API_BASE_URL || '').replace(/\/+$/, '');

function recruitingBaseOrNull() {
  return RECRUITING_API_BASE_URL || null;
}

async function forwardToRecruiting({ req, res, path }) {
  const base = recruitingBaseOrNull();
  if (!base) {
    res.status(501).json({
      error: 'RECRUITING_API_BASE_URL is not set',
      path,
    });
    return;
  }

  const target = `${base}${path}`;
  const headers = {
    'Content-Type': 'application/json',
  };
  const authHeader = req.headers.authorization || req.headers.Authorization;
  if (authHeader) headers.Authorization = authHeader;

  const body =
    req.method === 'POST' || req.method === 'PATCH' || req.method === 'PUT'
      ? JSON.stringify(req.body || {})
      : undefined;

  try {
    const resp = await fetch(target, {
      method: req.method,
      headers,
      body,
    });

    const text = await resp.text();
    const contentType = resp.headers.get('content-type') || '';
    res.status(resp.status);
    if (contentType.includes('application/json')) {
      try {
        res.json(JSON.parse(text));
      } catch (_) {
        res.send(text);
      }
    } else {
      res.send(text);
    }
  } catch (error) {
    logger.error('Recruiting forward failed', {
      path,
      message: error?.message || String(error),
    });
    res.status(502).json({ error: 'Recruiting backend unreachable', path });
  }
}

const IS_FUNCTIONS_EMULATOR = String(process.env.FUNCTIONS_EMULATOR || '').toLowerCase() === 'true';
const REQUIRE_LIVE_STRIPE_KEYS = !IS_FUNCTIONS_EMULATOR && STRIPE_ENV === 'production';
const STRIPE_SECRET_IS_TEST = STRIPE_SECRET_KEY.trim().startsWith('sk_test_');

logger.info('Stripe backend config status', {
  stripeSecretConfigured: STRIPE_SECRET_KEY.trim().length > 0,
  stripeWebhookSecretConfigured: STRIPE_WEBHOOK_SECRET.trim().length > 0,
  stripeApiVersion: STRIPE_API_VERSION,
  stripeEnv: STRIPE_ENV || 'unspecified',
  requireLiveStripeKeys: REQUIRE_LIVE_STRIPE_KEYS,
  functionsEmulator: IS_FUNCTIONS_EMULATOR,
});

if (!IS_FUNCTIONS_EMULATOR && STRIPE_SECRET_KEY.trim().startsWith('sk_test_')) {
  logger.warn('Stripe backend uses TEST secret key outside emulator.');
}
if (REQUIRE_LIVE_STRIPE_KEYS && STRIPE_SECRET_IS_TEST) {
  logger.error(
    'Stripe backend is in production mode but uses TEST secret key. '
      + 'Set STRIPE_SECRET_KEY=sk_live_... or disable STRIPE_ENV=production.',
  );
}

const PRODUCT_CATALOG = {
  contact_1: {
    id: 'contact_1',
    type: 'credits',
    credits: 1,
    amountCents: 299,
    currency: CURRENCY,
    title: '1 контакт',
  },
  contact_10: {
    id: 'contact_10',
    type: 'credits',
    credits: 10,
    amountCents: 2499,
    currency: CURRENCY,
    title: '10 контактов',
  },
  contact_30: {
    id: 'contact_30',
    type: 'credits',
    credits: 30,
    amountCents: 5999,
    currency: CURRENCY,
    title: '30 контактов',
  },
  promotion_bump: {
    id: 'promotion_bump',
    type: 'job_boost',
    boostType: 'bump',
    amountCents: 499,
    durationHours: 72,
    currency: CURRENCY,
    title: 'Поднять вакансию (72ч)',
  },
  promotion_urgent: {
    id: 'promotion_urgent',
    type: 'job_boost',
    boostType: 'urgent',
    amountCents: 799,
    durationHours: 24 * 7,
    currency: CURRENCY,
    title: 'Срочно (7д)',
  },
  highlight_job_7d: {
    id: 'highlight_job_7d',
    type: 'job_boost',
    boostType: 'highlight',
    amountCents: 699,
    durationHours: 24 * 7,
    currency: CURRENCY,
    title: 'Выделение вакансии (7д)',
  },
  promotion_show_employer_contacts: {
    id: 'promotion_show_employer_contacts',
    type: 'vacancy_feature',
    vacancyFeatureType: 'show_employer_contacts',
    amountCents: 5000,
    currency: CURRENCY,
    title: 'Показать контакты работодателя',
  },
  employer_verification: {
    id: 'employer_verification',
    type: 'verification',
    amountCents: 1900,
    currency: CURRENCY,
    title: 'Верификация работодателя',
  },
};

const VACANCY_PRODUCT_ALIAS_TO_BACKEND = {
  highlight_job_7d: 'highlight_job_7d',
  job_highlight: 'highlight_job_7d',
  promotion_urgent: 'promotion_urgent',
  job_urgent: 'promotion_urgent',
  promotion_bump: 'promotion_bump',
  job_boost: 'promotion_bump',
  promotion_show_employer_contacts: 'promotion_show_employer_contacts',
  job_show_employer_contacts: 'promotion_show_employer_contacts',
};

const VACANCY_BACKEND_TO_CANONICAL = {
  highlight_job_7d: 'job_highlight',
  promotion_urgent: 'job_urgent',
  promotion_bump: 'job_boost',
  promotion_show_employer_contacts: 'job_show_employer_contacts',
};

function isVacancyMonetizationProduct(product) {
  return Boolean(
    product
      && (
        product.type === 'job_boost'
        || product.type === 'vacancy_feature'
      ),
  );
}

function resolveVacancyProduct(rawValue) {
  const requestedId = asString(rawValue);
  const backendProductId = asString(
    VACANCY_PRODUCT_ALIAS_TO_BACKEND[requestedId] || requestedId,
  );
  const product = PRODUCT_CATALOG[backendProductId];
  if (!product || !isVacancyMonetizationProduct(product)) {
    return {
      requestedId,
      backendProductId,
      canonicalProductId: '',
      product,
    };
  }
  return {
    requestedId,
    backendProductId,
    canonicalProductId: asString(
      VACANCY_BACKEND_TO_CANONICAL[backendProductId] || requestedId,
    ),
    product,
  };
}

function requireStripe(res) {
  if (!stripe) {
    res.status(500).json({
      error: 'Stripe is not configured on backend (missing STRIPE_SECRET_KEY).',
    });
    return false;
  }
  if (REQUIRE_LIVE_STRIPE_KEYS && STRIPE_SECRET_IS_TEST) {
    res.status(500).json({
      error: 'Stripe backend is in production mode with test secret key.',
    });
    return false;
  }
  return true;
}

function parseBearerToken(req) {
  const header = req.headers.authorization || req.headers.Authorization || '';
  const value = String(header).trim();
  if (!value.toLowerCase().startsWith('bearer ')) return null;
  const token = value.slice(7).trim();
  return token || null;
}

async function requireAuth(req, res, next) {
  if (req.method === 'OPTIONS') {
    next();
    return;
  }
  try {
    const token = parseBearerToken(req);
    if (!token) {
      res.status(401).json({ error: 'Missing Bearer token' });
      return;
    }

    const decoded = await admin.auth().verifyIdToken(token, true);
    const provider = asString(decoded?.firebase?.sign_in_provider).toLowerCase();
    if (provider === 'anonymous') {
      res.status(403).json({ error: 'Anonymous auth is not allowed for payments API' });
      return;
    }
    req.auth = {
      uid: decoded.uid,
      email: decoded.email || '',
      name: decoded.name || '',
    };
    next();
  } catch (error) {
    logger.warn('Auth verification failed', {
      message: error?.message || String(error),
    });
    res.status(401).json({ error: 'Invalid auth token' });
  }
}

async function resolveOptionalAuth(req) {
  const token = parseBearerToken(req);
  if (!token) return null;

  const decoded = await admin.auth().verifyIdToken(token, true);
  const provider = asString(decoded?.firebase?.sign_in_provider).toLowerCase();
  if (provider === 'anonymous') {
    throw new Error('Anonymous auth is not allowed for payments API');
  }
  return {
    uid: decoded.uid,
    email: decoded.email || '',
    name: decoded.name || '',
  };
}

function nowIso() {
  return new Date().toISOString();
}

function asString(v) {
  return String(v == null ? '' : v).trim();
}

function asPositiveInt(v, fallback = 1) {
  const n = Number(v);
  if (!Number.isFinite(n)) return fallback;
  const i = Math.floor(n);
  return i > 0 ? i : fallback;
}

function entitlementFailurePatch(code, message) {
  return {
    entitlements_applied: false,
    fulfillment_status: 'failed',
    fulfillment_error_code: code,
    fulfillment_error_message: message,
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
  };
}

function entitlementFailurePatch(code, message) {
  return {
    entitlements_applied: false,
    fulfillment_status: 'failed',
    fulfillment_error_code: code,
    fulfillment_error_message: message,
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
  };
}

function parseEuroAmountToCents(value) {
  const raw = Number(value);
  if (!Number.isFinite(raw) || raw <= 0) return 0;
  return Math.round(raw * 100);
}

function employersRef(uid) {
  return db.collection('employers').doc(uid);
}

function usersRef(uid) {
  return db.collection('users').doc(uid);
}

function purchasesCol() {
  return db.collection('purchases');
}

function pendingPurchasesCol() {
  return db.collection('pending_purchases');
}

function creditLedgerCol() {
  return db.collection('credit_ledger');
}

function stripeWebhookEventsCol() {
  return db.collection('stripe_webhook_events');
}

function jobBoostsCol() {
  return db.collection('job_boosts');
}

function verificationRequestsRef(uid) {
  return db.collection('verification_requests').doc(uid);
}

function contactUnlockRef(uid, candidateId) {
  return employersRef(uid).collection('contact_unlocks').doc(candidateId);
}

function computeCreditsBalance(data) {
  const direct = Number(data?.credits_balance);
  if (Number.isFinite(direct)) return Math.max(0, Math.floor(direct));

  const legacy = Number(data?.credits);
  if (Number.isFinite(legacy)) return Math.max(0, Math.floor(legacy));

  return 0;
}

async function loadOwnedJobOrThrow(jobId, employerId) {
  const normalizedJobId = asString(jobId);
  const normalizedEmployerId = asString(employerId);

  if (!normalizedJobId) {
    const error = new Error('JOB_ID_REQUIRED');
    error.statusCode = 400;
    throw error;
  }

  if (!normalizedEmployerId) {
    const error = new Error('AUTH_REQUIRED');
    error.statusCode = 401;
    throw error;
  }

  const jobRef = db.collection('jobs').doc(normalizedJobId);
  const jobSnap = await jobRef.get();

  if (!jobSnap.exists) {
    const error = new Error('JOB_NOT_FOUND');
    error.statusCode = 404;
    throw error;
  }

  const job = jobSnap.data() || {};
  const ownerId = asString(job.ownerId || job.ownerUid || job.owner_id);

  if (!ownerId || ownerId !== normalizedEmployerId) {
    const error = new Error('JOB_OWNER_MISMATCH');
    error.statusCode = 403;
    throw error;
  }

  return {
    ref: jobRef,
    snap: jobSnap,
    data: job,
    ownerId,
    jobId: normalizedJobId,
  };
}

async function markPurchaseEntitlementFailed({
  purchaseRef,
  purchaseData,
  code,
  message,
  paymentIntent,
  sessionId = '',
}) {
  const normalizedCode = asString(code) || 'entitlement_failed';
  const normalizedMessage = asString(message) || normalizedCode;

  await purchaseRef.set({
    ...((purchaseData && typeof purchaseData === 'object') ? purchaseData : {}),
    stripe_payment_intent_id: asString(paymentIntent?.id),
    stripe_payment_intent_status: asString(paymentIntent?.status),
    stripe_checkout_session_id: asString(sessionId),
    status: 'failed_entitlement',
    fulfillment_status: 'failed',
    fulfillment_error_code: normalizedCode,
    fulfillment_error_message: normalizedMessage,
    entitlements_applied: false,
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
    created_at:
      purchaseData?.created_at || admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
}

async function hasEntitlementBeenApplied(paymentIntentId) {
  const state = await loadPendingOrPurchaseByPaymentIntentId(paymentIntentId);
  const data = state?.data || {};
  return data.entitlements_applied === true
    || asString(data.fulfillment_status) === 'applied';
}

async function upsertEmployerBilling({ uid, email, vatId }) {
  const update = {
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
  };
  if (email) update.email = email;
  if (vatId) update.vat_id = vatId;

  await employersRef(uid).set(update, { merge: true });

  const userBillingPatch = {
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  if (vatId) {
    userBillingPatch.billing = {
      vatId,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
  }
  await usersRef(uid).set(userBillingPatch, { merge: true });
}

async function resolveStripeCustomer({ uid, email, vatId }) {
  const snap = await employersRef(uid).get();
  const data = snap.exists ? snap.data() || {} : {};
  let customerId = asString(data.stripe_customer_id);

  if (customerId) {
    await stripe.customers.update(customerId, {
      email: email || undefined,
      metadata: {
        employer_id: uid,
        vat_id: vatId || asString(data.vat_id) || '',
      },
    });
    return customerId;
  }

  const customer = await stripe.customers.create({
    email: email || undefined,
    metadata: {
      employer_id: uid,
      vat_id: vatId || '',
    },
  });
  customerId = customer.id;

  await employersRef(uid).set(
    {
      stripe_customer_id: customerId,
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  if (vatId) {
    try {
      await stripe.customers.createTaxId(customerId, {
        type: 'eu_vat',
        value: vatId,
      });
    } catch (error) {
      logger.warn('Failed to attach VAT tax ID to Stripe customer', {
        uid,
        customerId,
        message: error?.message || String(error),
      });
    }
  }

  return customerId;
}

function purchasePayload({
  uid,
  email,
  product,
  quantity,
  context,
  vatId,
  paymentIntent,
}) {
  return {
    employer_id: uid,
    employer_email: email || '',
    product_id: product.id,
    product_type: product.type,
    payment_status: 'pending',
    fulfillment_status: 'pending',
    quantity,
    amount: paymentIntent.amount,
    currency: paymentIntent.currency,
    status: 'requires_payment',
    vat_id: vatId || '',
    context,
    stripe_payment_intent_id: paymentIntent.id,
    stripe_customer_id: paymentIntent.customer || '',
    stripe_client_secret: paymentIntent.client_secret || '',
    created_at: admin.firestore.FieldValue.serverTimestamp(),
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
  };
}

function pendingPurchasePayload(args) {
  return {
    ...purchasePayload(args),
    status: 'pending',
  };
}

function checkoutPendingPurchasePayload({
  uid,
  email,
  product,
  jobId,
  paymentIntent,
  session,
}) {
  const base = pendingPurchasePayload({
    uid,
    email,
    product,
    quantity: 1,
    context: jobId ? { jobId } : {},
    vatId: '',
    paymentIntent,
  });
  return {
    ...base,
    stripe_checkout_session_id: asString(session?.id),
    stripe_checkout_status: asString(session?.status),
    stripe_checkout_payment_status: asString(session?.payment_status),
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
  };
}

function validateSucceededPaymentIntent({ paymentIntent, purchaseData }) {
  const data = purchaseData && typeof purchaseData === 'object'
    ? purchaseData
    : {};
  const metadata = paymentIntent?.metadata && typeof paymentIntent.metadata === 'object'
    ? paymentIntent.metadata
    : {};

  const purchaseEmployerId = asString(data.employer_id);
  const metadataEmployerId = asString(metadata.userId || metadata.employer_id);
  if (!purchaseEmployerId || !metadataEmployerId || purchaseEmployerId !== metadataEmployerId) {
    return {
      ok: false,
      code: 'metadata_employer_mismatch',
      message: `purchase.employer_id=${purchaseEmployerId} metadata.userId=${metadataEmployerId}`,
    };
  }

  const purchaseProductId = asString(data.product_id);
  const metadataProductId = asString(metadata.productId || metadata.product_id);
  const productId = purchaseProductId || metadataProductId;
  if (!purchaseProductId) {
    return {
      ok: false,
      code: 'missing_purchase_product',
      message: 'purchase.product_id is missing',
    };
  }
  const product = PRODUCT_CATALOG[productId];
  if (!product) {
    return {
      ok: false,
      code: 'unknown_product',
      message: `product_id=${productId}`,
    };
  }
  if (!purchaseProductId || !metadataProductId || purchaseProductId !== metadataProductId) {
    return {
      ok: false,
      code: 'metadata_product_mismatch',
      message: `purchase.product_id=${purchaseProductId} metadata.productId=${metadataProductId}`,
    };
  }

  const purchaseQuantity = asPositiveInt(data.quantity, 1);
  const metadataQuantity = asPositiveInt(metadata.quantity, 1);
  if (purchaseQuantity !== metadataQuantity) {
    return {
      ok: false,
      code: 'metadata_quantity_mismatch',
      message: `purchase.quantity=${purchaseQuantity} metadata.quantity=${metadataQuantity}`,
    };
  }

  const expectedAmount = product.amountCents * purchaseQuantity;
  const intentAmount = Number(paymentIntent?.amount || 0);
  if (intentAmount !== expectedAmount) {
    return {
      ok: false,
      code: 'amount_mismatch',
      message: `intent.amount=${intentAmount} expected=${expectedAmount}`,
    };
  }

  const expectedCurrency = asString(product.currency).toLowerCase();
  const intentCurrency = asString(paymentIntent?.currency).toLowerCase();
  if (!intentCurrency || intentCurrency !== expectedCurrency) {
    return {
      ok: false,
      code: 'currency_mismatch',
      message: `intent.currency=${intentCurrency} expected=${expectedCurrency}`,
    };
  }

  return { ok: true, productId, quantity: purchaseQuantity };
}

async function markWebhookEvent({
  eventId,
  paymentIntentId,
  status,
  details = {},
}) {
  const safeEventId = asString(eventId);
  if (!safeEventId) return;
  await stripeWebhookEventsCol().doc(safeEventId).set(
    {
      event_id: safeEventId,
      payment_intent_id: asString(paymentIntentId),
      status: asString(status),
      details,
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
      created_at: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
}

async function appendCreditLedger({
  employerId,
  delta,
  reason,
  refId,
  meta = {},
}) {
  await creditLedgerCol().add({
    employer_id: employerId,
    delta,
    reason,
    ref_id: refId || '',
    meta,
    created_at: admin.firestore.FieldValue.serverTimestamp(),
  });
}

async function applyPaymentEntitlement({ purchaseRef, purchaseData, paymentIntent }) {
  let outcome = {
    applied: false,
    code: '',
    message: '',
  };

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(purchaseRef);
    if (!snap.exists) {
      outcome = {
        applied: false,
        code: 'purchase_not_found',
        message: 'purchase document does not exist',
      };
      return;
    }

    const current = snap.data() || {};

    if (current.entitlements_applied === true) {
      outcome = {
        applied: true,
        code: 'already_applied',
        message: 'entitlements already applied',
      };
      return;
    }

    const employerId = asString(current.employer_id);
    if (!employerId) {
      const code = 'missing_employer_id';
      const message = 'missing employer_id';
      tx.set(purchaseRef, {
        status: 'failed_entitlement',
        fulfillment_status: 'failed',
        fulfillment_error_code: code,
        fulfillment_error_message: message,
        entitlements_apply_error: message,
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
      outcome = { applied: false, code, message };
      return;
    }

    const employerDocRef = employersRef(employerId);
    const employerSnap = await tx.get(employerDocRef);
    const employer = employerSnap.exists ? employerSnap.data() || {} : {};

    const productId = asString(current.product_id);
    const product = PRODUCT_CATALOG[productId];
    if (!product) {
      const code = 'unknown_product';
      const message = `unknown product ${productId}`;
      tx.set(purchaseRef, {
        status: 'failed_entitlement',
        fulfillment_status: 'failed',
        fulfillment_error_code: code,
        fulfillment_error_message: message,
        entitlements_apply_error: message,
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
      outcome = { applied: false, code, message };
      return;
    }

    if (product.type === 'credits') {
      const qty = asPositiveInt(current.quantity, 1);
      const addCredits = product.credits * qty;
      const currentBalance = computeCreditsBalance(employer);
      const nextBalance = currentBalance + addCredits;

      tx.set(employerDocRef, {
        credits_balance: nextBalance,
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
        vat_id: asString(current.vat_id) || asString(employer.vat_id),
      }, { merge: true });

      tx.set(usersRef(employerId), {
        billing: {
          creditsBalance: nextBalance,
          vatId: asString(current.vat_id) || asString(employer.vat_id),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });

      const ledgerRef = creditLedgerCol().doc();
      tx.set(ledgerRef, {
        employer_id: employerId,
        delta: addCredits,
        reason: 'purchase_credits',
        ref_id: purchaseRef.id,
        meta: { product_id: product.id, payment_intent_id: paymentIntent.id },
        created_at: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    if (product.type === 'job_boost') {
      const context = current.context && typeof current.context === 'object' ? current.context : {};
      const jobId = asString(context.jobId);
      const vacancyRef = db.collection('jobs').doc(jobId);
      const vacancySnap = await tx.get(vacancyRef);

      if (!vacancySnap.exists) {
        const code = 'job_not_found';
        const message = `job ${jobId} not found`;
        tx.set(purchaseRef, {
          status: 'failed_entitlement',
          fulfillment_status: 'failed',
          fulfillment_error_code: code,
          fulfillment_error_message: message,
          entitlements_apply_error: message,
          updated_at: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        outcome = { applied: false, code, message };
        return;
      }

      const vacancy = vacancySnap.data() || {};
      const vacancyOwnerId = asString(vacancy.ownerId || vacancy.ownerUid || vacancy.owner_id);

      if (!vacancyOwnerId || vacancyOwnerId !== employerId) {
        const code = 'job_owner_mismatch';
        const message = `job.owner=${vacancyOwnerId} employer=${employerId}`;
        tx.set(purchaseRef, {
          status: 'failed_entitlement',
          fulfillment_status: 'failed',
          fulfillment_error_code: code,
          fulfillment_error_message: message,
          entitlements_apply_error: message,
          updated_at: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        outcome = { applied: false, code, message };
        return;
      }

      const activeUntil = admin.firestore.Timestamp.fromDate(
        new Date(Date.now() + product.durationHours * 60 * 60 * 1000),
      );

      const boostRef = jobBoostsCol().doc();
      tx.set(boostRef, {
        employer_id: employerId,
        job_id: jobId,
        type: product.boostType,
        source_product_id: product.id,
        status: 'active',
        active_from: admin.firestore.FieldValue.serverTimestamp(),
        active_until: activeUntil,
        created_at: admin.firestore.FieldValue.serverTimestamp(),
      });

      const vacancyPatch = {
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        paidServices: admin.firestore.FieldValue.arrayUnion(product.boostType),
      };

      if (product.boostType === 'bump') {
        vacancyPatch.bumpActiveUntil = activeUntil;
      } else if (product.boostType === 'urgent') {
        vacancyPatch.urgentActiveUntil = activeUntil;
        vacancyPatch.isUrgent = true;
        vacancyPatch.paidUrgent = true;
        vacancyPatch.urgentRequested = false;
      } else if (product.boostType === 'top_category') {
        vacancyPatch.topCategoryActiveUntil = activeUntil;
      } else if (product.boostType === 'highlight') {
        vacancyPatch.highlightActiveUntil = activeUntil;
      }

      tx.set(vacancyRef, vacancyPatch, { merge: true });
    }

    if (product.type === 'vacancy_feature') {
      const context = current.context && typeof current.context === 'object' ? current.context : {};
      const jobId = asString(context.jobId);
      const vacancyRef = db.collection('jobs').doc(jobId);
      const vacancySnap = await tx.get(vacancyRef);

      if (!vacancySnap.exists) {
        const code = 'job_not_found';
        const message = `job ${jobId} not found`;
        tx.set(purchaseRef, {
          status: 'failed_entitlement',
          fulfillment_status: 'failed',
          fulfillment_error_code: code,
          fulfillment_error_message: message,
          entitlements_apply_error: message,
          updated_at: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        outcome = { applied: false, code, message };
        return;
      }

      const vacancy = vacancySnap.data() || {};
      const vacancyOwnerId = asString(vacancy.ownerId || vacancy.ownerUid || vacancy.owner_id);

      if (!vacancyOwnerId || vacancyOwnerId !== employerId) {
        const code = 'job_owner_mismatch';
        const message = `job.owner=${vacancyOwnerId} employer=${employerId}`;
        tx.set(purchaseRef, {
          status: 'failed_entitlement',
          fulfillment_status: 'failed',
          fulfillment_error_code: code,
          fulfillment_error_message: message,
          entitlements_apply_error: message,
          updated_at: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        outcome = { applied: false, code, message };
        return;
      }

      const vacancyPatch = {
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };

      if (product.vacancyFeatureType === 'show_employer_contacts') {
        vacancyPatch.showContacts = true;
        vacancyPatch.showEmployerContactsUnlockedAt = admin.firestore.FieldValue.serverTimestamp();
        vacancyPatch.paidServices = admin.firestore.FieldValue.arrayUnion('show_employer_contacts');
      }

      tx.set(vacancyRef, vacancyPatch, { merge: true });
    }

    if (product.type === 'verification') {
      const requestRef = verificationRequestsRef(employerId);
      tx.set(requestRef, {
        employer_id: employerId,
        status: 'pending',
        source_purchase_id: purchaseRef.id,
        source_payment_intent_id: paymentIntent.id,
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
        created_at: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });

      tx.set(employerDocRef, {
        verification_status: 'pending',
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
        vat_id: asString(current.vat_id) || asString(employer.vat_id),
      }, { merge: true });

      tx.set(usersRef(employerId), {
        billing: {
          verificationStatus: 'pending',
          vatId: asString(current.vat_id) || asString(employer.vat_id),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
    }

    tx.set(purchaseRef, {
      status: 'succeeded',
      fulfillment_status: 'applied',
      fulfillment_error_code: admin.firestore.FieldValue.delete(),
      fulfillment_error_message: admin.firestore.FieldValue.delete(),
      entitlements_apply_error: admin.firestore.FieldValue.delete(),
      entitlements_applied: true,
      entitlements_applied_at: admin.firestore.FieldValue.serverTimestamp(),
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    outcome = {
      applied: true,
      code: 'applied',
      message: 'entitlements applied',
    };
  });

  return outcome;
}

async function ensureCheckoutSessionProcessed(session) {
  const stripeClient = getStripeClient();
  const metadata = session?.metadata && typeof session.metadata === 'object'
    ? session.metadata
    : {};
  const userId = asString(metadata.userId || metadata.employer_id);
  const resolvedVacancyProduct = resolveVacancyProduct(
    metadata.canonicalProductId || metadata.canonical_product_id
      || metadata.productId || metadata.product_id || metadata.featureKey,
  );
  const productId = asString(
    resolvedVacancyProduct.backendProductId
      || metadata.productId || metadata.product_id || metadata.featureKey,
  );
  const canonicalProductId = asString(resolvedVacancyProduct.canonicalProductId);
  const jobId = asString(metadata.context_job_id);
  const sessionId = asString(session?.id);
  const product = PRODUCT_CATALOG[productId];
  const checkoutStatus = asString(session?.status).toLowerCase();
  const checkoutPaymentStatus = asString(session?.payment_status).toLowerCase();

  if (!userId || !product) {
    return {
      applied: false,
      status: 'invalid_metadata',
      userId,
      productId,
      canonicalProductId,
      jobId,
      sessionId,
    };
  }
  if (isVacancyMonetizationProduct(product) && !jobId) {
    return {
      applied: false,
      status: 'missing_job_id',
      userId,
      productId,
      canonicalProductId,
      jobId,
      sessionId,
    };
  }

  if (checkoutPaymentStatus !== 'paid') {
    return {
      applied: false,
      status: checkoutStatus === 'expired' ? 'checkout_expired' : 'checkout_not_paid',
      userId,
      productId,
      canonicalProductId,
      jobId,
      sessionId,
      checkoutStatus,
      paymentStatus: checkoutPaymentStatus,
    };
  }

  const paymentIntentId = asString(session?.payment_intent?.id || session?.payment_intent);
  if (!paymentIntentId) {
    return {
      applied: false,
      status: 'missing_payment_intent',
      userId,
      productId,
      canonicalProductId,
      jobId,
      sessionId,
    };
  }

  const paymentIntent = typeof session?.payment_intent === 'object' && session.payment_intent
    ? session.payment_intent
    : await stripeClient.paymentIntents.retrieve(paymentIntentId);
  const checkoutEmail = asString(
    session?.customer_details?.email || session?.customer_email || paymentIntent?.receipt_email,
  );
  const purchaseRef = pendingPurchasesCol().doc(paymentIntent.id);

  await purchaseRef.set(
    checkoutPendingPurchasePayload({
      uid: userId,
      email: checkoutEmail,
      product,
      jobId,
      paymentIntent,
      session,
    }),
    { merge: true },
  );

  const state = await loadPendingOrPurchaseByPaymentIntentId(paymentIntent.id);
  const purchaseData = state?.data || {};
  const validation = validateSucceededPaymentIntent({
    paymentIntent,
    purchaseData,
  });

  if (!validation.ok) {
    await purchaseRef.set(
      {
        status: 'validation_failed',
        validation_error_code: validation.code,
        validation_error_message: validation.message,
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    return {
      applied: false,
      status: 'validation_failed',
      validationCode: validation.code,
      validationMessage: validation.message,
      userId,
      productId,
      canonicalProductId,
      jobId,
      sessionId,
      paymentIntentId: paymentIntent.id,
    };
  }

  if (asString(paymentIntent?.status).toLowerCase() !== 'succeeded') {
    return {
      applied: false,
      status: 'awaiting_payment_confirmation',
      userId,
      productId,
      canonicalProductId,
      jobId,
      sessionId,
      paymentIntentId: paymentIntent.id,
      paymentIntentStatus: asString(paymentIntent?.status),
    };
  }

  const finalPurchaseRef = state?.purchaseRef || purchasesCol().doc(paymentIntent.id);
  await finalPurchaseRef.set(
    {
      ...purchaseData,
      stripe_payment_intent_id: paymentIntent.id,
      stripe_payment_intent_status: paymentIntent.status,
      stripe_checkout_session_id: sessionId,
      status: 'succeeded',
      payment_status: 'succeeded',
      fulfillment_status: 'pending',
      paid_at: admin.firestore.FieldValue.serverTimestamp(),
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
      created_at: purchaseData.created_at || admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  const entitlementResult = await applyPaymentEntitlement({
    purchaseRef: finalPurchaseRef,
    purchaseData,
    paymentIntent,
  });
  await purchaseRef.delete();

  if (!entitlementResult.applied) {
    return {
      applied: false,
      status: 'failed_entitlement',
      errorCode: asString(entitlementResult.code),
      errorMessage: asString(entitlementResult.message),
      userId,
      productId,
      canonicalProductId,
      jobId,
      sessionId,
      paymentIntentId: paymentIntent.id,
      paymentIntentStatus: asString(paymentIntent?.status),
    };
  }

  return {
    applied: true,
    status: 'applied',
    userId,
    productId,
    canonicalProductId,
    jobId,
    sessionId,
    paymentIntentId: paymentIntent.id,
    paymentIntentStatus: asString(paymentIntent?.status),
  };
}

async function findPurchaseByPaymentIntentId(paymentIntentId) {
  const byId = await purchasesCol().doc(paymentIntentId).get();
  if (byId.exists) return byId.ref;

  const snap = await purchasesCol()
    .where('stripe_payment_intent_id', '==', paymentIntentId)
    .limit(1)
    .get();

  if (snap.empty) return null;
  return snap.docs[0].ref;
}

async function loadPendingOrPurchaseByPaymentIntentId(paymentIntentId) {
  const pendingRef = pendingPurchasesCol().doc(paymentIntentId);
  const pendingSnap = await pendingRef.get();
  if (pendingSnap.exists) {
    return {
      source: 'pending',
      pendingRef,
      purchaseRef: purchasesCol().doc(paymentIntentId),
      data: pendingSnap.data() || {},
    };
  }

  const purchaseRef = await findPurchaseByPaymentIntentId(paymentIntentId);
  if (!purchaseRef) return null;
  const purchaseSnap = await purchaseRef.get();
  return {
    source: 'purchase',
    pendingRef: null,
    purchaseRef,
    data: purchaseSnap.exists ? (purchaseSnap.data() || {}) : {},
  };
}

async function markPaymentFailed({ paymentIntent, reason }) {
  const state = await loadPendingOrPurchaseByPaymentIntentId(paymentIntent.id);
  const base = state?.data || {};
  const currentStatus = asString(base.status).toLowerCase();
  const alreadyApplied = base.entitlements_applied === true;
  if (alreadyApplied || currentStatus.startsWith('succeeded')) {
    logger.warn('markPaymentFailed ignored for already succeeded purchase', {
      paymentIntentId: paymentIntent.id,
      currentStatus,
      alreadyApplied,
      reason,
    });
    if (state?.pendingRef) {
      await state.pendingRef.delete();
    }
    return;
  }
  const finalRef = purchasesCol().doc(paymentIntent.id);

  await finalRef.set(
    {
      ...base,
      stripe_payment_intent_id: paymentIntent.id,
      status: 'failed',
      failure_reason: reason || '',
      amount: paymentIntent.amount || base.amount || 0,
      currency: paymentIntent.currency || base.currency || CURRENCY,
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
      created_at: base.created_at || admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  if (state?.pendingRef) {
    await state.pendingRef.delete();
  }
}

async function parseMultipart(req) {
  return new Promise((resolve, reject) => {
    const busboy = Busboy({ headers: req.headers });
    const fields = {};
    const files = [];

    busboy.on('field', (name, val) => {
      fields[name] = val;
    });

    busboy.on('file', (name, stream, info) => {
      const chunks = [];
      stream.on('data', (chunk) => chunks.push(chunk));
      stream.on('error', reject);
      stream.on('end', () => {
        files.push({
          fieldName: name,
          filename: info.filename,
          mimeType: info.mimeType,
          buffer: Buffer.concat(chunks),
        });
      });
    });

    busboy.on('error', reject);
    busboy.on('finish', () => resolve({ fields, files }));

    const raw = req.rawBody;
    if (raw && raw.length) {
      busboy.end(raw);
      return;
    }

    const chunks = [];
    req.on('data', (chunk) => chunks.push(chunk));
    req.on('end', () => busboy.end(Buffer.concat(chunks)));
    req.on('error', reject);
  });
}

const SENSITIVE_CV_CONTACT_KEYS = [
  'email',
  'phone',
  'phoneNumber',
  'phoneCountryCode',
  'whatsapp',
  'telegram',
  'viber',
  'messenger',
  'tg',
  'wa',
  'facebookMessenger',
  'contactEmail',
  'contactPhone',
];

function candidateContactsPrivateRef(candidateId) {
  return db.collection('candidate_contacts_private').doc(candidateId);
}

function extractCandidateContactPayload(candidateId, cvData) {
  const contacts = cvData && typeof cvData.contacts === 'object'
    ? cvData.contacts
    : {};
  const ownerId = asString(cvData.ownerId || cvData.ownerUid);
  const firstName = asString(contacts.firstName || cvData.firstName);
  const lastName = asString(contacts.lastName || cvData.lastName);
  const name = asString(contacts.name)
    || [firstName, lastName].filter(Boolean).join(' ').trim();

  const email = asString(contacts.email || cvData.email);
  const phone = asString(contacts.phone || cvData.phone);
  const phoneCountryCode = asString(contacts.phoneCountryCode || cvData.phoneCountryCode);
  const phoneNumber = asString(contacts.phoneNumber || cvData.phoneNumber);
  const whatsapp = asString(contacts.whatsapp || contacts.wa || cvData.whatsapp);
  const telegram = asString(contacts.telegram || contacts.tg || cvData.telegram);
  const viber = asString(contacts.viber || cvData.viber);
  const messenger = asString(
    contacts.messenger || contacts.facebookMessenger || cvData.messenger,
  );

  return {
    candidateId,
    cvId: candidateId,
    ownerId,
    name,
    firstName,
    lastName,
    email,
    phone,
    phoneCountryCode,
    phoneNumber,
    whatsapp,
    telegram,
    viber,
    messenger,
  };
}

function buildPublicCvSanitizePatch(cvData) {
  const patch = {};
  let changed = false;

  const contacts = cvData && typeof cvData.contacts === 'object'
    ? { ...cvData.contacts }
    : null;
  if (contacts) {
    for (const key of SENSITIVE_CV_CONTACT_KEYS) {
      if (Object.prototype.hasOwnProperty.call(contacts, key)) {
        delete contacts[key];
        changed = true;
      }
    }
    if (changed) {
      patch.contacts = contacts;
    }
  }

  for (const key of SENSITIVE_CV_CONTACT_KEYS) {
    if (Object.prototype.hasOwnProperty.call(cvData || {}, key)) {
      patch[key] = admin.firestore.FieldValue.delete();
      changed = true;
    }
  }

  return changed ? patch : null;
}

async function resolveCandidateContact(candidateId) {
  const privateSnap = await candidateContactsPrivateRef(candidateId).get();
  if (privateSnap.exists) {
    const privateData = privateSnap.data() || {};
    return {
      candidateId,
      name: asString(privateData.name),
      email: asString(privateData.email),
      phone: asString(privateData.phone),
      whatsapp: asString(privateData.whatsapp),
      telegram: asString(privateData.telegram),
      viber: asString(privateData.viber),
      messenger: asString(privateData.messenger),
      cvId: asString(privateData.cvId || candidateId),
      ownerId: asString(privateData.ownerId),
    };
  }

  const candidateCv = await db.collection('cvs').doc(candidateId).get();
  if (!candidateCv.exists) {
    return {
      candidateId,
      name: '',
      email: '',
      phone: '',
      whatsapp: '',
      telegram: '',
      viber: '',
      messenger: '',
      cvId: candidateId,
      ownerId: '',
    };
  }

  const legacy = extractCandidateContactPayload(candidateId, candidateCv.data() || {});
  return {
    candidateId,
    name: asString(legacy.name),
    email: asString(legacy.email),
    phone: asString(legacy.phone),
    whatsapp: asString(legacy.whatsapp),
    telegram: asString(legacy.telegram),
    viber: asString(legacy.viber),
    messenger: asString(legacy.messenger),
    cvId: asString(legacy.cvId || candidateCv.id),
    ownerId: asString(legacy.ownerId),
  };
}

const app = express();
// Absolute preflight bypass: must run before any auth or route middleware.
app.use((req, res, next) => {
  if (req.method === 'OPTIONS') {
    res.set('Access-Control-Allow-Origin', '*');
    res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
    res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    res.status(204).send('');
    return;
  }
  next();
});

const corsMiddleware = cors({
  origin: true,
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization'],
});
app.use(corsMiddleware);
app.options('*', corsMiddleware);

const PAYMENT_CORS_PATH_PREFIXES = [
  '/payments/',
  '/createCheckoutSession',
  '/employer/credits/',
  '/employer/contacts/',
  '/employer/me',
];

function isDevWebOrigin(origin) {
  const value = asString(origin).toLowerCase();
  if (!value) return false;
  return /^https?:\/\/localhost(?::\d+)?$/.test(value)
    || /^https?:\/\/127\.0\.0\.1(?::\d+)?$/.test(value);
}

function isPaymentCorsPath(path) {
  const rawPath = asString(path);
  if (!rawPath) return false;
  const normalized = rawPath.startsWith('/api/')
    ? rawPath.slice(4)
    : (rawPath === '/api' ? '/' : rawPath);
  return PAYMENT_CORS_PATH_PREFIXES.some((prefix) => {
    if (prefix.endsWith('/')) return normalized.startsWith(prefix);
    return normalized === prefix || normalized.startsWith(`${prefix}/`);
  });
}

app.use((req, res, next) => {
  // Always allow preflight to pass without auth checks.
  if (req.method === 'OPTIONS') {
    const origin = asString(req.headers.origin);
    if (origin) {
      res.set('Access-Control-Allow-Origin', origin);
      res.set('Vary', 'Origin');
      if (isDevWebOrigin(origin)) {
        res.set('X-Worka-Cors-Origin', 'dev-local');
      }
    }
    res.set(
      'Access-Control-Allow-Headers',
      'Content-Type, Authorization, X-Requested-With',
    );
    res.set('Access-Control-Allow-Methods', 'GET, POST, PUT, PATCH, DELETE, OPTIONS');
    res.set('Access-Control-Max-Age', '86400');
    res.status(204).send('');
    return;
  }

  if (!isPaymentCorsPath(req.path)) {
    next();
    return;
  }

  const origin = asString(req.headers.origin);
  // Dev-friendly: explicitly supports localhost/127.0.0.1 and keeps
  // reflective origin for existing deployed web clients.
  if (origin) {
    res.set('Access-Control-Allow-Origin', origin);
    res.set('Vary', 'Origin');
    if (isDevWebOrigin(origin)) {
      res.set('X-Worka-Cors-Origin', 'dev-local');
    }
  }
  res.set(
    'Access-Control-Allow-Headers',
    'Content-Type, Authorization, X-Requested-With',
  );
  res.set('Access-Control-Allow-Methods', 'GET, POST, PUT, PATCH, DELETE, OPTIONS');
  res.set('Access-Control-Max-Age', '86400');

  next();
});
app.use(express.json({ limit: '1mb' }));

app.get('/health', (_req, res) => {
  res.json({ ok: true, ts: nowIso() });
});

// ---------------------------------------------------------------------------
// Recruiting endpoints (bridged to RECRUITING_API_BASE_URL)
// ---------------------------------------------------------------------------
app.post('/jobs', requireAuth, async (req, res) => {
  await forwardToRecruiting({ req, res, path: '/jobs' });
});

app.patch('/jobs/:jobCode', requireAuth, async (req, res) => {
  await forwardToRecruiting({ req, res, path: `/jobs/${req.params.jobCode}` });
});

app.post('/apply', requireAuth, async (req, res) => {
  await forwardToRecruiting({ req, res, path: '/apply' });
});

app.post('/candidates/cv', requireAuth, async (req, res) => {
  await forwardToRecruiting({ req, res, path: '/candidates/cv' });
});

app.patch('/candidates/cv/:id', requireAuth, async (req, res) => {
  await forwardToRecruiting({ req, res, path: `/candidates/cv/${req.params.id}` });
});

app.post('/candidates/cv/:cvId/entitlements', requireAuth, async (req, res) => {
  await forwardToRecruiting({
    req,
    res,
    path: `/candidates/cv/${req.params.cvId}/entitlements`,
  });
});

app.post('/worker/entitlements/apply', requireAuth, async (req, res) => {
  await forwardToRecruiting({
    req,
    res,
    path: '/worker/entitlements/apply',
  });
});

async function handleParseVacancy(req, res) {
  const text = (req.body?.text ?? '').toString().trim();
  logger.info('POST /ai/parse-vacancy received', {
    path: req.path,
    textLength: text.length,
  });
  if (!text) {
    res.status(400).json({ error: 'text is required' });
    return;
  }
  try {
    logger.info('POST /ai/parse-vacancy: starting AI parse');
    const { parseVacancyText } = require('./ai_parser'); // lazy — isolates failure
    const parsed_data = await parseVacancyText(text);
    logger.info('POST /ai/parse-vacancy: AI parse complete');
    res.json({ parsed_data });
  } catch (err) {
    logger.error('POST /ai/parse-vacancy failed', { message: err?.message || String(err) });
    res.status(500).json({ error: err?.message || 'AI parsing failed' });
  }
}

async function handleParseCv(req, res) {
  const text = (req.body?.text ?? '').toString().trim();
  logger.info('POST /ai/parse-cv received', {
    path: req.path,
    textLength: text.length,
  });
  if (!text) {
    res.status(400).json({ error: 'text is required' });
    return;
  }
  try {
    logger.info('POST /ai/parse-cv: starting AI parse');
    const { parseCVText } = require('./ai_parser'); // lazy — isolates failure
    const parsed_data = await parseCVText(text);
    logger.info('POST /ai/parse-cv: AI parse complete');
    res.json({ parsed_data });
  } catch (err) {
    logger.error('POST /ai/parse-cv failed', { message: err?.message || String(err) });
    res.status(500).json({ error: err?.message || 'AI parsing failed' });
  }
}

// ─── AI: Parse text routes (supports both /ai/* and /api/ai/*) ───────────
for (const p of ['/ai/parse-vacancy', '/api/ai/parse-vacancy']) {
  app.post(p, requireAuth, handleParseVacancy);
}
for (const p of ['/ai/parse-cv', '/api/ai/parse-cv']) {
  app.post(p, requireAuth, handleParseCv);
}

// ─── AI: Parse vacancy from URL ───────────────────────────────────────────────
// Fetches the page server-side, strips HTML, then runs the same vacancy parser.
// SSRF protection: only allows http(s), blocks private/local IP ranges.
async function handleParseVacancyUrl(req, res) {
  const rawUrl = (req.body?.url ?? '').toString().trim();
  logger.info('POST /ai/parse-vacancy-url received', { url: rawUrl });

  if (!rawUrl) {
    res.status(400).json({ error: 'url is required' });
    return;
  }

  // Validate URL scheme — only http/https allowed
  let parsedUrl;
  try {
    parsedUrl = new URL(rawUrl);
  } catch {
    res.status(400).json({ error: 'Invalid URL' });
    return;
  }
  if (parsedUrl.protocol !== 'http:' && parsedUrl.protocol !== 'https:') {
    res.status(400).json({ error: 'Only http and https URLs are allowed' });
    return;
  }

  // SSRF protection: block private/loopback hostnames
  const hostname = parsedUrl.hostname.toLowerCase();
  const BLOCKED = [
    'localhost', '127.0.0.1', '0.0.0.0', '::1',
    'metadata.google.internal', '169.254.169.254',
  ];
  if (BLOCKED.includes(hostname) || hostname.endsWith('.internal')) {
    res.status(400).json({ error: 'URL not allowed' });
    return;
  }

  try {
    // Fetch the page with a strict timeout
    const https = require('https');
    const http  = require('http');
    const client = parsedUrl.protocol === 'https:' ? https : http;

    const pageText = await new Promise((resolve, reject) => {
      const request = client.get(
        rawUrl,
        { timeout: 10000, headers: { 'User-Agent': 'Mozilla/5.0 (compatible; WorkaBot/1.0)' } },
        (response) => {
          if (response.statusCode >= 400) {
            reject(new Error(`Remote server returned ${response.statusCode}`));
            return;
          }
          let body = '';
          response.setEncoding('utf8');
          response.on('data', (chunk) => {
            body += chunk;
            if (body.length > 300_000) { response.destroy(); reject(new Error('Page too large')); }
          });
          response.on('end', () => resolve(body));
          response.on('error', reject);
        },
      );
      request.on('timeout', () => { request.destroy(); reject(new Error('Request timed out')); });
      request.on('error', reject);
    });

    // Strip HTML tags and collapse whitespace to get readable text
    const text = pageText
      .replace(/<script[\s\S]*?<\/script>/gi, ' ')
      .replace(/<style[\s\S]*?<\/style>/gi, ' ')
      .replace(/<[^>]+>/g, ' ')
      .replace(/&nbsp;/g, ' ')
      .replace(/&amp;/g, '&')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&quot;/g, '"')
      .replace(/\s{2,}/g, ' ')
      .trim()
      .slice(0, 15000); // limit to 15k chars for token budget

    if (text.length < 50) {
      res.status(422).json({ error: 'Could not extract readable text from the URL' });
      return;
    }

    logger.info('POST /ai/parse-vacancy-url: text extracted, starting AI parse', { charCount: text.length });
    const { parseVacancyText } = require('./ai_parser');
    const parsed_data = await parseVacancyText(text);
    logger.info('POST /ai/parse-vacancy-url: AI parse complete');
    res.json({ parsed_data, source_text: text.slice(0, 2000) }); // return snippet for debugging
  } catch (err) {
    logger.error('POST /ai/parse-vacancy-url failed', { message: err?.message || String(err) });
    res.status(500).json({ error: err?.message || 'Failed to fetch or parse URL' });
  }
}
for (const p of ['/ai/parse-vacancy-url', '/api/ai/parse-vacancy-url']) {
  app.post(p, requireAuth, handleParseVacancyUrl);
}

// ─── AI: Parse vacancy from PDF ───────────────────────────────────────────────
async function handleParseVacancyPdf(req, res) {
  logger.info('POST /ai/parse-vacancy-pdf received');
  const contentType = (req.headers['content-type'] || '').toLowerCase();
  if (!contentType.includes('multipart/form-data')) {
    res.status(400).json({ error: 'multipart/form-data required' });
    return;
  }

  try {
    const pdfBuffer = await new Promise((resolve, reject) => {
      const bb = Busboy({ headers: req.headers, limits: { fileSize: 10 * 1024 * 1024 } });
      let fileBuffer = null;
      bb.on('file', (_name, stream) => {
        const chunks = [];
        stream.on('data', (d) => chunks.push(d));
        stream.on('end', () => { fileBuffer = Buffer.concat(chunks); });
        stream.on('error', reject);
      });
      bb.on('finish', () => fileBuffer ? resolve(fileBuffer) : reject(new Error('No file uploaded')));
      bb.on('error', reject);
      req.pipe(bb);
    });

    const pdfParse = require('pdf-parse');
    const pdfData  = await pdfParse(pdfBuffer);
    const text = (pdfData.text || '').trim().slice(0, 15000);

    if (text.length < 50) {
      res.status(422).json({ error: 'Could not extract text from PDF' });
      return;
    }

    logger.info('POST /ai/parse-vacancy-pdf: text extracted', { charCount: text.length });
    const { parseVacancyText } = require('./ai_parser');
    const parsed_data = await parseVacancyText(text);
    logger.info('POST /ai/parse-vacancy-pdf: AI parse complete');
    res.json({ parsed_data });
  } catch (err) {
    logger.error('POST /ai/parse-vacancy-pdf failed', { message: err?.message || String(err) });
    res.status(500).json({ error: err?.message || 'PDF parsing failed' });
  }
}
for (const p of ['/ai/parse-vacancy-pdf', '/api/ai/parse-vacancy-pdf']) {
  app.post(p, requireAuth, handleParseVacancyPdf);
}

// ─── AI: Parse CV from PDF ────────────────────────────────────────────────────
async function handleParseCvPdf(req, res) {
  logger.info('POST /ai/parse-cv-pdf received');
  const contentType = (req.headers['content-type'] || '').toLowerCase();
  if (!contentType.includes('multipart/form-data')) {
    res.status(400).json({ error: 'multipart/form-data required' });
    return;
  }

  try {
    const pdfBuffer = await new Promise((resolve, reject) => {
      const bb = Busboy({ headers: req.headers, limits: { fileSize: 10 * 1024 * 1024 } });
      let fileBuffer = null;
      bb.on('file', (_name, stream) => {
        const chunks = [];
        stream.on('data', (d) => chunks.push(d));
        stream.on('end', () => { fileBuffer = Buffer.concat(chunks); });
        stream.on('error', reject);
      });
      bb.on('finish', () => fileBuffer ? resolve(fileBuffer) : reject(new Error('No file uploaded')));
      bb.on('error', reject);
      req.pipe(bb);
    });

    const pdfParse = require('pdf-parse');
    const pdfData  = await pdfParse(pdfBuffer);
    const text = (pdfData.text || '').trim().slice(0, 15000);

    if (text.length < 50) {
      res.status(422).json({ error: 'Could not extract text from PDF' });
      return;
    }

    logger.info('POST /ai/parse-cv-pdf: text extracted', { charCount: text.length });
    const { parseCVText } = require('./ai_parser');
    const parsed_data = await parseCVText(text);
    logger.info('POST /ai/parse-cv-pdf: AI parse complete');
    res.json({ parsed_data });
  } catch (err) {
    logger.error('POST /ai/parse-cv-pdf failed', { message: err?.message || String(err) });
    res.status(500).json({ error: err?.message || 'PDF parsing failed' });
  }
}
for (const p of ['/ai/parse-cv-pdf', '/api/ai/parse-cv-pdf']) {
  app.post(p, requireAuth, handleParseCvPdf);
}

app.post('/payments/payment-intent', requireAuth, async (req, res) => {
  try {
    if (!requireStripe(res)) return;

    const employerId = asString(req.auth.uid);
    const employerEmail = asString(req.auth.email);
    const productId = asString(req.body?.productId);
    const product = PRODUCT_CATALOG[productId];

    if (!employerId) {
      res.status(401).json({ error: 'Unauthorized' });
      return;
    }

    if (!product) {
      res.status(400).json({ error: 'Unknown productId' });
      return;
    }

    const quantity = asPositiveInt(req.body?.quantity, 1);
    const vatId = asString(req.body?.vatId);
    const context = req.body?.context && typeof req.body.context === 'object'
      ? req.body.context
      : {};

    let normalizedJobId = '';
    if (isVacancyMonetizationProduct(product)) {
      normalizedJobId = asString(req.body?.context?.jobId || req.body?.jobId);
      try {
        await loadOwnedJobOrThrow(normalizedJobId, employerId);
      } catch (error) {
        const code = String(error?.message || '');
        const statusCode = Number(error?.statusCode || 400);

        if (code === 'JOB_NOT_FOUND') {
          res.status(404).json({ error: 'Job not found' });
          return;
        }
        if (code === 'JOB_OWNER_MISMATCH') {
          res.status(403).json({ error: 'You do not own this job' });
          return;
        }
        if (code === 'JOB_ID_REQUIRED') {
          res.status(400).json({ error: 'jobId is required for vacancy payment' });
          return;
        }

        res.status(statusCode).json({ error: code || 'Failed to validate job ownership' });
        return;
      }
    }

    await upsertEmployerBilling({ uid: employerId, email: employerEmail, vatId });

    const customerId = await resolveStripeCustomer({ uid: employerId, email: employerEmail, vatId });

    const amount = product.amountCents * quantity;

    const metadata = {
      userId: employerId,
      employer_id: employerId,
      productId: product.id,
      product_id: product.id,
      product_type: product.type,
      quantity: String(quantity),
      vat_id: vatId,
      ...(normalizedJobId ? { context_job_id: normalizedJobId } : {}),
      ...(asString(context.candidateId) ? { context_candidate_id: asString(context.candidateId) } : {}),
    };

    const paymentIntent = await stripe.paymentIntents.create({
      amount,
      currency: product.currency,
      customer: customerId,
      automatic_payment_methods: { enabled: true },
      receipt_email: employerEmail || undefined,
      metadata,
    });

    const normalizedContext = {
      ...context,
      ...(normalizedJobId ? { jobId: normalizedJobId } : {}),
    };

    const purchaseRef = pendingPurchasesCol().doc(paymentIntent.id);
    await purchaseRef.set(
      pendingPurchasePayload({
        uid: employerId,
        email: employerEmail,
        product,
        quantity,
        context: normalizedContext,
        vatId,
        paymentIntent,
      }),
      { merge: true },
    );

    res.json({
      clientSecret: paymentIntent.client_secret,
      paymentIntentId: paymentIntent.id,
    });
  } catch (error) {
    logger.error('POST /payments/payment-intent failed', {
      message: error?.message || String(error),
    });
    res.status(500).json({ error: 'Failed to create payment intent' });
  }
});

app.post('/payments/create-payment-intent', requireAuth, async (req, res) => {
  try {
    if (!requireStripe(res)) return;

    const uid = req.auth.uid;
    const email = req.auth.email || '';
    const productId = asString(req.body?.productId);
    const product = PRODUCT_CATALOG[productId];
    if (!product || product.type !== 'credits') {
      logger.warn('POST /payments/create-payment-intent invalid product', {
        uid,
        productId,
      });
      res.status(400).json({ error: 'Unknown or unsupported productId' });
      return;
    }

    // Credits checkout endpoint: quantity and pricing are fully server-defined.
    const quantity = 1;
    const vatId = asString(req.body?.vatId);
    const context = req.body?.context && typeof req.body.context === 'object'
      ? req.body.context
      : {};

    logger.info('POST /payments/create-payment-intent debug', {
      uid,
      productId,
      stripeClientReady: !!stripe,
      stripeSecretConfigured: Boolean(process.env.STRIPE_SECRET_KEY && process.env.STRIPE_SECRET_KEY.trim()),
      stripeSecretPrefix: asString(process.env.STRIPE_SECRET_KEY).slice(0, 7),
    });

    await upsertEmployerBilling({ uid, email, vatId });

    const customerId = await resolveStripeCustomer({ uid, email, vatId });

    const amount = product.amountCents * quantity;

    const paymentIntent = await stripe.paymentIntents.create({
      amount,
      currency: product.currency,
      customer: customerId,
      automatic_payment_methods: { enabled: true },
      receipt_email: email || undefined,
      metadata: {
        userId: uid,
        productId: product.id,
        app: 'worka',
        employer_id: uid,
        product_id: product.id,
        product_type: product.type,
        quantity: String(quantity),
        vat_id: vatId,
        context_job_id: asString(context.jobId),
        context_candidate_id: asString(context.candidateId),
      },
    });

    const purchaseRef = pendingPurchasesCol().doc(paymentIntent.id);
    await purchaseRef.set(
      pendingPurchasePayload({
        uid,
        email,
        product,
        quantity,
        context,
        vatId,
        paymentIntent,
      }),
      { merge: true },
    );

    logger.info('POST /payments/create-payment-intent created', {
      uid,
      productId: product.id,
      amount,
      currency: product.currency,
      paymentIntentId: paymentIntent.id,
      hasClientSecret: Boolean(paymentIntent.client_secret),
    });

    res.json({
      clientSecret: paymentIntent.client_secret,
      paymentIntentId: paymentIntent.id,
      amount,
      currency: product.currency,
      productId: product.id,
    });
  } catch (error) {
    logger.error('POST /payments/create-payment-intent failed', {
      uid: req.auth?.uid || '',
      productId: asString(req.body?.productId),
      message: error?.message || String(error),
    });
    res.status(500).json({ error: 'Failed to create payment intent' });
  }
});

// ---------------------------------------------------------------------------
// Stripe Checkout (one-time payments)
// ---------------------------------------------------------------------------
app.post('/createCheckoutSession', requireAuth, async (req, res) => {
  try {
    if (!requireStripe(res)) return;
    const stripe = getStripeClient();

    logger.info('POST /createCheckoutSession headers', {
      origin: req.headers.origin || '',
      referer: req.headers.referer || '',
      host: req.headers.host || '',
    });

    const requestedProductId = asString(
      req.body?.canonicalProductId || req.body?.productId || req.body?.featureKey,
    );
    const vacancyProduct = resolveVacancyProduct(requestedProductId);
    const catalogProduct = vacancyProduct.product || PRODUCT_CATALOG[requestedProductId];
    const context = req.body?.context && typeof req.body.context === 'object'
      ? req.body.context
      : {};
    const returnContext = req.body?.returnContext && typeof req.body.returnContext === 'object'
      ? req.body.returnContext
      : {};
    const requestedJobId = asString(req.body?.jobId || context.jobId);
    const returnOrigin = asString(returnContext.origin);
    const returnJobId = asString(returnContext.jobId || requestedJobId);
    const returnProduct = asString(
      returnContext.product || vacancyProduct.canonicalProductId,
    );
    const returnSourceScreen = asString(returnContext.sourceScreen);

    const userId = asString(req.auth?.uid);
    const featureKey = vacancyProduct.backendProductId || requestedProductId;
    const customerEmail = asString(req.auth?.email);
    let amountCents = 0;

    if (isVacancyMonetizationProduct(catalogProduct)) {
      amountCents = catalogProduct.amountCents;

      if (!userId || !featureKey || !customerEmail || !requestedJobId) {
        res.status(400).json({
          error: 'userId, productId, customerEmail and jobId are required for vacancy checkout',
        });
        return;
      }

      // Ownership check: job must exist and belong to auth user.
      const jobSnap = await db.collection('jobs').doc(requestedJobId).get();
      if (!jobSnap.exists) {
        res.status(404).json({ error: 'job_not_found' });
        return;
      }
      const job = jobSnap.data() || {};
      const owner = asString(job.ownerId || job.ownerUid || job.owner_id);
      if (!owner || owner !== userId) {
        res.status(403).json({ error: 'forbidden_job_owner_mismatch' });
        return;
      }
    } else if (!userId || !featureKey || !customerEmail || amountCents <= 0) {
      res.status(400).json({
        error: 'userId, featureKey, amount, customerEmail are required',
      });
      return;
    }

    // Server-authoritative amount only.
    const resolvedProduct = PRODUCT_CATALOG[featureKey];
    if (!resolvedProduct) {
      res.status(400).json({ error: 'Unknown productId' });
      return;
    }
    amountCents = resolvedProduct.amountCents;

    const rawSuccessUrl = asString(process.env.STRIPE_CHECKOUT_SUCCESS_URL);
    const rawCancelUrl = asString(process.env.STRIPE_CHECKOUT_CANCEL_URL);
    const successBase = returnOrigin || rawSuccessUrl;
    const cancelBase = returnOrigin || rawCancelUrl;
    const successUrl = buildCheckoutReturnUrl(
      successBase,
      '/payments/success',
      { session_id: '{CHECKOUT_SESSION_ID}' },
    );
    const cancelUrl = buildCheckoutReturnUrl(
      cancelBase,
      '/payments/cancel',
    );
    const safeSuccessUrl = isVacancyMonetizationProduct(catalogProduct)
      ? appendQueryParams(successUrl, {
          origin: returnOrigin,
          job_id: returnJobId,
          product: returnProduct,
          source_screen: returnSourceScreen,
        })
      : successUrl;
    const safeCancelUrl = isVacancyMonetizationProduct(catalogProduct)
      ? appendQueryParams(cancelUrl, {
          origin: returnOrigin,
          job_id: returnJobId,
          product: returnProduct,
          source_screen: returnSourceScreen,
        })
      : cancelUrl;

    const finalSuccessUrl =
      FRONTEND_WEB_ROUTING === 'hash' ? toHashRoute(safeSuccessUrl) : safeSuccessUrl;
    const finalCancelUrl =
      FRONTEND_WEB_ROUTING === 'hash' ? toHashRoute(safeCancelUrl) : safeCancelUrl;

    logger.info('POST /createCheckoutSession input', {
      userId,
      featureKey,
      canonicalProductId: vacancyProduct.canonicalProductId,
      returnOrigin,
      returnJobId,
      customerEmail,
      amountCents,
      requestedJobId,
      successUrl: finalSuccessUrl,
      cancelUrl: finalCancelUrl,
      successBase,
      cancelBase,
      rawSuccessUrl,
      rawCancelUrl,
      routingMode: FRONTEND_WEB_ROUTING,
      finalSuccessUrl,
      finalCancelUrl,
    });

    const session = await stripe.checkout.sessions.create({
      mode: 'payment',
      customer_email: customerEmail,
      success_url: finalSuccessUrl,
      cancel_url: finalCancelUrl,
      line_items: [
        {
          quantity: 1,
          price_data: {
            currency: 'eur',
            unit_amount: amountCents,
            product_data: {
              name: asString(catalogProduct?.title || featureKey),
            },
          },
        },
      ],
      metadata: {
        userId,
        featureKey,
        employer_id: userId,
        productId: featureKey,
        product_id: featureKey,
        canonicalProductId: vacancyProduct.canonicalProductId,
        canonical_product_id: vacancyProduct.canonicalProductId,
        backendProductId: featureKey,
        backend_product_id: featureKey,
        returnOrigin,
        return_origin: returnOrigin,
        returnJobId,
        return_job_id: returnJobId,
        returnProduct,
        return_product: returnProduct,
        sourceScreen: returnSourceScreen,
        source_screen: returnSourceScreen,
        quantity: '1',
        context_job_id: requestedJobId,
      },
      payment_intent_data: {
        metadata: {
          userId,
          featureKey,
          employer_id: userId,
          productId: featureKey,
          product_id: featureKey,
          canonicalProductId: vacancyProduct.canonicalProductId,
          canonical_product_id: vacancyProduct.canonicalProductId,
          backendProductId: featureKey,
          backend_product_id: featureKey,
          returnOrigin,
          return_origin: returnOrigin,
          returnJobId,
          return_job_id: returnJobId,
          returnProduct,
          return_product: returnProduct,
          sourceScreen: returnSourceScreen,
          source_screen: returnSourceScreen,
          quantity: '1',
          context_job_id: requestedJobId,
        },
      },
    });

    if (!session.url) {
      res.status(500).json({ error: 'Failed to create checkout session url' });
      return;
    }

    logger.info('POST /createCheckoutSession created', {
      userId,
      featureKey,
      canonicalProductId: vacancyProduct.canonicalProductId,
      amountCents,
      sessionId: session.id,
    });

    res.json({ url: session.url });
  } catch (error) {
    logger.error('POST /createCheckoutSession failed', {
      message: error?.message || String(error),
      type: error?.type || '',
      code: error?.code || '',
      param: error?.param || '',
      decline_code: error?.decline_code || '',
      stack: error?.stack || '',
      raw: error?.raw || null,
      userId: asString(req.body?.userId),
      featureKey: asString(req.body?.featureKey),
      customerEmail: asString(req.body?.customerEmail),
      amount: req.body?.amount,
    });
    return res.status(500).json({
      error: 'createCheckoutSession_failed',
      message: error?.message,
      type: error?.type,
      code: error?.code,
      param: error?.param,
      decline_code: error?.decline_code,
    });
  }
});

app.post('/payments/checkout-session-status', requireAuth, async (req, res) => {
  try {
    if (!requireStripe(res)) return;
    const stripeClient = getStripeClient();
    const sessionId = asString(req.body?.sessionId);
    if (!sessionId) {
      res.status(400).json({ error: 'sessionId is required' });
      return;
    }

    const session = await stripeClient.checkout.sessions.retrieve(sessionId, {
      expand: ['payment_intent'],
    });
    const metadata = session?.metadata && typeof session.metadata === 'object'
      ? session.metadata
      : {};
    const ownerId = asString(metadata.userId || metadata.employer_id);
    if (!ownerId || ownerId !== req.auth.uid) {
      res.status(403).json({ error: 'checkout session does not belong to auth user' });
      return;
    }

    const resolvedVacancyProduct = resolveVacancyProduct(
      metadata.canonicalProductId || metadata.canonical_product_id
        || metadata.productId || metadata.product_id || metadata.featureKey,
    );
    const productId = asString(
      resolvedVacancyProduct.backendProductId
        || metadata.productId || metadata.product_id || metadata.featureKey,
    );
    const isVacancyCheckout = isVacancyMonetizationProduct(
      PRODUCT_CATALOG[productId],
    );
    const result = isVacancyCheckout
      ? await ensureCheckoutSessionProcessed(session)
      : {
          applied: false,
          status: asString(session?.payment_status || session?.status || 'unknown'),
          userId: ownerId,
          productId,
          canonicalProductId: asString(resolvedVacancyProduct.canonicalProductId),
          jobId: asString(metadata.context_job_id),
          sessionId,
          paymentIntentId: asString(session?.payment_intent?.id || session?.payment_intent),
          paymentIntentStatus: asString(session?.payment_intent?.status),
        };

    res.json({
      sessionId,
      checkoutStatus: asString(session?.status),
      paymentStatus: asString(session?.payment_status),
      isVacancyCheckout,
      ...result,
    });
  } catch (error) {
    logger.error('POST /payments/checkout-session-status failed', {
      message: error?.message || String(error),
      sessionId: asString(req.body?.sessionId),
      uid: req.auth?.uid || '',
    });
    res.status(500).json({ error: 'Failed to resolve checkout session status' });
  }
});

async function handleStripeWebhookRequest(req, res) {
  try {
    if (!requireStripe(res)) return;
    if (!STRIPE_WEBHOOK_SECRET) {
      res.status(500).json({ error: 'Missing STRIPE_WEBHOOK_SECRET' });
      return;
    }

    if (req.method !== 'POST') {
      res.status(405).send('Method Not Allowed');
      return;
    }

    const signature = req.headers['stripe-signature'];
    if (!signature) {
      res.status(400).send('Missing stripe-signature header');
      return;
    }

    const event = stripe.webhooks.constructEvent(
      req.rawBody,
      signature,
      STRIPE_WEBHOOK_SECRET,
    );

    const eventId = asString(event.id);
    const eventRef = eventId
      ? stripeWebhookEventsCol().doc(eventId)
      : null;

    if (eventRef) {
      const eventSnap = await eventRef.get();
      const existingStatus = asString(eventSnap.data()?.status);
      const paymentIntentId = asString(
        event?.data?.object?.payment_intent
          || event?.data?.object?.id,
      );

      if (eventSnap.exists && existingStatus.startsWith('processed')) {
        const entitlementApplied = paymentIntentId
          ? await hasEntitlementBeenApplied(paymentIntentId)
          : false;

        if (entitlementApplied) {
          logger.info('stripeWebhook duplicate event ignored', {
            eventId,
            type: event.type,
            status: existingStatus,
          });
          res.json({ received: true, duplicate: true });
          return;
        }

        logger.warn('stripeWebhook duplicate event will retry fulfillment', {
          eventId,
          type: event.type,
          status: existingStatus,
          paymentIntentId,
        });
      }
      await markWebhookEvent({
        eventId,
        paymentIntentId,
        status: 'processing',
        details: { type: event.type },
      });
    }

    if (event.type === 'payment_intent.succeeded') {
      const paymentIntent = event.data.object;
      const state = await loadPendingOrPurchaseByPaymentIntentId(paymentIntent.id);

      if (!state) {
        const orphanRef = purchasesCol().doc(paymentIntent.id);
        await orphanRef.set(
          {
            stripe_payment_intent_id: paymentIntent.id,
            status: 'succeeded_unmatched',
            amount: paymentIntent.amount || 0,
            currency: paymentIntent.currency || CURRENCY,
            updated_at: admin.firestore.FieldValue.serverTimestamp(),
            created_at: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
        await markWebhookEvent({
          eventId,
          paymentIntentId: paymentIntent.id,
          status: 'processed_unmatched',
          details: { type: event.type },
        });
        res.json({ received: true, applied: false, reason: 'purchase_not_found' });
        return;
      }

      const purchaseRef = state.purchaseRef;
      const purchaseData = state.data || {};

      await purchaseRef.set(
        {
          ...purchaseData,
          stripe_payment_intent_id: paymentIntent.id,
          stripe_payment_intent_status: paymentIntent.status,
          paid_at: admin.firestore.FieldValue.serverTimestamp(),
          updated_at: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );

      const validation = validateSucceededPaymentIntent({
        paymentIntent,
        purchaseData,
      });
      if (!validation.ok) {
        logger.error('stripeWebhook validation failed for payment_intent.succeeded', {
          eventId,
          paymentIntentId: paymentIntent.id,
          code: validation.code,
          message: validation.message,
        });
        await purchaseRef.set(
          {
            status: 'validation_failed',
            validation_error_code: validation.code,
            validation_error_message: validation.message,
            updated_at: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
        if (state.pendingRef) {
          await state.pendingRef.set(
            {
              status: 'validation_failed',
              validation_error_code: validation.code,
              validation_error_message: validation.message,
              updated_at: admin.firestore.FieldValue.serverTimestamp(),
            },
            { merge: true },
          );
        }
        await markWebhookEvent({
          eventId,
          paymentIntentId: paymentIntent.id,
          status: 'processed_validation_failed',
          details: {
            type: event.type,
            code: validation.code,
            message: validation.message,
          },
        });
        res.json({ received: true, applied: false, reason: 'validation_failed' });
        return;
      }

      const entitlementResult = await applyPaymentEntitlement({
        purchaseRef,
        purchaseData,
        paymentIntent,
      });
      if (state.pendingRef) {
        await state.pendingRef.delete();
      }
      await markWebhookEvent({
        eventId,
        paymentIntentId: paymentIntent.id,
        status: entitlementResult.applied
          ? 'processed'
          : 'processed_entitlement_failed',
        details: {
          type: event.type,
          code: asString(entitlementResult.code),
          message: asString(entitlementResult.message),
        },
      });

      res.json({
        received: true,
        applied: entitlementResult.applied === true,
        status: entitlementResult.applied ? 'applied' : 'failed_entitlement',
        errorCode: asString(entitlementResult.code),
        errorMessage: asString(entitlementResult.message),
      });
      return;
    }

    if (event.type === 'payment_intent.payment_failed') {
      const paymentIntent = event.data.object;
      const reason = asString(paymentIntent.last_payment_error?.message);
      await markPaymentFailed({ paymentIntent, reason });
      await markWebhookEvent({
        eventId,
        paymentIntentId: paymentIntent.id,
        status: 'processed_failed',
        details: { type: event.type, reason },
      });
      logger.warn('stripeWebhook payment failed', {
        eventId,
        paymentIntentId: paymentIntent.id,
        reason,
      });
      res.json({ received: true, failed: true });
      return;
    }

    if (event.type === 'checkout.session.completed') {
      const session = event.data.object;
      const metadata = session?.metadata || {};
      const result = await ensureCheckoutSessionProcessed(session);
      logger.info('stripeWebhook checkout.session.completed', {
        eventId,
        sessionId: asString(session?.id),
        userId: asString(metadata.userId),
        featureKey: asString(metadata.featureKey),
        applied: result.applied === true,
        status: asString(result.status),
      });
      await markWebhookEvent({
        eventId,
        paymentIntentId: asString(session?.payment_intent?.id || session?.payment_intent),
        status: result.applied === true ? 'processed_checkout_applied' : 'processed_checkout_seen',
        details: {
          type: event.type,
          sessionId: asString(session?.id),
          productId: asString(result.productId),
          status: asString(result.status),
        },
      });
      res.json({ received: true, applied: result.applied === true, via: 'checkout.session.completed' });
      return;
    }

    await markWebhookEvent({
      eventId,
      paymentIntentId: asString(event?.data?.object?.id),
      status: 'processed_ignored',
      details: { type: event.type },
    });
    res.json({ received: true, ignored: true, event: event.type });
  } catch (error) {
    const message = error?.message || String(error);
    const eventId = asString(error?.raw?.id || error?.id);
    if (eventId) {
      await markWebhookEvent({
        eventId,
        paymentIntentId: '',
        status: 'failed',
        details: { message },
      });
    }
    logger.error('stripeWebhook failed', {
      message,
    });
    res.status(400).send(`Webhook Error: ${message}`);
  }
}

app.post('/stripeWebhook', async (req, res) => {
  await handleStripeWebhookRequest(req, res);
});

app.post('/employer/credits/consume', requireAuth, async (req, res) => {
  try {
    const employerId = req.auth.uid;
    const candidateId = asString(req.body?.candidateId);
    if (!candidateId) {
      res.status(400).json({ error: 'candidateId is required' });
      return;
    }

    const employerDocRef = employersRef(employerId);
    const unlockRef = contactUnlockRef(employerId, candidateId);

    let creditsLeft = 0;

    await db.runTransaction(async (tx) => {
      const unlockSnap = await tx.get(unlockRef);
      const employerSnap = await tx.get(employerDocRef);
      const employerData = employerSnap.exists ? employerSnap.data() || {} : {};
      const currentBalance = computeCreditsBalance(employerData);

      if (unlockSnap.exists) {
        creditsLeft = currentBalance;
        return;
      }

      if (currentBalance <= 0) {
        throw new Error('INSUFFICIENT_CREDITS');
      }

      creditsLeft = currentBalance - 1;

      tx.set(
        employerDocRef,
        {
          credits_balance: creditsLeft,
          updated_at: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );

      tx.set(
        usersRef(employerId),
        {
          billing: {
            creditsBalance: creditsLeft,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );

      tx.set(unlockRef, {
        employer_id: employerId,
        candidate_id: candidateId,
        unlocked_at: admin.firestore.FieldValue.serverTimestamp(),
      });

      const ledgerRef = creditLedgerCol().doc();
      tx.set(ledgerRef, {
        employer_id: employerId,
        delta: -1,
        reason: 'contact_unlock',
        ref_id: candidateId,
        meta: {
          candidate_id: candidateId,
        },
        created_at: admin.firestore.FieldValue.serverTimestamp(),
      });
    });

    const contact = await resolveCandidateContact(candidateId);

    res.json({
      creditsLeft,
      contact,
    });
  } catch (error) {
    if (String(error?.message || '') === 'INSUFFICIENT_CREDITS') {
      res.status(402).json({ error: 'Not enough credits' });
      return;
    }

    logger.error('POST /employer/credits/consume failed', {
      message: error?.message || String(error),
    });
    res.status(500).json({ error: 'Failed to consume credit' });
  }
});

app.get('/employer/contacts/:candidateId', requireAuth, async (req, res) => {
  try {
    const employerId = req.auth.uid;
    const candidateId = asString(req.params?.candidateId);
    if (!candidateId) {
      res.status(400).json({ error: 'candidateId is required' });
      return;
    }

    const unlockSnap = await contactUnlockRef(employerId, candidateId).get();
    if (!unlockSnap.exists) {
      res.status(403).json({ error: 'CONTACT_LOCKED' });
      return;
    }

    const contact = await resolveCandidateContact(candidateId);
    res.json(contact);
  } catch (error) {
    logger.error('GET /employer/contacts/:candidateId failed', {
      message: error?.message || String(error),
    });
    res.status(500).json({ error: 'Failed to load candidate contact' });
  }
});

app.get('/employer/contacts/unlocked', requireAuth, async (req, res) => {
  try {
    const employerId = req.auth.uid;
    const snap = await employersRef(employerId)
      .collection('contact_unlocks')
      .limit(2000)
      .get();

    const candidateIds = snap.docs
      .map((d) => asString(d.id || (d.data() || {}).candidate_id))
      .filter(Boolean);

    res.json({ candidateIds });
  } catch (error) {
    logger.error('GET /employer/contacts/unlocked failed', {
      message: error?.message || String(error),
    });
    res.status(500).json({ error: 'Failed to load unlocked contacts' });
  }
});

app.get('/employer/credits/state', requireAuth, async (req, res) => {
  try {
    const employerId = req.auth.uid;
    const [employerSnap, unlockSnap] = await Promise.all([
      employersRef(employerId).get(),
      employersRef(employerId)
        .collection('contact_unlocks')
        .limit(2000)
        .get(),
    ]);

    const employer = employerSnap.exists ? employerSnap.data() || {} : {};
    const candidateIds = unlockSnap.docs
      .map((d) => asString(d.id || (d.data() || {}).candidate_id))
      .filter(Boolean);

    res.json({
      uid: employerId,
      credits: computeCreditsBalance(employer),
      candidateIds,
      updatedAt: nowIso(),
    });
  } catch (error) {
    logger.error('GET /employer/credits/state failed', {
      message: error?.message || String(error),
    });
    res.status(500).json({ error: 'Failed to load credits state' });
  }
});

app.get('/employer/me', requireAuth, async (req, res) => {
  try {
    const uid = req.auth.uid;

    const [employerSnap, userSnap] = await Promise.all([
      employersRef(uid).get(),
      usersRef(uid).get(),
    ]);

    const employer = employerSnap.exists ? employerSnap.data() || {} : {};
    const user = userSnap.exists ? userSnap.data() || {} : {};
    const billing = user.billing && typeof user.billing === 'object' ? user.billing : {};

    res.json({
      uid,
      email: req.auth.email || asString(user.email) || asString(employer.email),
      vatId: asString(employer.vat_id) || asString(billing.vatId),
      credits: computeCreditsBalance(employer),
      plan: asString(employer.plan) || asString(billing.plan),
      verificationStatus:
        asString(employer.verification_status)
        || asString(billing.verificationStatus)
        || 'none',
    });
  } catch (error) {
    logger.error('GET /employer/me failed', {
      message: error?.message || String(error),
    });
    res.status(500).json({ error: 'Failed to load employer profile' });
  }
});

app.get('/employer/credits/history', requireAuth, async (req, res) => {
  try {
    const uid = req.auth.uid;
    const snap = await creditLedgerCol().where('employer_id', '==', uid).get();

    const items = snap.docs
      .map((d) => {
        const m = d.data() || {};
        const createdAt = m.created_at && typeof m.created_at.toDate === 'function'
          ? m.created_at.toDate().toISOString()
          : null;
        return {
          id: d.id,
          delta: Number(m.delta || 0),
          reason: asString(m.reason),
          refId: asString(m.ref_id),
          meta: m.meta && typeof m.meta === 'object' ? m.meta : {},
          createdAt,
        };
      })
      .sort((a, b) => String(b.createdAt || '').localeCompare(String(a.createdAt || '')));

    res.json({ items });
  } catch (error) {
    logger.error('GET /employer/credits/history failed', {
      message: error?.message || String(error),
    });
    res.status(500).json({ error: 'Failed to load credits history' });
  }
});

app.post('/employer/verification/upload', requireAuth, async (req, res) => {
  try {
    const uid = req.auth.uid;

    const contentType = String(req.headers['content-type'] || '').toLowerCase();
    if (!contentType.includes('multipart/form-data')) {
      res.status(400).json({ error: 'Expected multipart/form-data' });
      return;
    }

    const { fields, files } = await parseMultipart(req);
    if (!files.length) {
      res.status(400).json({ error: 'No file uploaded' });
      return;
    }

    const file = files[0];
    const filename = asString(file.filename) || `verification_${Date.now()}.bin`;
    const safeName = filename.replace(/[^a-zA-Z0-9._-]/g, '_');
    const objectPath = `verification_docs/${uid}/${Date.now()}_${safeName}`;

    const bucket = storage.bucket();
    const gcsFile = bucket.file(objectPath);

    await gcsFile.save(file.buffer, {
      contentType: file.mimeType || 'application/octet-stream',
      resumable: false,
      metadata: {
        metadata: {
          employer_id: uid,
          uploaded_via: 'verification_upload_api',
        },
      },
    });

    const fileUrl = `gs://${bucket.name}/${objectPath}`;
    const notes = asString(fields.notes);

    await verificationRequestsRef(uid).set(
      {
        employer_id: uid,
        status: 'pending',
        file_url: fileUrl,
        file_name: filename,
        file_content_type: file.mimeType || 'application/octet-stream',
        notes,
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
        created_at: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    await employersRef(uid).set(
      {
        verification_status: 'pending',
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    await usersRef(uid).set(
      {
        billing: {
          verificationStatus: 'pending',
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    res.json({ ok: true, fileUrl });
  } catch (error) {
    logger.error('POST /employer/verification/upload failed', {
      message: error?.message || String(error),
    });
    res.status(500).json({ error: 'Failed to upload verification document' });
  }
});

app.get('/employer/verification/status', requireAuth, async (req, res) => {
  try {
    const uid = req.auth.uid;

    const [requestSnap, employerSnap] = await Promise.all([
      verificationRequestsRef(uid).get(),
      employersRef(uid).get(),
    ]);

    const request = requestSnap.exists ? requestSnap.data() || {} : {};
    const employer = employerSnap.exists ? employerSnap.data() || {} : {};

    const status = asString(request.status)
      || asString(employer.verification_status)
      || 'none';

    res.json({
      status,
      fileUrl: asString(request.file_url),
      notes: asString(request.notes),
      updatedAt:
        request.updated_at && typeof request.updated_at.toDate === 'function'
          ? request.updated_at.toDate().toISOString()
          : null,
    });
  } catch (error) {
    logger.error('GET /employer/verification/status failed', {
      message: error?.message || String(error),
    });
    res.status(500).json({ error: 'Failed to load verification status' });
  }
});

exports.api = onRequest(
  {
    region: REGION,
    invoker: 'public',
    secrets: ['STRIPE_SECRET_KEY'],
    // Express middleware above is the single CORS handler.
    cors: false,
    memory: '512MiB',    // bumped: OpenAI client adds ~50 MiB resident
    timeoutSeconds: 120, // bumped: AI parse can take 10-30s on cold start
  },
  app,
);

exports.stripeWebhook = onRequest(
  {
    region: REGION,
    secrets: ['STRIPE_SECRET_KEY', 'STRIPE_WEBHOOK_SECRET'],
    cors: false,
    memory: '256MiB',
    timeoutSeconds: 60,
  },
  async (req, res) => {
    await handleStripeWebhookRequest(req, res);
  },
);

exports.onCvWrittenSyncPrivateContacts = onDocumentWritten(
  {
    document: 'cvs/{cvId}',
    region: REGION,
  },
  async (event) => {
    const cvId = asString(event.params.cvId);
    if (!cvId) return;
    const after = event.data?.after;
    if (!after?.exists) return;

    const cvData = after.data() || {};
    const payload = extractCandidateContactPayload(cvId, cvData);
    const hasSensitiveValue = [
      payload.email,
      payload.phone,
      payload.whatsapp,
      payload.telegram,
      payload.viber,
      payload.messenger,
    ].some((value) => asString(value).length > 0);

    if (hasSensitiveValue || payload.ownerId) {
      await candidateContactsPrivateRef(cvId).set(
        {
          ...payload,
          updated_at: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    }

    const sanitizePatch = buildPublicCvSanitizePatch(cvData);
    if (sanitizePatch) {
      await db.collection('cvs').doc(cvId).set(
        {
          ...sanitizePatch,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    }
  },
);

async function deleteResponsesByField(collectionName, field, value) {
  if (!value) return 0;
  let deleted = 0;
  while (true) {
    const snap = await db
      .collection(collectionName)
      .where(field, '==', value)
      .limit(BATCH_SIZE)
      .get();

    if (snap.empty) break;

    const batch = db.batch();
    for (const doc of snap.docs) {
      batch.delete(doc.ref);
      deleted += 1;
    }
    await batch.commit();
  }
  return deleted;
}

async function cascadeDeleteResponses(field, value) {
  let total = 0;
  for (const col of RESPONSES_COLS) {
    total += await deleteResponsesByField(col, field, value);
  }
  return total;
}

exports.onJobDeletedCascadeResponses = onDocumentDeleted(
  {
    document: 'jobs/{jobId}',
    region: REGION,
  },
  async (event) => {
    const jobId = event.params.jobId;
    if (!jobId) return;
    const deleted = await cascadeDeleteResponses('jobId', jobId);
    logger.info('Cascade delete by jobId completed', { jobId, deleted });
  },
);

exports.onJobTestDeletedCascadeResponses = onDocumentDeleted(
  {
    document: 'jobs_test/{jobId}',
    region: REGION,
  },
  async (event) => {
    const jobId = event.params.jobId;
    if (!jobId) return;
    const deleted = await cascadeDeleteResponses('jobId', jobId);
    logger.info('Cascade delete by jobId (jobs_test) completed', {
      jobId,
      deleted,
    });
  },
);

exports.onCvDeletedCascadeResponses = onDocumentDeleted(
  {
    document: 'cvs/{cvId}',
    region: REGION,
  },
  async (event) => {
    const cvId = event.params.cvId;
    if (!cvId) return;
    const deleted = await cascadeDeleteResponses('candidateCvId', cvId);
    logger.info('Cascade delete by candidateCvId completed', { cvId, deleted });
  },
);

exports.onCvTestDeletedCascadeResponses = onDocumentDeleted(
  {
    document: 'cvs_test/{cvId}',
    region: REGION,
  },
  async (event) => {
    const cvId = event.params.cvId;
    if (!cvId) return;
    const deleted = await cascadeDeleteResponses('candidateCvId', cvId);
    logger.info('Cascade delete by candidateCvId (cvs_test) completed', {
      cvId,
      deleted,
    });
  },
);
