# Worka Canonical Contact Paywall — Experiment Matrix

## Active A/B Flags

| Experiment | Flag | Variant A (control) | Variant B |
|---|---|---|---|
| CTA copy | `CONTACT_PAYWALL_CTA_AB` | Price-led CTA (`Купить N контактов за €...`) | Action-led CTA (`Открыть N контактов сейчас`) |
| Social proof (pack 10) | `CONTACT_PAYWALL_SOCIAL_PROOF_AB` | No extra line | `Чаще всего выбирают работодатели` under `contact_10` |
| Value emphasis (packs 10/30) | `CONTACT_PAYWALL_VALUE_AB` | No extra value line | Dynamic savings line (`Экономия X%...`) for `contact_10`/`contact_30` |
| First-time framing | `CONTACT_PAYWALL_FIRST_TIME_AB` | No first-time framing block | First-time block for first unlock users only |
| Urgency framing | `CONTACT_PAYWALL_URGENCY_AB` | No urgency block | Urgency/loss-framing block under header |

Notes:
- `FIRST_TIME` applies only when `is_first_unlock_mode=1`.
- Variant values are logged in `paywall_opened` as `a/b`.

---

## Core Metrics per Experiment

- Primary funnel:
  - `paywall_opened -> purchase_success`
- Commercial mix:
  - pack selection share (`contact_1` / `contact_10` / `contact_30`)
  - ARPU proxy (weighted average selected pack value)
- Unlock completion:
  - `purchase_success -> contact_unlock_success`

Recommended event cuts:
- by `entry_point`
- by `is_first_unlock_mode`
- by selected `pack_id`

---

## Contamination / Interpretation Risks

Use caution when analyzing together:

1. `CTA_AB` + `URGENCY_AB`
- Both influence top-of-funnel click intent; hard to isolate CTA effect.

2. `SOCIAL_PROOF_AB` + `VALUE_AB`
- Both push higher-tier packages (`10/30`), can inflate each other.

3. `FIRST_TIME_AB` with any other experiment
- New users behave differently; must segment by `is_first_unlock_mode`.

4. Full 5-experiment parallel readout
- 32 combinations possible; many cells become underpowered.

---

## Recommended Rollout Order

## Phase 1 (single-variable, clean read)
1. `CTA_AB`
2. `SOCIAL_PROOF_AB`
3. `VALUE_AB`

Run each with others pinned to control (`A`) where possible.

## Phase 2 (segmented cohort test)
4. `FIRST_TIME_AB`

Analyze only in `is_first_unlock_mode=1` cohort.

## Phase 3 (higher-risk persuasion)
5. `URGENCY_AB`

Run after baseline is stable; monitor for negative trust signals.

---

## Practical Guardrails

- During one experiment readout, force non-target flags to `A` via dart-define.
- Keep attribution window fixed (same days/weekparts).
- Do not change pricing/copy outside tested flag during active readout.
- Stop criteria:
  - meaningful lift in `purchase_success`
  - no regression in `purchase_success -> contact_unlock_success`
  - no support spike (`оплата прошла, но кредиты не пришли`)
