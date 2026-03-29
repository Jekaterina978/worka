# Monetization Hardening: Release-Readiness Checklist

## 1) Deploy Order
1. Deploy Cloud Functions (`functions/index.js`) with server-authoritative unlock/contact endpoints.
2. Deploy Firestore Rules (`firestore.rules`) that block client writes for wallet/unlock and protect private contacts.
3. Run data migrations (dry-run first, then apply).
4. Deploy Flutter app build with latest interaction/favorites hardening.
5. Run post-deploy smoke checks on production project.

## 2) Migration Scripts To Run
Run in this order:

1. CV contacts split/sanitization:
```bash
node scripts/migrate_cv_contacts_private.js <service-account.json>
node scripts/migrate_cv_contacts_private.js <service-account.json> --run
```

2. Historical interaction snapshot cleanup:
```bash
node scripts/migrate_interaction_candidate_contacts_sanitize.js <service-account.json>
node scripts/migrate_interaction_candidate_contacts_sanitize.js <service-account.json> --run
```

Optional targeted run:
```bash
node scripts/migrate_interaction_candidate_contacts_sanitize.js <service-account.json> --run --collections=applications,jobOffers,responses
```

Success criteria:
- Dry-run before apply shows expected `modified` counts.
- Post-apply dry-run shows `modified ~= 0`.

## 3) Manual QA Scenarios (Must Pass)
1. Employer with `0` credits: `Показать контакты` always opens paywall, no contacts visible.
2. Purchase -> unlock -> auto-resume: after successful purchase, target contact opens without extra manual retry.
3. Already unlocked candidate: opens immediately, no extra credit spend.
4. Candidate search / candidate details / favorites: no full contacts before unlock.
5. Interaction screens (`apply_response`, `interaction_message`): no candidate email/phone before unlock.
6. Reinstall / logout / new device: unlocked state restored from server, not from local cache only.
7. Candidate owner edit/view: own contacts still editable/readable without crash.
8. No direct bypass via hidden links/buttons (`mailto/tel`) before unlock.

## 4) Rollback Considerations
1. Keep previous Functions and app build artifacts available for rollback.
2. Firestore rules rollback only if critical outage; avoid reopening direct contact reads.
3. Migrations are destructive for sensitive snapshot fields:
   - Do not run `--run` without validated dry-run output.
   - If rollback needed after cleanup, restore from Firestore backup/export.
4. If partial rollout issue:
   - Freeze app release,
   - Roll back Functions first,
   - Re-check rules compatibility.

## 5) Post-Release Monitoring
Monitor first 24-72h:

1. Functions errors:
   - `/employer/credits/consume`
   - `/employer/contacts/:candidateId`
   - `/employer/contacts/unlocked`
2. Paywall/unlock funnel analytics:
   - `paywall_opened`
   - `purchase_started/success/failed`
   - `contact_unlock_confirmed/success/failed`
   - `contact_already_unlocked`
3. Data hygiene spot checks:
   - `cvs/*` should not expose full candidate contacts publicly.
   - `applications/jobOffers/responses` should not contain historical candidate contact snapshots.
4. Product health:
   - drop in candidate visibility in favorites/search (unexpected),
   - unlock success rate,
   - support tickets for “paid but contacts not opened”.

