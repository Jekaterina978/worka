# Worka Stripe Test-Mode Validation Sheet

Use this checklist for final manual validation in Stripe **test mode**.

## Common Preconditions (for all scenarios)

- App built/run with test config:
  - `STRIPE_PUBLISHABLE_KEY=pk_test_...`
  - non-production `STRIPE_ENV` on client.
- Functions configured with test backend config:
  - `STRIPE_SECRET_KEY=sk_test_...`
  - `STRIPE_WEBHOOK_SECRET=whsec_...`
  - `STRIPE_ENV=test` (or unset, but not `production`).
- Webhook endpoint in Stripe Dashboard points to deployed `stripeWebhook`.
- Test employer account exists (`uid = <EMPLOYER_UID>`).
- Test candidate exists (`candidateId = <CANDIDATE_ID>`).
- Firestore viewer ready for:
  - `employers/<EMPLOYER_UID>`
  - `purchases/*`
  - `credit_ledger/*`
  - `stripe_webhook_events/*`
  - `employers/<EMPLOYER_UID>/contact_unlocks/*`

---

## 1) Successful Payment (baseline)

### Preconditions
- Employer has known starting balance `B0`.
- Candidate can be any (unlock not required for this scenario).

### Steps
1. Open credits wallet.
2. Select pack (e.g. `contact_10`).
3. Complete PaymentSheet with successful Stripe test card.
4. Wait until wallet refresh/polling completes.

### Expected Firestore changes
- `purchases/<paymentIntentId>`:
  - `status = succeeded`
  - `entitlements_applied = true`
  - valid `product_id`, `amount`, `currency`.
- `credit_ledger` new entry:
  - `employer_id = <EMPLOYER_UID>`
  - `delta = +10` (for `contact_10`)
  - `reason = purchase_credits`
  - `meta.payment_intent_id = <paymentIntentId>`.
- `employers/<EMPLOYER_UID>.credits_balance = B0 + 10`.
- `stripe_webhook_events/<eventId>`:
  - processed status (`processed`).

### Expected UI result
- Payment success feedback.
- Wallet balance increases.
- No manual local credit increment artifacts before webhook.

---

## 2) Cancelled Payment

### Preconditions
- Starting balance `B0` recorded.

### Steps
1. Open paywall or wallet purchase.
2. Start PaymentSheet.
3. Cancel payment in sheet.

### Expected Firestore changes
- No positive grant in `credit_ledger`.
- `employers/<EMPLOYER_UID>.credits_balance` remains `B0`.
- `purchases` may have pending/created record, but **no succeeded+applied grant**.

### Expected UI result
- User sees cancel feedback.
- Balance unchanged.
- Candidate remains locked if flow was contact unlock.

---

## 3) Failed Payment

### Preconditions
- Starting balance `B0` recorded.

### Steps
1. Start payment with Stripe test method causing failure.
2. Wait for webhook processing.

### Expected Firestore changes
- `purchases/<paymentIntentId>` has failed-like status (`failed` or failure marker).
- `stripe_webhook_events/<eventId>` has failed processing status (e.g. `processed_failed`).
- No `credit_ledger` positive delta for that intent.
- `employers/<EMPLOYER_UID>.credits_balance` unchanged (`B0`).

### Expected UI result
- User-friendly error shown.
- No balance increase.

---

## 4) Duplicate Webhook Idempotency

### Preconditions
- Have one already successful `paymentIntentId` from scenario 1.

### Steps
1. Replay same Stripe webhook event (`payment_intent.succeeded`) via Stripe CLI/dashboard retry.
2. Wait for function execution.

### Expected Firestore changes
- `stripe_webhook_events/<sameEventId>` recognized as duplicate/processed.
- No second credits grant:
  - no extra positive `credit_ledger` for same intent.
  - `credits_balance` does not increment again.
- `purchases/<paymentIntentId>.entitlements_applied` stays true.

### Expected UI result
- No visible double top-up.
- Wallet remains consistent.

---

## 5) Wallet Purchase Flow

### Preconditions
- Open `Мои кредиты`.
- Starting balance `B0`.

### Steps
1. Select each pack one-by-one in separate runs:
   - `contact_1`, `contact_10`, `contact_30`.
2. Complete payment successfully for each run.

### Expected Firestore changes
- Per run, one succeeded purchase and one positive ledger entry:
  - `+1`, `+10`, `+30` respectively.
- `credits_balance` increases cumulatively by pack credits.

### Expected UI result
- Selected pack amount matches checkout.
- Balance updates after webhook sync.
- Success feedback displayed.

---

## 6) Contact Unlock Purchase Flow (auto-resume)

### Preconditions
- Candidate is locked (no `contact_unlocks/<candidateId>` doc).
- Employer balance is `0`.

### Steps
1. Tap `Показать контакты` on candidate.
2. Pay via paywall.
3. Do not tap again; wait for orchestration.

### Expected Firestore changes
- Purchase success records as in scenario 1.
- Then spend record:
  - `credit_ledger` entry with `delta = -1`, `reason = contact_unlock`.
- `employers/<EMPLOYER_UID>/contact_unlocks/<CANDIDATE_ID>` created.
- Net `credits_balance = purchasedCredits - 1`.

### Expected UI result
- After payment + sync, contact unlock auto-resumes.
- Contacts become visible without second manual purchase.

---

## 7) Already Unlocked Candidate

### Preconditions
- `employers/<EMPLOYER_UID>/contact_unlocks/<CANDIDATE_ID>` exists.
- Candidate previously unlocked.

### Steps
1. Open same candidate again.
2. Tap contact action.

### Expected Firestore changes
- No new spend (`delta = -1`) for same candidate.
- No new purchase required.
- Balance unchanged.

### Expected UI result
- Contacts open immediately.
- No paywall shown.

---

## 8) Webhook Lag / Pending State

### Preconditions
- Candidate locked.
- Employer balance `0`.
- Introduce webhook delay (or simulate slow delivery).

### Steps
1. Start unlock payment from candidate paywall.
2. Complete PaymentSheet success.
3. Observe UI before webhook arrives, then after webhook arrives.

### Expected Firestore changes
- Before webhook: no positive credit grant yet.
- After webhook:
  - succeeded purchase + entitlement applied,
  - positive ledger grant,
  - then unlock spend `-1` when auto-resume finishes,
  - unlock doc created.

### Expected UI result
- Temporary pending message is acceptable.
- Final state must auto-resume to unlocked contacts after webhook grant.
- No double charge / no duplicate spend.

---

## Focused Collection Checks (must verify in every run)

## `purchases`
- One document per `paymentIntentId`.
- Correct `product_id`, `amount`, `currency`.
- For success: `status=succeeded` and `entitlements_applied=true`.
- No inconsistent transition from succeeded to failed.

## `credit_ledger`
- Purchase grant entries have positive `delta` and `reason=purchase_credits`.
- Unlock spend entries have `delta=-1` and `reason=contact_unlock`.
- No duplicated grant/spend for same business action.

## `employers/{uid}.credits_balance`
- Changes only by expected deltas.
- Matches ledger net effect over tested actions.

## `stripe_webhook_events`
- Event docs created for incoming Stripe webhooks.
- Duplicates are marked/ignored, not re-applied.
- Failed events recorded without granting credits.

---

## Fail Conditions (global)

- Credits appear in UI or Firestore without webhook-backed grant.
- Duplicate webhook increases balance twice.
- Unlock consumes more than 1 credit for one candidate unlock.
- Candidate contacts shown while still locked.
- Cancelled/failed payment changes balance.
