#!/usr/bin/env node
'use strict';

/**
 * cleanup_duplicate_vacancy_copies.js
 *
 * Safe one-off cleanup for old duplicate vacancy copy docs in Worka.
 *
 * Rules:
 * - Never touch non-copy originals.
 * - Process only docs with copiedFromJobId (copy lineage signal).
 * - Process only active docs (not soft-deleted / not deleted status).
 * - Group by: ownerId + ownerType + copiedFromJobId + normalizedTitle.
 * - If group has >1 active docs:
 *    - keep doc with engagement if exactly one has engagement > 0
 *    - otherwise keep oldest by createdAt (stable by id)
 *    - soft-delete others.
 * - Ambiguous groups are skipped (e.g. >1 docs with engagement > 0).
 *
 * Usage:
 *   node scripts/cleanup_duplicate_vacancy_copies.js ./serviceAccountKey.json --dry-run
 *   node scripts/cleanup_duplicate_vacancy_copies.js ./serviceAccountKey.json --run
 */

const admin = require('firebase-admin');
const path = require('path');

const args = process.argv.slice(2);
const isRun = args.includes('--run');
const isDryRun = args.includes('--dry-run') || !isRun;

const saArg = args.find((a) => !a.startsWith('--')) || process.env.GOOGLE_APPLICATION_CREDENTIALS;
if (!saArg) {
  console.error('ERROR: service account path is required.');
  console.error('Usage: node scripts/cleanup_duplicate_vacancy_copies.js ./serviceAccountKey.json --dry-run');
  process.exit(1);
}

const serviceAccountPath = path.resolve(process.cwd(), saArg);
const serviceAccount = require(serviceAccountPath);

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const projectId = admin.app().options.projectId || serviceAccount.project_id || '';
const allowProd = args.includes('--allow-prod');

if (!projectId) {
  console.error('❌ Cannot determine projectId from service account or app options. Aborting.');
  process.exit(1);
}

if (projectId === 'worka-416c0' && !allowProd) {
  console.error('❌ Refusing to run against production project worka-416c0 without --allow-prod');
  process.exit(1);
}

console.log('[env]', {
  projectId,
  serviceAccountEmail: serviceAccount.client_email || 'n/a',
});
console.log('[mode]', {
  runMode: isDryRun ? 'DRY-RUN' : 'WRITE',
  allowProd,
});

const db = admin.firestore();
const jobsCol = db.collection('jobs');

function s(v) {
  return (v == null ? '' : String(v)).trim();
}

function n(v) {
  if (typeof v === 'number' && Number.isFinite(v)) return v;
  const parsed = Number(String(v || '').trim());
  return Number.isFinite(parsed) ? parsed : 0;
}

function normalizeCopyTitle(raw) {
  const base = s(raw).replace(/(?:\s*\(копия\)\s*)+$/i, '').trim();
  return `${base || 'Вакансия'} (копия)`;
}

function isSoftDeleted(m) {
  const status = s(m.status).toLowerCase();
  return m.isDeleted === true || m.deletedAt != null || status === 'deleted' || status === 'archived' || status === 'removed';
}

function parseDate(raw) {
  if (!raw) return null;
  if (raw && typeof raw.toDate === 'function') {
    try { return raw.toDate(); } catch (_) { return null; }
  }
  const d = new Date(raw);
  return Number.isNaN(d.getTime()) ? null : d;
}

function engagementScore(m) {
  return (
    n(m.responsesCount) +
    n(m.applicationsCount) +
    n(m.offersCount) +
    n(m.viewsCount) +
    n(m.views)
  );
}

function stableSortByCreatedAsc(a, b) {
  const ad = parseDate(a.data.createdAt) || parseDate(a.data.updatedAt) || new Date(0);
  const bd = parseDate(b.data.createdAt) || parseDate(b.data.updatedAt) || new Date(0);
  if (ad.getTime() !== bd.getTime()) return ad - bd;
  return a.id.localeCompare(b.id);
}

async function main() {
  console.log(`Mode: ${isDryRun ? 'DRY-RUN' : 'RUN'}`);
  console.log(`Collection: jobs`);

  const snap = await jobsCol.get();
  const docs = snap.docs.map((d) => ({ id: d.id, data: d.data() || {} }));

  // Only active copy lineage docs are eligible.
  const candidates = docs.filter(({ data }) => {
    if (isSoftDeleted(data)) return false;
    const ownerId = s(data.ownerId || data.ownerUid);
    const copiedFromJobId = s(data.copiedFromJobId);
    if (!ownerId) return false;
    if (!copiedFromJobId) return false; // conservative: skip ambiguous lineage-missing docs
    return true;
  });

  const groups = new Map();
  for (const d of candidates) {
    const m = d.data;
    const ownerId = s(m.ownerId || m.ownerUid);
    const ownerType = s(m.ownerType || 'personal');
    const copiedFromJobId = s(m.copiedFromJobId);
    const titleNorm = normalizeCopyTitle(m.title);
    const key = `${ownerId}|${ownerType}|${copiedFromJobId}|${titleNorm}`;
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(d);
  }

  let groupsWithDupes = 0;
  let groupsSkipped = 0;
  let plannedDeletes = 0;
  let appliedDeletes = 0;

  for (const [key, items] of groups.entries()) {
    if (items.length <= 1) continue;
    groupsWithDupes += 1;

    const withScore = items.map((x) => ({
      ...x,
      score: engagementScore(x.data),
    }));
    const engaged = withScore.filter((x) => x.score > 0);

    // Ambiguous if multiple engaged active docs exist.
    if (engaged.length > 1) {
      groupsSkipped += 1;
      console.log(`\n[SKIP][AMBIGUOUS] ${key}`);
      for (const x of withScore.sort(stableSortByCreatedAsc)) {
        console.log(`  - ${x.id} score=${x.score} title="${s(x.data.title)}" createdAt=${parseDate(x.data.createdAt) || 'n/a'}`);
      }
      continue;
    }

    let keep;
    if (engaged.length === 1) {
      keep = engaged[0];
    } else {
      keep = [...withScore].sort(stableSortByCreatedAsc)[0];
    }

    const toDelete = withScore.filter((x) => x.id !== keep.id);
    plannedDeletes += toDelete.length;

    console.log(`\n[PLAN] ${key}`);
    console.log(`  keep: ${keep.id} score=${keep.score} title="${s(keep.data.title)}"`);
    for (const x of toDelete.sort(stableSortByCreatedAsc)) {
      console.log(`  del : ${x.id} score=${x.score} title="${s(x.data.title)}"`);
    }

    if (!isDryRun) {
      const batch = db.batch();
      const now = admin.firestore.FieldValue.serverTimestamp();
      for (const x of toDelete) {
        batch.update(jobsCol.doc(x.id), {
          isDeleted: true,
          deletedAt: now,
          status: 'deleted',
          cleanup: {
            duplicateCopy: true,
            cleanedBy: 'cleanup_duplicate_vacancy_copies.js',
            keptDocId: keep.id,
            sourceDocId: s(x.data.copiedFromJobId),
            key,
            cleanedAt: now,
          },
          updatedAt: now,
        });
      }
      await batch.commit();
      appliedDeletes += toDelete.length;
    }
  }

  console.log('\n=== SUMMARY ===');
  console.log(`groups scanned (copy lineage): ${groups.size}`);
  console.log(`groups with duplicates          : ${groupsWithDupes}`);
  console.log(`groups skipped as ambiguous     : ${groupsSkipped}`);
  console.log(`planned soft-deletes            : ${plannedDeletes}`);
  console.log(`${isDryRun ? 'applied soft-deletes (dry)' : 'applied soft-deletes'} : ${isDryRun ? 0 : appliedDeletes}`);

  if (isDryRun) {
    console.log('\nDry-run complete. Re-run with --run to apply changes.');
  }
}

main()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error('FATAL:', e);
    process.exit(1);
  });
