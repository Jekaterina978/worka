# Stripe Monetization Post-Launch Monitoring (Worka)

Use this checklist daily in first 7 days, then weekly.

## 1) Core Metrics & Signals

## Stripe/Webhook health
- `payment_intent.succeeded` count (hour/day)
- `payment_intent.payment_failed` count (hour/day)
- `failed / succeeded` ratio
- duplicate webhook rate (events marked duplicate/ignored)
- unmatched/validation-failed webhook count

## Funnel conversion
- `purchase_started -> purchase_success`
- `paywall_opened -> purchase_success`
- `purchase_success -> contact_unlock_success`
- `contact_unlock_tap -> contact_unlock_success`

## Reliability/support signals
- count of support cases: “оплата прошла, но кредиты не пришли”
- `webhook_pending` UI outcomes frequency
- avg time from `purchase_success` (client) to wallet balance increase

---

## 2) What to watch in Functions logs

Primary sources:
- `functions/index.js` logs for:
  - `POST /payments/create-payment-intent created`
  - `POST /payments/create-payment-intent failed`
  - `stripeWebhook duplicate event ignored`
  - `stripeWebhook validation failed for payment_intent.succeeded`
  - `stripeWebhook payment failed`
  - `stripeWebhook failed`
  - `markPaymentFailed ignored for already succeeded purchase`

Red flags:
- spikes in `create-payment-intent failed`
- non-zero recurring `validation failed`
- frequent webhook signature/config errors
- repeated `purchase_not_found` / unmatched succeeded events

---

## 3) Firestore collections to verify

## `purchases`
Check:
- succeeded payments become `status=succeeded`
- `entitlements_applied=true` for succeeded credits purchases
- no invalid transitions (e.g. succeeded -> failed)

## `credit_ledger`
Check:
- every credits purchase has positive `delta` (`reason=purchase_credits`)
- unlock spend has `delta=-1` (`reason=contact_unlock`)
- no duplicate positive grants for same `payment_intent_id`

## `employers/{uid}`
Check:
- `credits_balance` matches ledger net effect
- no sudden unexplained drops/increments

## `stripe_webhook_events`
Check:
- events recorded for processed webhooks
- duplicates marked/ignored
- failed/validation statuses tracked and not silently dropped

---

## 4) Critical analytics events

Must be present and non-zero (if traffic exists):
- `paywall_opened`
- `pack_selected`
- `purchase_started`
- `purchase_success`
- `purchase_failed`
- `contact_unlock_tap`
- `contact_unlock_confirmed`
- `contact_unlock_success`
- `contact_unlock_failed`
- `contact_already_unlocked`
- `credits_screen_opened`

Key params to monitor:
- `entry_point`
- `pack_id`
- `credits_before`
- `credits_after`
- `result_status`
- `candidate_safe_id`

Data quality checks:
- no major event drop after release
- no abnormal duplicate bursts from retries/rebuilds
- pack distribution sane (`contact_1`, `contact_10`, `contact_30`)

---

## 5) Recommended operational thresholds

- Webhook success rate target: `> 99%`
- Validation failures target: `0` (investigate any non-zero)
- Duplicate webhook processing causing extra grants: `0` (must always be zero)
- Support tickets “paid but no credits”:
  - investigate immediately if `> 2/day` in first week
- Median time payment->credits visible:
  - target `< 30s`, investigate if sustained `> 2 min`

---

## 6) Incident triage (paid but no credits)

1. Find `paymentIntentId` from Stripe/support data.
2. Check `purchases/{paymentIntentId}`:
   - status, `entitlements_applied`.
3. Check `stripe_webhook_events` for related event processing.
4. Check `credit_ledger` for expected positive delta.
5. Check employer `credits_balance`.
6. If webhook missing/delayed:
   - verify Stripe endpoint delivery and function logs.
7. If validation failed:
   - inspect amount/currency/product metadata mismatch and fix config.

---

## 7) Reporting cadence

- Daily (first week):
  - succeeded/failed counts
  - funnel conversions
  - incident count
- Weekly:
  - conversion trends by `entry_point`
  - package mix
  - unlock completion after purchase
