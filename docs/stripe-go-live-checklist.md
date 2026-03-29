# Stripe Go Live Checklist (Worka)

## 1) Config Map (where each value is used)

### Flutter (`lib/main.dart`)
- `STRIPE_PUBLISHABLE_KEY`
  - Required for Stripe SDK initialization.
  - In `release` or `STRIPE_ENV=production`, app startup is blocked for `pk_test_...`.
- `STRIPE_ENV` (`test` / `production`, optional)
  - Optional explicit environment marker for runtime key checks.
- `STRIPE_MERCHANT_IDENTIFIER`
  - Required for iOS Apple Pay-capable setup.
- `STRIPE_URL_SCHEME`
  - Required for return URL/deep-link handling.

### Firebase Functions (`functions/index.js`)
- `STRIPE_SECRET_KEY`
  - Required to create PaymentIntent and verify webhook payloads.
  - If `STRIPE_ENV=production`, backend rejects Stripe API requests with `sk_test_...`.
- `STRIPE_WEBHOOK_SECRET`
  - Required for `Stripe-Signature` verification in `stripeWebhook`.
- `STRIPE_API_VERSION` (optional)
  - Stripe API version used by backend SDK.
- `STRIPE_ENV` (`test` / `production`, recommended)
  - Enables strict live-key guard in production mode.

## 2) Operational Setup

### Flutter run/build (example)
```bash
flutter run \
  --dart-define=STRIPE_PUBLISHABLE_KEY=pk_test_xxx \
  --dart-define=STRIPE_MERCHANT_IDENTIFIER=merchant.com.example.worka \
  --dart-define=STRIPE_URL_SCHEME=worka
```

### Firebase Functions env (example)
```bash
firebase functions:config:set \
  stripe.secret_key="sk_test_xxx" \
  stripe.webhook_secret="whsec_xxx" \
  stripe.api_version="2025-02-24.acacia" \
  stripe.env="test"
```

Then deploy Functions.

### Stripe Dashboard webhook
Create endpoint to `stripeWebhook` function URL and subscribe to:
- `payment_intent.succeeded`
- `payment_intent.payment_failed`

## 3) iOS / Android Setup

### iOS
- Configure URL scheme matching `STRIPE_URL_SCHEME`.
- Configure merchant ID matching `STRIPE_MERCHANT_IDENTIFIER` (if Apple Pay is used).
- Verify app can return from external payment auth to app.

### Android
- Ensure Stripe return URL handling is configured.
- Verify manifest/intent-filter setup for deep link callback scheme.

## 4) Test Mode Validation (manual E2E)

## A. Success path (wallet purchase)
Preconditions:
- Stripe test keys configured.
- User logged in as employer.

Steps:
1. Open wallet/credits screen.
2. Select pack (`contact_1` / `contact_10` / `contact_30`).
3. Complete PaymentSheet with successful test card.

Expected:
- Client sees success.
- Webhook `payment_intent.succeeded` received.
- `employers/{uid}.credits_balance` increases.
- `purchases/{paymentIntentId}` written with succeeded state.
- `credit_ledger` has purchase delta.

Fail if:
- No webhook grant.
- Balance unchanged after polling window.

## B. Cancel path
Steps:
1. Start payment from wallet or contact paywall.
2. Cancel PaymentSheet.

Expected:
- User sees cancel feedback.
- No credit changes.
- No unlock granted.

Fail if:
- Credits changed or unlock granted.

## C. Failed payment path
Steps:
1. Start payment with failing test method/card.

Expected:
- User sees error feedback.
- Webhook `payment_intent.payment_failed` recorded.
- No credit grant.

Fail if:
- Any positive credit delta appears.

## D. Duplicate webhook safety
Steps:
1. Replay same succeeded webhook event (Stripe CLI replay).

Expected:
- Event deduplicated via `stripe_webhook_events/{eventId}`.
- No double grant.

Fail if:
- Credits increment twice for same payment intent.

## E. Unlock flow auto-resume
Steps:
1. Open locked candidate contact.
2. Pay from contact paywall.
3. Wait for webhook grant.

Expected:
- Wallet sync/polling detects new credits.
- Unlock spend consumes 1 credit exactly once.
- Contacts become visible.

Fail if:
- Requires second manual tap after successful purchase.
- Double spend occurs.

## 5) Production Switch Steps

1. Set production backend config:
   - `STRIPE_SECRET_KEY=sk_live_...`
   - `STRIPE_WEBHOOK_SECRET=whsec_...` (from live webhook endpoint)
   - `STRIPE_ENV=production`
2. Deploy Functions and verify startup logs show:
   - `stripeEnv=production`
   - `requireLiveStripeKeys=true`
   - no test-key warning/errors.
3. Update Stripe Dashboard live webhook endpoint to production `stripeWebhook` URL.
4. Build/release app with:
   - `STRIPE_PUBLISHABLE_KEY=pk_live_...`
   - `STRIPE_ENV=production`
5. App startup must fail if `pk_test_...` is used in release/prod mode.
4. Run smoke tests:
   - wallet purchase success/cancel/fail
   - contact unlock purchase + auto-resume
   - duplicate webhook replay
5. Monitor:
   - Functions logs: create-payment-intent + webhook processing
   - mismatch/validation failures
   - pending purchases not transitioning

## 6) Launch Blockers (must be green)
- Publishable key configured in app build.
- Secret + webhook secret configured in Functions.
- Webhook events delivered and verified.
- No local credit grant path exists.
- Idempotency confirmed by replay test.
