#!/usr/bin/env node

const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

const keyPath = process.argv[2];
const run = process.argv.includes('--run');
const allowProd = process.argv.includes('--allow-prod');

const collectionArg = process.argv.find((arg) =>
  arg.startsWith('--collections='),
);
const explicitCollections = collectionArg
  ? collectionArg
      .split('=')
      .slice(1)
      .join('=')
      .split(',')
      .map((v) => v.trim())
      .filter((v) => v.length > 0)
  : null;

const defaultCollections = [
  'applications',
  'jobOffers',
  // Legacy interaction collections that may still exist in prod/test projects.
  'responses',
  'responses_test',
];

const collectionsToScan = explicitCollections ?? defaultCollections;

if (!keyPath) {
  console.error(
    'Usage: node scripts/migrate_interaction_candidate_contacts_sanitize.js <service-account.json> [--run] [--collections=applications,jobOffers,responses]',
  );
  process.exit(1);
}

const resolvedKeyPath = path.resolve(process.cwd(), keyPath);
if (!fs.existsSync(resolvedKeyPath)) {
  console.error(`Service account not found: ${resolvedKeyPath}`);
  process.exit(1);
}

const serviceAccount = require(resolvedKeyPath);
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
console.log('[mode]', {
  runMode: run ? 'WRITE' : 'DRY-RUN',
  allowProd,
  collectionsToScan,
});

const db = admin.firestore();

const topLevelCandidateSensitiveKeys = [
  'candidateEmail',
  'candidatePhone',
  'candidateEmailSnapshot',
  'candidatePhoneSnapshot',
  'applicantEmailSnapshot',
  'applicantPhoneSnapshot',
  'candidateWhatsapp',
  'candidateTelegram',
  'candidateViber',
  'candidateMessenger',
  'candidateContactEmail',
  'candidateContactPhone',
];

const nestedCandidateSensitiveKeys = [
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
  'candidateEmail',
  'candidatePhone',
  'candidateEmailSnapshot',
  'candidatePhoneSnapshot',
];

function mapFrom(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    return null;
  }
  return { ...value };
}

function stripKeys(target, keys) {
  if (!target) return { changed: false, removed: [] };
  let changed = false;
  const removed = [];
  for (const key of keys) {
    if (Object.prototype.hasOwnProperty.call(target, key)) {
      delete target[key];
      changed = true;
      removed.push(key);
    }
  }
  return { changed, removed };
}

function sanitizeCandidateSnapshot(snapshotRaw) {
  const snapshot = mapFrom(snapshotRaw);
  if (!snapshot) {
    return {
      changed: false,
      snapshot: snapshotRaw,
      removedPaths: [],
    };
  }

  const removedPaths = [];
  let changed = false;

  const top = stripKeys(snapshot, nestedCandidateSensitiveKeys);
  if (top.changed) {
    changed = true;
    for (const key of top.removed) {
      removedPaths.push(`candidateSnapshot.${key}`);
    }
  }

  const nestedMaps = ['contacts', 'contact', 'socialLinks', 'business'];
  for (const nestedKey of nestedMaps) {
    const nestedMap = mapFrom(snapshot[nestedKey]);
    if (!nestedMap) continue;
    const nested = stripKeys(nestedMap, nestedCandidateSensitiveKeys);
    if (nested.changed) {
      changed = true;
      snapshot[nestedKey] = nestedMap;
      for (const key of nested.removed) {
        removedPaths.push(`candidateSnapshot.${nestedKey}.${key}`);
      }
    }
  }

  return {
    changed,
    snapshot,
    removedPaths,
  };
}

function buildPatch(data) {
  const patch = {};
  const removedPaths = [];

  for (const key of topLevelCandidateSensitiveKeys) {
    if (Object.prototype.hasOwnProperty.call(data, key)) {
      patch[key] = admin.firestore.FieldValue.delete();
      removedPaths.push(key);
    }
  }

  if (Object.prototype.hasOwnProperty.call(data, 'candidateSnapshot')) {
    const sanitized = sanitizeCandidateSnapshot(data.candidateSnapshot);
    if (sanitized.changed) {
      patch.candidateSnapshot = sanitized.snapshot;
      removedPaths.push(...sanitized.removedPaths);
    }
  }

  return {
    patch,
    removedPaths,
    changed: removedPaths.length > 0,
  };
}

async function collectionExists(name) {
  const snap = await db.collection(name).limit(1).get();
  return !snap.empty;
}

async function scanCollection(name) {
  const collectionRef = db.collection(name);
  const stats = {
    collection: name,
    exists: false,
    scanned: 0,
    modified: 0,
    skipped: 0,
    dryRunModified: 0,
    removedFieldHits: 0,
  };

  const exists = await collectionExists(name);
  stats.exists = exists;
  if (!exists) return stats;

  const limit = 400;
  let lastDoc = null;
  const sample = [];

  while (true) {
    let query = collectionRef.orderBy(admin.firestore.FieldPath.documentId()).limit(limit);
    if (lastDoc) {
      query = query.startAfter(lastDoc.id);
    }

    const snap = await query.get();
    if (snap.empty) break;

    for (const doc of snap.docs) {
      stats.scanned += 1;
      const data = doc.data() || {};
      const { patch, removedPaths, changed } = buildPatch(data);
      if (!changed) {
        stats.skipped += 1;
        continue;
      }

      stats.modified += 1;
      stats.dryRunModified += 1;
      stats.removedFieldHits += removedPaths.length;
      if (sample.length < 20) {
        sample.push({
          docId: doc.id,
          removed: removedPaths,
        });
      }

      if (run) {
        await collectionRef.doc(doc.id).set(
          {
            ...patch,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
      }
    }

    lastDoc = snap.docs[snap.docs.length - 1];
    if (snap.size < limit) break;
  }

  stats.sample = sample;
  return stats;
}

async function main() {
  const startedAt = new Date().toISOString();
  const perCollection = [];

  for (const name of collectionsToScan) {
    const stat = await scanCollection(name);
    perCollection.push(stat);
  }

  const totals = perCollection.reduce(
    (acc, item) => {
      acc.scanned += item.scanned;
      acc.modified += item.modified;
      acc.skipped += item.skipped;
      acc.removedFieldHits += item.removedFieldHits || 0;
      if (item.exists) acc.collectionsFound += 1;
      else acc.collectionsMissing += 1;
      return acc;
    },
    {
      scanned: 0,
      modified: 0,
      skipped: 0,
      removedFieldHits: 0,
      collectionsFound: 0,
      collectionsMissing: 0,
    },
  );

  const report = {
    run,
    startedAt,
    finishedAt: new Date().toISOString(),
    collectionsRequested: collectionsToScan,
    totals,
    collections: perCollection,
  };

  console.log(JSON.stringify(report, null, 2));
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
