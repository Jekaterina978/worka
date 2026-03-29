'use strict';

/**
 * cleanup_database.js
 *
 * Удаляет из Firestore:
 *   1) CVs с отсутствующим/пустым/guest/anonymous ownerId
 *   2) Вакансии (jobs) с теми же условиями
 *   3) Отклики (applications) с отсутствующим/пустым/guest applicantId
 *   4) Предложения работы (jobOffers) с отсутствующим employerId/candidateId/cvId/vacancyId
 *   5) Тестовые записи во всех коллекциях (title содержит "test"/"копия"/"demo")
 *
 * Запуск:
 *   node cleanup_database.js <путь/к/serviceAccountKey.json> [--dry-run]
 *
 *   --dry-run  показывает что будет удалено, но ничего не удаляет
 */

const admin = require('firebase-admin');
const path  = require('path');

// ─── CLI args ────────────────────────────────────────────────────────────────

const args    = process.argv.slice(2);
const DRY_RUN = args.includes('--dry-run');
const allowProd = args.includes('--allow-prod');
const saArg   = args.find((a) => !a.startsWith('--'));
const saPath  = saArg
  ? path.resolve(saArg)
  : process.env.GOOGLE_APPLICATION_CREDENTIALS;

if (!saPath) {
  console.error(
    'ERROR: укажи путь к serviceAccountKey.json как первый аргумент,\n' +
    '       или задай переменную GOOGLE_APPLICATION_CREDENTIALS.\n\n' +
    '       Пример: node cleanup_database.js ./serviceAccountKey.json',
  );
  process.exit(1);
}

// ─── Firebase init ───────────────────────────────────────────────────────────

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

// ─── Constants ───────────────────────────────────────────────────────────────

const BATCH_SIZE = 400; // max 500 per Firestore batch, keep margin

// Ключевые слова для удаления тестовых записей (проверяются в поле title).
// Для коллекций jobOffers/applications используется поле vacancyTitle / jobTitle.
const TEST_KEYWORDS = ['test', 'копия', 'demo'];

// Коллекции для поиска тестовых записей и поле-заголовок для каждой.
const TEST_TITLE_COLLECTIONS = [
  { name: 'cvs',          titleField: 'title'      },
  { name: 'jobs',         titleField: 'title'      },
  { name: 'applications', titleField: 'vacancyTitle' },
  { name: 'jobOffers',    titleField: 'vacancyTitle' },
  { name: 'responses',    titleField: 'title'      },
];

// ─── Helpers ─────────────────────────────────────────────────────────────────

/** true если значение отсутствует, пустое или является плейсхолдером гостя */
function isGuestId(value) {
  if (value === null || value === undefined) return true;
  const s = String(value).trim().toLowerCase();
  return s === '' || s === 'null' || s === 'undefined'
      || s === 'guest' || s === 'anonymous';
}

/** true если title содержит одно из тестовых слов (case-insensitive) */
function isTestTitle(value) {
  if (!value) return false;
  const s = String(value).trim().toLowerCase();
  return TEST_KEYWORDS.some((kw) => s.includes(kw));
}

/** Разбивает массив ссылок на чанки и удаляет пакетами */
async function batchDeleteRefs(refs, label) {
  if (refs.length === 0) return 0;
  let deleted = 0;
  for (let i = 0; i < refs.length; i += BATCH_SIZE) {
    const chunk = refs.slice(i, i + BATCH_SIZE);
    if (!DRY_RUN) {
      const batch = db.batch();
      chunk.forEach((ref) => batch.delete(ref));
      await batch.commit();
    }
    deleted += chunk.length;
    console.log(`    ${DRY_RUN ? '[DRY-RUN] Найдено' : 'Удалено'} ${deleted} из ${refs.length} (${label})`);
  }
  return deleted;
}

/**
 * Полное сканирование коллекции с пагинацией.
 * predicate(data) → true если документ нужно удалить.
 * Возвращает количество удалённых документов.
 */
async function scanAndDelete(collectionName, label, predicate) {
  console.log(`\n  Сканирую /${collectionName} [${label}] …`);

  let totalDeleted = 0;
  let scanned      = 0;
  let cursor       = null;
  let page         = 0;

  while (true) {
    page++;
    let query = db.collection(collectionName).orderBy(admin.firestore.FieldPath.documentId()).limit(BATCH_SIZE);
    if (cursor) query = query.startAfter(cursor);

    const snap = await query.get();
    if (snap.empty) break;

    scanned += snap.docs.length;
    cursor   = snap.docs[snap.docs.length - 1];

    const toDelete = snap.docs
      .filter((doc) => predicate(doc.data(), doc.id))
      .map((doc) => doc.ref);

    if (toDelete.length > 0) {
      const n = await batchDeleteRefs(toDelete, `${collectionName} стр.${page}`);
      totalDeleted += n;
    }

    process.stdout.write(`\r    Просмотрено: ${scanned} | Удалено: ${totalDeleted}   `);

    if (snap.docs.length < BATCH_SIZE) break; // последняя страница
  }

  process.stdout.write('\n');
  console.log(`  ✓ /${collectionName} [${label}]: ${totalDeleted} удалено (просмотрено ${scanned})`);
  return totalDeleted;
}

// ─── Задачи очистки ───────────────────────────────────────────────────────────

/** 1) CVs с пустым / guest / anonymous ownerId */
async function cleanCvs() {
  return scanAndDelete(
    'cvs',
    'гостевой ownerId',
    (data) => isGuestId(data.ownerId),
  );
}

/** 2) Вакансии с пустым / guest / anonymous ownerId */
async function cleanJobs() {
  return scanAndDelete(
    'jobs',
    'гостевой ownerId',
    (data) => isGuestId(data.ownerId),
  );
}

/** 3) Отклики с пустым / guest applicantId */
async function cleanApplications() {
  return scanAndDelete(
    'applications',
    'гостевой applicantId',
    (data) => isGuestId(data.applicantId),
  );
}

/**
 * 4) jobOffers где хотя бы одно из ключевых полей отсутствует:
 *    employerId, candidateId, cvId, vacancyId
 */
async function cleanJobOffers() {
  return scanAndDelete(
    'jobOffers',
    'неполные поля',
    (data) =>
      isGuestId(data.employerId)  ||
      isGuestId(data.candidateId) ||
      isGuestId(data.cvId)        ||
      isGuestId(data.vacancyId),
  );
}

/**
 * 5) Тестовые записи во всех коллекциях.
 *    Каждая коллекция имеет своё поле-заголовок.
 */
async function cleanTestData() {
  let total = 0;
  for (const { name, titleField } of TEST_TITLE_COLLECTIONS) {
    const n = await scanAndDelete(
      name,
      `тестовый ${titleField}`,
      (data) => isTestTitle(data[titleField]),
    );
    total += n;
  }
  return total;
}

// ─── Main ─────────────────────────────────────────────────────────────────────

async function main() {
  const line = '═'.repeat(50);
  console.log(`\n╔${line}╗`);
  console.log(`║  Worka — Очистка базы Firestore${' '.repeat(18)}║`);
  if (DRY_RUN) {
    console.log(`║  ⚠️   РЕЖИМ ПРЕДПРОСМОТРА — ничего не удаляется  ║`);
  }
  console.log(`╚${line}╝\n`);

  const stats = {
    cvs:          0,
    jobs:         0,
    applications: 0,
    jobOffers:    0,
    testData:     0,
  };

  // ── 1. CVs ──────────────────────────────────────────────────────────────────
  console.log('━━━ 1/5  CVs (гостевой ownerId) ━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  stats.cvs = await cleanCvs();

  // ── 2. Вакансии ─────────────────────────────────────────────────────────────
  console.log('\n━━━ 2/5  Вакансии (гостевой ownerId) ━━━━━━━━━━━━━━━━━━━━━');
  stats.jobs = await cleanJobs();

  // ── 3. Отклики ──────────────────────────────────────────────────────────────
  console.log('\n━━━ 3/5  Отклики — applications (гостевой applicantId) ━━━━');
  stats.applications = await cleanApplications();

  // ── 4. Предложения работы ───────────────────────────────────────────────────
  console.log('\n━━━ 4/5  Предложения — jobOffers (неполные поля) ━━━━━━━━━━');
  stats.jobOffers = await cleanJobOffers();

  // ── 5. Тестовые записи ──────────────────────────────────────────────────────
  console.log('\n━━━ 5/5  Тестовые записи (title: test / копия / demo) ━━━━━');
  stats.testData = await cleanTestData();

  // ── Итог ────────────────────────────────────────────────────────────────────
  const grand = Object.values(stats).reduce((a, b) => a + b, 0);

  console.log(`\n╔${line}╗`);
  console.log(`║  ИТОГ${' '.repeat(44)}║`);
  console.log(`║  CVs удалено          : ${String(stats.cvs).padStart(6)}${' '.repeat(18)}║`);
  console.log(`║  Вакансии удалено     : ${String(stats.jobs).padStart(6)}${' '.repeat(18)}║`);
  console.log(`║  Отклики удалено      : ${String(stats.applications).padStart(6)}${' '.repeat(18)}║`);
  console.log(`║  Предложения удалено  : ${String(stats.jobOffers).padStart(6)}${' '.repeat(18)}║`);
  console.log(`║  Тестовые удалено     : ${String(stats.testData).padStart(6)}${' '.repeat(18)}║`);
  console.log(`║${'─'.repeat(50)}║`);
  console.log(`║  ВСЕГО                : ${String(grand).padStart(6)}${' '.repeat(18)}║`);
  if (DRY_RUN) {
    console.log(`║  ⚠️   DRY-RUN: реальных удалений не было      ║`);
  }
  console.log(`╚${line}╝\n`);

  process.exit(0);
}

main().catch((err) => {
  console.error('\n❌  Критическая ошибка:', err.message || err);
  process.exit(1);
});
