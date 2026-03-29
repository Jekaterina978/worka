# Worka Payments Backend (Stripe + Firebase Functions)

This backend implements one-time Stripe payments and server-side entitlements for Worka.

## Deployed functions

- `api` (HTTP):
  - `POST /payments/payment-intent`
  - `POST /employer/credits/consume`
  - `GET /employer/me`
  - `GET /employer/credits/history`
  - `POST /employer/verification/upload` (multipart/form-data)
  - `GET /employer/verification/status`
- `stripeWebhook` (HTTP): Stripe webhook endpoint

## Environment variables

Set these for Cloud Functions runtime:

- `STRIPE_SECRET_KEY` - Stripe secret key (`sk_live...` / `sk_test...`)
- `STRIPE_WEBHOOK_SECRET` - webhook signing secret (`whsec_...`)
- `STRIPE_API_VERSION` - optional, default: `2025-02-24.acacia`

## Install + deploy

```bash
cd functions
npm install
firebase deploy --only functions
```

## Stripe webhook setup

Configure Stripe endpoint URL to:

```text
https://<region>-<project-id>.cloudfunctions.net/stripeWebhook
```

Subscribe events:
- `payment_intent.succeeded`
- `payment_intent.payment_failed`

## Auth for API endpoints

All `api` endpoints except `/health` require Firebase ID token:

```http
Authorization: Bearer <firebase_id_token>
```

## Product IDs (POST /payments/payment-intent)

- `contact_1` (€2.99)
- `contact_10` (€24.99)
- `contact_30` (€59.99)
- `promotion_bump` (€4.99)
- `promotion_urgent` (€7.99)
- `promotion_top` (€12.99)
- `employer_verification` (€19.00)

All are charged in EUR.

## Entitlement source of truth

Entitlements are applied **only on webhook** (`payment_intent.succeeded`), never from client callbacks.

Applied effects:
- Credits package -> increments `employers/{uid}.credits_balance` and writes `credit_ledger`
- Job promotion -> creates active record in `job_boosts`
- Verification -> sets verification status to `pending` and creates/updates `verification_requests/{uid}`

## Firestore collections used

- `employers`
- `purchases`
- `credit_ledger`
- `job_boosts`
- `verification_requests`
- `users` (mirrored `billing` fields for app compatibility)

## Notes

- VAT ID is stored on employer profile (`vat_id`) and attached to Stripe customer metadata.
- Contact unlock consumes 1 credit unless contact already unlocked for that candidate.
