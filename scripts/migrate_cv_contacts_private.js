#!/usr/bin/env node

const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

const keyPath = process.argv[2];
const run = process.argv.includes('--run');

if (!keyPath) {
  console.error('Usage: node scripts/migrate_cv_contacts_private.js <service-account.json> [--run]');
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
const allowProd = process.argv.includes('--allow-prod');

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
  estimatedOps: 'unknown',
});

const db = admin.firestore();

const sensitiveKeys = [
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

function s(v) {
  return (v ?? '').toString().trim();
}

function extractPayload(cvId, cvData) {
  const contacts =
    cvData && cvData.contacts && typeof cvData.contacts === 'object'
      ? cvData.contacts
      : {};
  return {
    candidateId: cvId,
    cvId,
    ownerId: s(cvData.ownerId || cvData.ownerUid),
    name: s(contacts.name) || [s(contacts.firstName), s(contacts.lastName)].filter(Boolean).join(' ').trim(),
    firstName: s(contacts.firstName || cvData.firstName),
    lastName: s(contacts.lastName || cvData.lastName),
    email: s(contacts.email || cvData.email),
    phone: s(contacts.phone || cvData.phone),
    phoneCountryCode: s(contacts.phoneCountryCode || cvData.phoneCountryCode),
    phoneNumber: s(contacts.phoneNumber || cvData.phoneNumber),
    whatsapp: s(contacts.whatsapp || contacts.wa || cvData.whatsapp),
    telegram: s(contacts.telegram || contacts.tg || cvData.telegram),
    viber: s(contacts.viber || cvData.viber),
    messenger: s(contacts.messenger || contacts.facebookMessenger || cvData.messenger),
  };
}

function buildSanitizePatch(cvData) {
  const patch = {};
  let changed = false;
  const contacts =
    cvData && cvData.contacts && typeof cvData.contacts === 'object'
      ? { ...cvData.contacts }
      : null;
  if (contacts) {
    for (const key of sensitiveKeys) {
      if (Object.prototype.hasOwnProperty.call(contacts, key)) {
        delete contacts[key];
        changed = true;
      }
    }
    if (changed) {
      patch.contacts = contacts;
    }
  }
  for (const key of sensitiveKeys) {
    if (Object.prototype.hasOwnProperty.call(cvData || {}, key)) {
      patch[key] = admin.firestore.FieldValue.delete();
      changed = true;
    }
  }
  return changed ? patch : null;
}

async function main() {
  const cvs = await db.collection('cvs').get();
  const stats = {
    scanned: cvs.size,
    privateUpserts: 0,
    publicSanitize: 0,
  };

  for (const doc of cvs.docs) {
    const cvId = doc.id;
    const data = doc.data() || {};
    const payload = extractPayload(cvId, data);
    const hasSensitive = [
      payload.email,
      payload.phone,
      payload.whatsapp,
      payload.telegram,
      payload.viber,
      payload.messenger,
    ].some((v) => s(v).length > 0);

    if (hasSensitive || payload.ownerId) {
      stats.privateUpserts += 1;
      if (run) {
        await db.collection('candidate_contacts_private').doc(cvId).set(
          {
            ...payload,
            updated_at: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
      }
    }

    const patch = buildSanitizePatch(data);
    if (patch) {
      stats.publicSanitize += 1;
      if (run) {
        await db.collection('cvs').doc(cvId).set(
          {
            ...patch,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
      }
    }
  }

  console.log(JSON.stringify({ run, ...stats }, null, 2));
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
