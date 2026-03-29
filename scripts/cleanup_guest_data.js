/**
 * cleanup_guest_data.js
 *
 * One-time Node.js script that deletes Firestore documents written by
 * unauthenticated (guest) users — identified by a missing, empty, or
 * placeholder ownerId field ("", "guest", null).
 *
 * Usage:
 *   1. Install deps: npm install firebase-admin
 *   2. Set GOOGLE_APPLICATION_CREDENTIALS to your service-account JSON path,
 *      OR pass the path as an argument: node cleanup_guest_data.js ./sa.json
 *   3. Run: node cleanup_guest_data.js
 *
 * Collections scanned: cvs, jobs, applications, jobOffers, responses
 */

'use strict';

const admin = require('firebase-admin');
const path = require('path');

// ─── Init ────────────────────────────────────────────────────────────────────
const saPath = process.argv[2]
  ? path.resolve(process.argv[2])
  : process.env.GOOGLE_APPLICATION_CREDENTIALS;
const allowProd = process.argv.includes('--allow-prod');

if (!saPath) {
  console.error(
    'ERROR: Provide service-account path as argument or set GOOGLE_APPLICATION_CREDENTIALS',
  );
  process.exit(1);
}

const serviceAccount = require(saPath);
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const projectId = admin.app().options.projectId || serviceAccount.project_id || '';
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

const db = admin.firestore();

// ─── Helpers ─────────────────────────────────────────────────────────────────

/** Returns true if the value is a "guest" owner identifier. */
function isGuestOwner(value) {
  if (value === null || value === undefined) return true;
  const s = String(value).trim().toLowerCase();
  return s === '' || s === 'guest' || s === 'null' || s === 'undefined';
}

/**
 * Deletes guest docs from a collection using the given owner field name.
 * Batches deletes to stay under the 500-op Firestore limit.
 */
async function cleanupCollection(collectionName, ownerField) {
  console.log(`\nScanning /${collectionName} (ownerField="${ownerField}") …`);

  let totalDeleted = 0;
  let cursor = null;
  const BATCH_SIZE = 400;

  while (true) {
    let query = db.collection(collectionName).limit(BATCH_SIZE);
    if (cursor) query = query.startAfter(cursor);

    const snap = await query.get();
    if (snap.empty) break;
    cursor = snap.docs[snap.docs.length - 1];

    const toDelete = snap.docs.filter((doc) => {
      const data = doc.data();
      return isGuestOwner(data[ownerField]);
    });

    if (toDelete.length > 0) {
      const batch = db.batch();
      toDelete.forEach((doc) => batch.delete(doc.ref));
      await batch.commit();
      totalDeleted += toDelete.length;
      console.log(
        `  Deleted ${toDelete.length} docs in this page (total: ${totalDeleted})`,
      );
    }

    if (snap.docs.length < BATCH_SIZE) break;
  }

  console.log(`  ✓ ${collectionName}: ${totalDeleted} guest docs removed.`);
  return totalDeleted;
}

// ─── Main ────────────────────────────────────────────────────────────────────

async function main() {
  console.log('=== Worka Guest Data Cleanup ===\n');
  console.log(
    'This will DELETE all documents with empty/guest ownerId from:',
  );
  console.log(
    '  cvs, jobs (vacancies), applications, jobOffers, responses\n',
  );

  const collections = [
    { name: 'cvs',          ownerField: 'ownerId' },
    { name: 'jobs',         ownerField: 'ownerId' },
    { name: 'applications', ownerField: 'applicantId' },
    { name: 'jobOffers',    ownerField: 'employerId' },
    { name: 'responses',    ownerField: 'candidateOwnerId' },
  ];

  let grandTotal = 0;
  for (const col of collections) {
    const count = await cleanupCollection(col.name, col.ownerField);
    grandTotal += count;
  }

  console.log(`\n=== Done. Total documents deleted: ${grandTotal} ===`);
  process.exit(0);
}

main().catch((err) => {
  console.error('Fatal error:', err);
  process.exit(1);
});
