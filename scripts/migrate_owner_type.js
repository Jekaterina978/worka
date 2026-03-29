'use strict';

/**
 * migrate_owner_type.js
 *
 * Миграция схемы Worka: добавляет ownerType / vacancyOwnerType / employerType
 * в коллекции jobs, applications, jobOffers.
 *
 * Шаги:
 *   1. jobs        — проставляет ownerType="personal" где поле отсутствует.
 *   2. applications — подтягивает вакансию и копирует ownerType → vacancyOwnerType.
 *   3. jobOffers   — подтягивает вакансию и копирует ownerType → vacancyOwnerType,
 *                    employerType (если отсутствует).
 *   4. responses   — legacy коллекция, аналогично applications (type=="apply") и offers (type=="offer").
 *
 * Запуск:
 *   node migrate_owner_type.js <path/to/serviceAccountKey.json> [--dry-run]
 *
 * --dry-run  показывает изменения без записи в Firestore.
 */

const admin = require('firebase-admin');
const path  = require('path');

// ─── CLI ─────────────────────────────────────────────────────────────────────

const args    = process.argv.slice(2);
const DRY_RUN = args.includes('--dry-run');
const allowProd = args.includes('--allow-prod');
const saArg   = args.find((a) => !a.startsWith('--'));
const saPath  = saArg
  ? path.resolve(saArg)
  : process.env.GOOGLE_APPLICATION_CREDENTIALS;

if (!saPath) {
  console.error('ERROR: укажи путь к serviceAccountKey.json\n  node migrate_owner_type.js ./key.json');
  process.exit(1);
}

const serviceAccount = require(saPath);
admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });

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
  runMode: DRY_RUN ? 'DRY-RUN' : 'WRITE',
  allowProd,
});

const db = admin.firestore();

// ─── Константы ────────────────────────────────────────────────────────────────

const BATCH_SIZE     = 400;  // Firestore max 500, держим запас
const DEFAULT_TYPE   = 'personal'; // значение по умолчанию для исторических записей
const VALID_TYPES    = new Set(['personal', 'business']);

// ─── Helpers ─────────────────────────────────────────────────────────────────

function s(v) { return (v == null ? '' : String(v)).trim(); }

/** Применяет batch патчей (chunks по BATCH_SIZE). Возвращает кол-во обновлений. */
async function commitPatches(patches) {
  if (patches.length === 0) return 0;
  let written = 0;
  for (let i = 0; i < patches.length; i += BATCH_SIZE) {
    const chunk = patches.slice(i, i + BATCH_SIZE);
    if (!DRY_RUN) {
      const batch = db.batch();
      chunk.forEach(({ ref, data }) => batch.update(ref, data));
      await batch.commit();
    }
    written += chunk.length;
    process.stdout.write(`\r    ${DRY_RUN ? '[dry] ' : ''}записано: ${written}/${patches.length}   `);
  }
  process.stdout.write('\n');
  return written;
}

/** Полная пагинация коллекции. Возвращает все документы. */
async function fetchAll(collectionName) {
  const all = [];
  let cursor = null;
  while (true) {
    let q = db.collection(collectionName)
              .orderBy(admin.firestore.FieldPath.documentId())
              .limit(BATCH_SIZE);
    if (cursor) q = q.startAfter(cursor);
    const snap = await q.get();
    if (snap.empty) break;
    all.push(...snap.docs);
    cursor = snap.docs[snap.docs.length - 1];
    if (snap.docs.length < BATCH_SIZE) break;
  }
  return all;
}

// Кэш вакансий: jobId → ownerType
const jobOwnerTypeCache = new Map();

async function resolveJobOwnerType(jobId) {
  const id = s(jobId);
  if (!id) return null;
  if (jobOwnerTypeCache.has(id)) return jobOwnerTypeCache.get(id);
  const snap = await db.collection('jobs').doc(id).get();
  if (!snap.exists) {
    jobOwnerTypeCache.set(id, null);
    return null;
  }
  const data = snap.data();
  const ot = s(data.ownerType);
  const resolved = VALID_TYPES.has(ot) ? ot : DEFAULT_TYPE;
  jobOwnerTypeCache.set(id, resolved);
  return resolved;
}

// ─── Шаг 1: jobs ─────────────────────────────────────────────────────────────

async function migrateJobs() {
  console.log('\n━━━ 1/4  jobs → ownerType ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  const docs = await fetchAll('jobs');
  console.log(`  Найдено ${docs.length} вакансий`);

  const patches = [];
  const unknown = []; // нет ownerType — ставим personal, но логируем

  for (const doc of docs) {
    const m = doc.data();
    const existing = s(m.ownerType);

    // Уже верное значение — пропускаем
    if (VALID_TYPES.has(existing)) {
      jobOwnerTypeCache.set(doc.id, existing);
      continue;
    }

    const resolved = DEFAULT_TYPE;
    jobOwnerTypeCache.set(doc.id, resolved);
    unknown.push({ id: doc.id, title: s(m.title), ownerId: s(m.ownerId) });

    patches.push({
      ref: doc.reference,
      data: {
        ownerType: resolved,
        _migratedOwnerType: true,
        _migratedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
    });
  }

  if (unknown.length > 0) {
    console.log(`\n  ⚠️   ${unknown.length} вакансий без ownerType → установлено "${DEFAULT_TYPE}":`);
    unknown.slice(0, 20).forEach((u) =>
      console.log(`     [${u.id}] "${u.title}" owner=${u.ownerId}`),
    );
    if (unknown.length > 20) console.log(`     ... и ещё ${unknown.length - 20}`);
  }

  const written = await commitPatches(patches);
  console.log(`  ✓ jobs: обновлено ${written} из ${patches.length} нуждавшихся`);
  return written;
}

// ─── Шаг 2: applications ─────────────────────────────────────────────────────

async function migrateApplications() {
  console.log('\n━━━ 2/4  applications → vacancyOwnerType ━━━━━━━━━━━━━━━━━━');
  const docs = await fetchAll('applications');
  console.log(`  Найдено ${docs.length} откликов`);

  const patches   = [];
  const notFound  = []; // нет вакансии в кэше

  for (const doc of docs) {
    const m = doc.data();
    const type = s(m.type).toLowerCase();
    if (type !== 'apply') continue;

    // Уже проставлен корректно
    if (VALID_TYPES.has(s(m.vacancyOwnerType))) continue;

    const jobId = s(m.vacancyId) || s(m.jobId);
    const ownerType = await resolveJobOwnerType(jobId);
    if (ownerType === null) {
      notFound.push({ id: doc.id, jobId });
      // Всё равно ставим default, чтобы не было пустых полей
      patches.push({
        ref: doc.reference,
        data: {
          vacancyOwnerType: DEFAULT_TYPE,
          _migratedVacancyOwnerType: true,
          _migratedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
      });
      continue;
    }

    patches.push({
      ref: doc.reference,
      data: {
        vacancyOwnerType: ownerType,
        _migratedVacancyOwnerType: true,
        _migratedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
    });
  }

  if (notFound.length > 0) {
    console.log(`\n  ⚠️   ${notFound.length} откликов: вакансия не найдена (проставлен "${DEFAULT_TYPE}"):`);
    notFound.slice(0, 10).forEach((u) =>
      console.log(`     [${u.id}] jobId=${u.jobId}`),
    );
    if (notFound.length > 10) console.log(`     ... и ещё ${notFound.length - 10}`);
  }

  const written = await commitPatches(patches);
  console.log(`  ✓ applications: обновлено ${written} из ${patches.length} нуждавшихся`);
  return written;
}

// ─── Шаг 3: jobOffers ────────────────────────────────────────────────────────

async function migrateJobOffers() {
  console.log('\n━━━ 3/4  jobOffers → vacancyOwnerType + employerType ━━━━━━');
  const docs = await fetchAll('jobOffers');
  console.log(`  Найдено ${docs.length} предложений`);

  const patches  = [];
  const notFound = [];

  for (const doc of docs) {
    const m = doc.data();
    const type = s(m.type).toLowerCase();
    if (type !== 'offer') continue;

    const needsVacancyType = !VALID_TYPES.has(s(m.vacancyOwnerType));
    const needsEmployerType = !VALID_TYPES.has(s(m.employerType));
    if (!needsVacancyType && !needsEmployerType) continue;

    const jobId = s(m.vacancyId) || s(m.jobId);
    const ownerType = await resolveJobOwnerType(jobId);
    if (ownerType === null) {
      notFound.push({ id: doc.id, jobId });
    }
    const resolved = ownerType ?? DEFAULT_TYPE;

    const patch = {
      _migratedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    if (needsVacancyType) {
      patch.vacancyOwnerType = resolved;
      patch._migratedVacancyOwnerType = true;
    }
    if (needsEmployerType) {
      // employerType = режим профиля работодателя при отправке.
      // Для исторических данных: предполагаем совпадает с типом вакансии.
      patch.employerType = resolved;
      patch._migratedEmployerType = true;
    }

    patches.push({ ref: doc.reference, data: patch });
  }

  if (notFound.length > 0) {
    console.log(`\n  ⚠️   ${notFound.length} предложений: вакансия не найдена:`);
    notFound.slice(0, 10).forEach((u) =>
      console.log(`     [${u.id}] jobId=${u.jobId}`),
    );
  }

  const written = await commitPatches(patches);
  console.log(`  ✓ jobOffers: обновлено ${written} из ${patches.length} нуждавшихся`);
  return written;
}

// ─── Шаг 4: responses (legacy) ───────────────────────────────────────────────

async function migrateLegacyResponses() {
  console.log('\n━━━ 4/4  responses (legacy) → ownerType fields ━━━━━━━━━━━');
  const docs = await fetchAll('responses');
  console.log(`  Найдено ${docs.length} legacy-ответов`);

  const patches = [];

  for (const doc of docs) {
    const m = doc.data();
    const type = s(m.type).toLowerCase();

    if (type === 'apply') {
      if (VALID_TYPES.has(s(m.vacancyOwnerType))) continue;
      const jobId = s(m.vacancyId) || s(m.jobId);
      const ownerType = await resolveJobOwnerType(jobId) ?? DEFAULT_TYPE;
      patches.push({
        ref: doc.reference,
        data: {
          vacancyOwnerType: ownerType,
          _migratedVacancyOwnerType: true,
          _migratedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
      });
    } else if (type === 'offer') {
      const needsVT = !VALID_TYPES.has(s(m.vacancyOwnerType));
      const needsET = !VALID_TYPES.has(s(m.employerType));
      if (!needsVT && !needsET) continue;
      const jobId = s(m.vacancyId) || s(m.jobId);
      const ownerType = await resolveJobOwnerType(jobId) ?? DEFAULT_TYPE;
      const patch = { _migratedAt: admin.firestore.FieldValue.serverTimestamp() };
      if (needsVT) { patch.vacancyOwnerType = ownerType; patch._migratedVacancyOwnerType = true; }
      if (needsET) { patch.employerType = ownerType;      patch._migratedEmployerType = true;      }
      patches.push({ ref: doc.reference, data: patch });
    }
  }

  const written = await commitPatches(patches);
  console.log(`  ✓ responses: обновлено ${written} из ${patches.length} нуждавшихся`);
  return written;
}

// ─── Main ─────────────────────────────────────────────────────────────────────

async function main() {
  const line = '═'.repeat(54);
  console.log(`\n╔${line}╗`);
  console.log(`║  Worka — Миграция ownerType / vacancyOwnerType         ║`);
  if (DRY_RUN) {
    console.log(`║  ⚠️  DRY-RUN: реальных записей НЕ будет              ║`);
  }
  console.log(`╚${line}╝\n`);

  const stats = {
    jobs:         await migrateJobs(),
    applications: await migrateApplications(),
    jobOffers:    await migrateJobOffers(),
    responses:    await migrateLegacyResponses(),
  };

  const grand = Object.values(stats).reduce((a, b) => a + b, 0);

  console.log(`\n╔${line}╗`);
  console.log(`║  ИТОГ МИГРАЦИИ                                         ║`);
  console.log(`║  jobs обновлено         : ${String(stats.jobs).padStart(6)}                     ║`);
  console.log(`║  applications обновлено : ${String(stats.applications).padStart(6)}                     ║`);
  console.log(`║  jobOffers обновлено    : ${String(stats.jobOffers).padStart(6)}                     ║`);
  console.log(`║  responses обновлено    : ${String(stats.responses).padStart(6)}                     ║`);
  console.log(`║${'─'.repeat(54)}║`);
  console.log(`║  ВСЕГО изменено         : ${String(grand).padStart(6)}                     ║`);
  if (DRY_RUN) console.log(`║  ⚠️  DRY-RUN — в Firestore ничего не записано        ║`);
  console.log(`╚${line}╝\n`);

  process.exit(0);
}

main().catch((err) => {
  console.error('\n❌  Критическая ошибка:', err.message || err);
  process.exit(1);
});
