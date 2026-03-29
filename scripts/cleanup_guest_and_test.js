'use strict';

/**
 * cleanup_guest_and_test.js
 *
 * Удаляет из Firestore:
 *   A) Тестовые коллекции целиком: cvs_test, jobs_test, responses_test, app_test
 *   B) Гостевые/анонимные записи в: cvs, jobs, applications, jobOffers, responses
 *   C) Черновики в подколлекциях users/{uid}/cvs, users/{uid}/vacancies
 *
 * РЕЖИМЫ:
 *   --dry-run   только считает, в Firestore ничего не пишет
 *   --run       реальное удаление (требует явного флага)
 *
 * ДОПОЛНИТЕЛЬНЫЕ ФЛАГИ:
 *   --delete-soft-deleted   удалять CV где isDeleted==true (без флага — только считает)
 *   --skip-subcollections   пропустить сканирование users/{uid}/cvs и vacancies
 *
 * ЗАПУСК:
 *   node cleanup_guest_and_test.js --dry-run
 *   node cleanup_guest_and_test.js --run
 *   node cleanup_guest_and_test.js --run --delete-soft-deleted
 */

const admin = require('firebase-admin');
const path  = require('path');

// ─── CLI ─────────────────────────────────────────────────────────────────────

const args = process.argv.slice(2);

const DRY_RUN          = args.includes('--run') ? false : true; // default to dry-run
const DELETE_SOFT_DEL  = args.includes('--delete-soft-deleted');
const SKIP_SUBCOLS     = args.includes('--skip-subcollections');

const saArg  = args.find((a) => !a.startsWith('--'));
const saPath = saArg
  ? path.resolve(saArg)
  : process.env.GOOGLE_APPLICATION_CREDENTIALS;

if (!saPath) {
  console.error(
    '\n  ERROR: укажи путь к serviceAccountKey.json:\n' +
    '    node cleanup_guest_and_test.js ./key.json --dry-run\n',
  );
  process.exit(1);
}

// ─── Init ────────────────────────────────────────────────────────────────────

const serviceAccount = require(saPath);
admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });

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
  runMode: DRY_RUN ? 'DRY-RUN' : 'WRITE',
  allowProd,
  estimatedOps: 'unknown',
});

const db = admin.firestore();

// ─── Константы ───────────────────────────────────────────────────────────────

const BATCH_SIZE = 450; // Firestore max=500, держим запас

/**
 * Значения считающиеся "гостевыми".
 * Проверка case-insensitive с trim().
 */
const GUEST_VALUES = new Set([
  '', 'null', 'undefined', 'guest', 'anonymous',
  'none', 'unknown', 'test', 'dev',
]);

// ─── Итоги (заполняется в процессе работы) ───────────────────────────────────

const REPORT = {
  // { [label]: { scanned, flagged, deleted } }
};

function initSection(label) {
  REPORT[label] = { scanned: 0, flagged: 0, deleted: 0 };
}

function addToSection(label, { scanned = 0, flagged = 0, deleted = 0 }) {
  REPORT[label].scanned  += scanned;
  REPORT[label].flagged  += flagged;
  REPORT[label].deleted  += deleted;
}

// ─── Утилиты ─────────────────────────────────────────────────────────────────

/** Нормализует значение поля к строке. */
function s(v) {
  return (v == null ? '' : String(v)).trim();
}

/** true если значение является гостевым идентификатором. */
function isGuest(value) {
  if (value === null || value === undefined) return true;
  return GUEST_VALUES.has(s(value).toLowerCase());
}

/**
 * Читает все документы коллекции постранично.
 * Генератор — не загружает всё в память сразу.
 */
async function* paginate(collectionRef) {
  let cursor = null;
  while (true) {
    let q = collectionRef
      .orderBy(admin.firestore.FieldPath.documentId())
      .limit(BATCH_SIZE);
    if (cursor) q = q.startAfter(cursor);

    const snap = await q.get();
    if (snap.empty) break;

    yield snap.docs;

    cursor = snap.docs[snap.docs.length - 1];
    if (snap.docs.length < BATCH_SIZE) break;
  }
}

/** Удаляет (или симулирует удаление) массива DocumentReference. */
async function deleteRefs(refs, label, pageNum) {
  if (refs.length === 0) return 0;
  if (DRY_RUN) {
    process.stdout.write(
      `\r    [dry] стр.${pageNum} помечено к удалению: ${refs.length}   `,
    );
    return 0;
  }
  // Разбиваем на чанки <=450
  let deleted = 0;
  for (let i = 0; i < refs.length; i += BATCH_SIZE) {
    const chunk = refs.slice(i, i + BATCH_SIZE);
    const batch = db.batch();
    chunk.forEach((ref) => batch.delete(ref));
    await batch.commit();
    deleted += chunk.length;
  }
  process.stdout.write(
    `\r    стр.${pageNum}: удалено ${deleted}   `,
  );
  return deleted;
}

// ─── A) ТЕСТОВЫЕ КОЛЛЕКЦИИ ───────────────────────────────────────────────────

/**
 * Удаляет ВСЕ документы в тестовой коллекции.
 * Firestore не поддерживает "удалить коллекцию" напрямую —
 * нужно удалять документы по одному/батчами.
 */
async function deleteEntireCollection(colName) {
  const label = `[TEST] ${colName}`;
  initSection(label);
  console.log(`\n  Удаляю тестовую коллекцию /${colName} …`);

  const colRef = db.collection(colName);
  let page = 0;
  let totalScanned = 0;
  let totalDeleted = 0;

  for await (const docs of paginate(colRef)) {
    page++;
    totalScanned += docs.length;
    const refs = docs.map((d) => d.ref);
    const deleted = await deleteRefs(refs, label, page);
    totalDeleted += deleted;
    if (DRY_RUN) totalDeleted += refs.length; // в dry-run считаем "будет удалено"
  }

  process.stdout.write('\n');
  console.log(
    `  ✓ /${colName}: ${DRY_RUN ? 'будет удалено' : 'удалено'} ${totalDeleted} из ${totalScanned} документов`,
  );
  addToSection(label, { scanned: totalScanned, flagged: totalDeleted, deleted: totalDeleted });
}

// ─── B1) cvs — гостевые резюме ───────────────────────────────────────────────

async function cleanCvs() {
  const label = 'cvs (guest)';
  const labelSoft = 'cvs (isDeleted)';
  initSection(label);
  initSection(labelSoft);
  console.log('\n  Сканирую /cvs …');

  const colRef = db.collection('cvs');
  let page = 0;
  let scanned = 0;

  for await (const docs of paginate(colRef)) {
    page++;
    scanned += docs.length;
    process.stdout.write(`\r    стр.${page} просмотрено: ${scanned}   `);

    const guestRefs  = [];
    const deletedRefs = [];

    for (const doc of docs) {
      const m = doc.data();
      const ownerId = s(m.ownerId);
      if (isGuest(ownerId)) {
        guestRefs.push(doc.ref);
        continue;
      }
      // Дополнительно: isDeleted == true
      if (m.isDeleted === true) {
        deletedRefs.push(doc.ref);
      }
    }

    addToSection(label, { scanned: docs.length, flagged: guestRefs.length });
    addToSection(labelSoft, { flagged: deletedRefs.length });

    const del1 = await deleteRefs(guestRefs, label, page);
    addToSection(label, { deleted: del1 });

    if (DELETE_SOFT_DEL && deletedRefs.length > 0) {
      const del2 = await deleteRefs(deletedRefs, labelSoft, page);
      addToSection(labelSoft, { deleted: del2 });
    }
  }

  process.stdout.write('\n');
  const r1 = REPORT[label];
  const r2 = REPORT[labelSoft];
  console.log(
    `  ✓ /cvs гостевые: найдено ${r1.flagged}, ${DRY_RUN ? 'будет удалено' : 'удалено'} ${DRY_RUN ? r1.flagged : r1.deleted}`,
  );
  console.log(
    `  ✓ /cvs isDeleted: найдено ${r2.flagged}${
      DELETE_SOFT_DEL
        ? `, ${DRY_RUN ? 'будет удалено' : 'удалено'} ${DRY_RUN ? r2.flagged : r2.deleted}`
        : ' (пропущено, используй --delete-soft-deleted)'
    }`,
  );
}

// ─── B2) jobs — гостевые вакансии ────────────────────────────────────────────

async function cleanJobs() {
  const label = 'jobs (guest)';
  initSection(label);
  console.log('\n  Сканирую /jobs …');

  const colRef = db.collection('jobs');
  let page = 0;
  let scanned = 0;

  for await (const docs of paginate(colRef)) {
    page++;
    scanned += docs.length;
    process.stdout.write(`\r    стр.${page} просмотрено: ${scanned}   `);

    const toDelete = [];

    for (const doc of docs) {
      const m = doc.data();

      // Проверяем все варианты ID владельца
      const ownerId = s(m.ownerId);
      const ownerKey = s(m.ownerKey);
      const ownerUid = s(m.ownerUid);
      const vacancyOwnerId = s(m.vacancyOwnerId);
      const legacyOwnerId = s(m.employerOwnerId);

      // Основной ownerId — гостевой
      if (isGuest(ownerId)) {
        // Проверяем: может есть данные в legacy полях?
        const hasLegacyOwner =
          (!isGuest(ownerKey) && ownerKey) ||
          (!isGuest(ownerUid) && ownerUid) ||
          (!isGuest(vacancyOwnerId) && vacancyOwnerId) ||
          (!isGuest(legacyOwnerId) && legacyOwnerId);

        if (!hasLegacyOwner) {
          // Нет ни одного нормального owner ID → удалить
          toDelete.push(doc.ref);
        }
        // Если есть legacy owner — пропускаем (не удаляем, данные валидные)
      }
    }

    addToSection(label, { scanned: docs.length, flagged: toDelete.length });
    const del = await deleteRefs(toDelete, label, page);
    addToSection(label, { deleted: del });
  }

  process.stdout.write('\n');
  const r = REPORT[label];
  console.log(
    `  ✓ /jobs гостевые: найдено ${r.flagged}, ${DRY_RUN ? 'будет удалено' : 'удалено'} ${DRY_RUN ? r.flagged : r.deleted}`,
  );
}

// ─── B3) applications — гостевые отклики ─────────────────────────────────────

/**
 * Правило удаления:
 *   - type != "apply"  → мусор
 *   - applicantId пустой/гостевой
 *   - vacancyId (или jobId) пустой/гостевой
 *   - vacancyOwnerId (или employerOwnerId) пустой/гостевой
 *   - cvId (или candidateCvId) пустой/гостевой
 */
function isGuestApplication(m) {
  const type = s(m.type).toLowerCase();
  if (type && type !== 'apply') return { delete: true, reason: `type="${type}"` };

  const applicantId = s(m.applicantId) || s(m.candidateOwnerId);
  if (isGuest(applicantId)) return { delete: true, reason: 'applicantId пустой/guest' };

  const vacancyId = s(m.vacancyId) || s(m.jobId);
  if (isGuest(vacancyId)) return { delete: true, reason: 'vacancyId пустой/guest' };

  const ownerId = s(m.vacancyOwnerId) || s(m.employerOwnerId);
  if (isGuest(ownerId)) return { delete: true, reason: 'vacancyOwnerId пустой/guest' };

  const cvId = s(m.cvId) || s(m.candidateCvId);
  if (isGuest(cvId)) return { delete: true, reason: 'cvId пустой/guest' };

  return { delete: false };
}

async function cleanApplications() {
  const label = 'applications (guest)';
  initSection(label);
  console.log('\n  Сканирую /applications …');

  const colRef = db.collection('applications');
  let page = 0;
  let scanned = 0;
  const reasonCounts = {};

  for await (const docs of paginate(colRef)) {
    page++;
    scanned += docs.length;
    process.stdout.write(`\r    стр.${page} просмотрено: ${scanned}   `);

    const toDelete = [];

    for (const doc of docs) {
      const result = isGuestApplication(doc.data());
      if (result.delete) {
        toDelete.push(doc.ref);
        reasonCounts[result.reason] = (reasonCounts[result.reason] || 0) + 1;
      }
    }

    addToSection(label, { scanned: docs.length, flagged: toDelete.length });
    const del = await deleteRefs(toDelete, label, page);
    addToSection(label, { deleted: del });
  }

  process.stdout.write('\n');
  const r = REPORT[label];
  console.log(
    `  ✓ /applications гостевые: найдено ${r.flagged}, ${DRY_RUN ? 'будет удалено' : 'удалено'} ${DRY_RUN ? r.flagged : r.deleted}`,
  );
  if (Object.keys(reasonCounts).length > 0) {
    console.log('    Причины:');
    Object.entries(reasonCounts)
      .sort((a, b) => b[1] - a[1])
      .forEach(([reason, cnt]) => console.log(`      ${cnt}x — ${reason}`));
  }
}

// ─── B4) jobOffers — гостевые предложения ────────────────────────────────────

/**
 * Правило удаления:
 *   - type != "offer"  → мусор
 *   - employerId (или employerOwnerId) пустой/гостевой
 *   - candidateId (или candidateOwnerId) пустой/гостевой
 *   - vacancyId (или jobId) пустой/гостевой
 *   - cvId (или candidateCvId) пустой/гостевой
 */
function isGuestOffer(m) {
  const type = s(m.type).toLowerCase();
  if (type && type !== 'offer') return { delete: true, reason: `type="${type}"` };

  const employerId = s(m.employerId) || s(m.employerOwnerId);
  if (isGuest(employerId)) return { delete: true, reason: 'employerId пустой/guest' };

  const candidateId = s(m.candidateId) || s(m.candidateOwnerId);
  if (isGuest(candidateId)) return { delete: true, reason: 'candidateId пустой/guest' };

  const vacancyId = s(m.vacancyId) || s(m.jobId);
  if (isGuest(vacancyId)) return { delete: true, reason: 'vacancyId пустой/guest' };

  const cvId = s(m.cvId) || s(m.candidateCvId);
  if (isGuest(cvId)) return { delete: true, reason: 'cvId пустой/guest' };

  return { delete: false };
}

async function cleanJobOffers() {
  const label = 'jobOffers (guest)';
  initSection(label);
  console.log('\n  Сканирую /jobOffers …');

  const colRef = db.collection('jobOffers');
  let page = 0;
  let scanned = 0;
  const reasonCounts = {};

  for await (const docs of paginate(colRef)) {
    page++;
    scanned += docs.length;
    process.stdout.write(`\r    стр.${page} просмотрено: ${scanned}   `);

    const toDelete = [];

    for (const doc of docs) {
      const result = isGuestOffer(doc.data());
      if (result.delete) {
        toDelete.push(doc.ref);
        reasonCounts[result.reason] = (reasonCounts[result.reason] || 0) + 1;
      }
    }

    addToSection(label, { scanned: docs.length, flagged: toDelete.length });
    const del = await deleteRefs(toDelete, label, page);
    addToSection(label, { deleted: del });
  }

  process.stdout.write('\n');
  const r = REPORT[label];
  console.log(
    `  ✓ /jobOffers гостевые: найдено ${r.flagged}, ${DRY_RUN ? 'будет удалено' : 'удалено'} ${DRY_RUN ? r.flagged : r.deleted}`,
  );
  if (Object.keys(reasonCounts).length > 0) {
    console.log('    Причины:');
    Object.entries(reasonCounts)
      .sort((a, b) => b[1] - a[1])
      .forEach(([reason, cnt]) => console.log(`      ${cnt}x — ${reason}`));
  }
}

// ─── C) responses (legacy) ───────────────────────────────────────────────────

/**
 * Удаляем responses где:
 *   1) type == "apply" → проверяем как application
 *   2) type == "offer" → проверяем как offer
 *   3) Нет ни createdAt ни updatedAt → явный тестовый мусор
 *   4) type отсутствует → неопределённый мусор
 */
function isGuestResponse(m) {
  const type = s(m.type).toLowerCase();

  if (!type) {
    // Нет type — неизвестный документ
    return { delete: true, reason: 'type отсутствует' };
  }

  if (!m.createdAt && !m.updatedAt) {
    return { delete: true, reason: 'нет createdAt/updatedAt (тестовый)' };
  }

  if (type === 'apply') {
    const result = isGuestApplication(m);
    return result;
  }

  if (type === 'offer') {
    const result = isGuestOffer(m);
    return result;
  }

  // Неизвестный type
  return { delete: true, reason: `неизвестный type="${type}"` };
}

async function cleanResponses() {
  const label = 'responses (guest/invalid)';
  initSection(label);
  console.log('\n  Сканирую /responses (legacy) …');

  const colRef = db.collection('responses');
  let page = 0;
  let scanned = 0;
  const reasonCounts = {};

  for await (const docs of paginate(colRef)) {
    page++;
    scanned += docs.length;
    process.stdout.write(`\r    стр.${page} просмотрено: ${scanned}   `);

    const toDelete = [];

    for (const doc of docs) {
      const result = isGuestResponse(doc.data());
      if (result.delete) {
        toDelete.push(doc.ref);
        reasonCounts[result.reason] = (reasonCounts[result.reason] || 0) + 1;
      }
    }

    addToSection(label, { scanned: docs.length, flagged: toDelete.length });
    const del = await deleteRefs(toDelete, label, page);
    addToSection(label, { deleted: del });
  }

  process.stdout.write('\n');
  const r = REPORT[label];
  console.log(
    `  ✓ /responses гостевые: найдено ${r.flagged}, ${DRY_RUN ? 'будет удалено' : 'удалено'} ${DRY_RUN ? r.flagged : r.deleted}`,
  );
  if (Object.keys(reasonCounts).length > 0) {
    console.log('    Причины:');
    Object.entries(reasonCounts)
      .sort((a, b) => b[1] - a[1])
      .forEach(([reason, cnt]) => console.log(`      ${cnt}x — ${reason}`));
  }
}

// ─── D) Подколлекции users/{uid}/cvs и users/{uid}/vacancies ─────────────────

/**
 * Стратегия:
 *   1) Листаем всех users.
 *   2) Для каждого user — читаем users/{uid}/cvs и users/{uid}/vacancies.
 *   3) Удаляем документы где ownerId пустой/гостевой ИЛИ ownerId != uid.
 */
async function cleanUserSubcollections() {
  if (SKIP_SUBCOLS) {
    console.log('\n  [пропуск] подколлекции users/{uid}/cvs и vacancies (--skip-subcollections)');
    return;
  }

  const labelCvs  = 'users/{uid}/cvs (guest)';
  const labelVacs = 'users/{uid}/vacancies (guest)';
  initSection(labelCvs);
  initSection(labelVacs);
  console.log('\n  Сканирую подколлекции users/{uid}/cvs и /vacancies …');

  const usersRef = db.collection('users');
  let userPage = 0;
  let userCount = 0;

  for await (const userDocs of paginate(usersRef)) {
    userPage++;
    userCount += userDocs.length;
    process.stdout.write(`\r    users стр.${userPage}: ${userCount} пользователей   `);

    for (const userDoc of userDocs) {
      const uid = userDoc.id;

      // users/{uid}/cvs
      const cvsRef = db.collection('users').doc(uid).collection('cvs');
      for await (const cvDocs of paginate(cvsRef)) {
        const toDelete = [];
        for (const doc of cvDocs) {
          const m = doc.data();
          const ownerId = s(m.ownerId);
          if (isGuest(ownerId) || (ownerId && ownerId !== uid)) {
            toDelete.push(doc.ref);
          }
        }
        addToSection(labelCvs, { scanned: cvDocs.length, flagged: toDelete.length });
        const del = await deleteRefs(toDelete, labelCvs, userPage);
        addToSection(labelCvs, { deleted: del });
      }

      // users/{uid}/vacancies
      const vacsRef = db.collection('users').doc(uid).collection('vacancies');
      for await (const vacDocs of paginate(vacsRef)) {
        const toDelete = [];
        for (const doc of vacDocs) {
          const m = doc.data();
          const ownerId = s(m.ownerId);
          if (isGuest(ownerId) || (ownerId && ownerId !== uid)) {
            toDelete.push(doc.ref);
          }
        }
        addToSection(labelVacs, { scanned: vacDocs.length, flagged: toDelete.length });
        const del = await deleteRefs(toDelete, labelVacs, userPage);
        addToSection(labelVacs, { deleted: del });
      }
    }
  }

  process.stdout.write('\n');
  const r1 = REPORT[labelCvs];
  const r2 = REPORT[labelVacs];
  console.log(
    `  ✓ users/{uid}/cvs: найдено ${r1.flagged} из ${r1.scanned}, ${DRY_RUN ? 'будет удалено' : 'удалено'} ${DRY_RUN ? r1.flagged : r1.deleted}`,
  );
  console.log(
    `  ✓ users/{uid}/vacancies: найдено ${r2.flagged} из ${r2.scanned}, ${DRY_RUN ? 'будет удалено' : 'удалено'} ${DRY_RUN ? r2.flagged : r2.deleted}`,
  );
}

// ─── ИТОГОВАЯ ТАБЛИЦА ────────────────────────────────────────────────────────

function printReport() {
  const PAD_LABEL   = 36;
  const PAD_NUM     = 10;
  const line = '─'.repeat(PAD_LABEL + PAD_NUM * 3 + 6);
  const dline = '═'.repeat(PAD_LABEL + PAD_NUM * 3 + 6);

  console.log(`\n╔${dline}╗`);
  const header = DRY_RUN ? 'ПРЕДПРОСМОТР (DRY-RUN) — ничего не удалено' : 'ИТОГ УДАЛЕНИЯ';
  console.log(`║  ${header}${' '.repeat(dline.length - header.length - 1)}║`);
  console.log(`╠${dline}╣`);

  const colH = (s, w) => s.padEnd(w);
  console.log(
    `║  ${colH('Коллекция', PAD_LABEL)}` +
    `${colH('Просмотрено', PAD_NUM)}` +
    `${colH('Найдено', PAD_NUM)}` +
    `${colH(DRY_RUN ? 'Будет удалено' : 'Удалено', PAD_NUM)}  ║`,
  );
  console.log(`╠${line}╣`);

  let grandScanned = 0;
  let grandFlagged = 0;
  let grandDeleted = 0;

  for (const [label, r] of Object.entries(REPORT)) {
    console.log(
      `║  ${colH(label, PAD_LABEL)}` +
      `${String(r.scanned).padStart(PAD_NUM)}` +
      `${String(r.flagged).padStart(PAD_NUM)}` +
      `${String(DRY_RUN ? r.flagged : r.deleted).padStart(PAD_NUM)}  ║`,
    );
    grandScanned += r.scanned;
    grandFlagged += r.flagged;
    grandDeleted += r.deleted;
  }

  const effectiveDeleted = DRY_RUN ? grandFlagged : grandDeleted;
  console.log(`╠${dline}╣`);
  console.log(
    `║  ${colH('ИТОГО', PAD_LABEL)}` +
    `${String(grandScanned).padStart(PAD_NUM)}` +
    `${String(grandFlagged).padStart(PAD_NUM)}` +
    `${String(effectiveDeleted).padStart(PAD_NUM)}  ║`,
  );
  console.log(`╚${dline}╝`);

  if (DRY_RUN) {
    console.log('\n  ⚠️  Это предпросмотр. Для реального удаления запусти:');
    console.log('     node cleanup_guest_and_test.js ./key.json --run\n');
  } else {
    console.log(`\n  ✅  Удаление завершено. Всего удалено: ${grandDeleted} документов.\n`);
  }
}

// ─── MAIN ─────────────────────────────────────────────────────────────────────

async function main() {
  const dline = '═'.repeat(56);
  console.log(`\n╔${dline}╗`);
  console.log(
    DRY_RUN
      ? `║  WORKA — Очистка Firestore  [DRY-RUN — без изменений]  ║`
      : `║  WORKA — Очистка Firestore  [РЕАЛЬНЫЙ РЕЖИМ]           ║`,
  );
  if (DELETE_SOFT_DEL)
    console.log(`║  + удаление CV с isDeleted=true                        ║`);
  if (SKIP_SUBCOLS)
    console.log(`║  + пропуск подколлекций users/{uid}/...                ║`);
  console.log(`╚${dline}╝`);

  // ─ A: Тестовые коллекции ──────────────────────────────────────────────────
  console.log('\n════ A) ТЕСТОВЫЕ КОЛЛЕКЦИИ ════════════════════════════════');
  await deleteEntireCollection('cvs_test');
  await deleteEntireCollection('jobs_test');
  await deleteEntireCollection('responses_test');
  await deleteEntireCollection('app_test');

  // ─ B: Гостевые записи в production коллекциях ────────────────────────────
  console.log('\n════ B) ГОСТЕВЫЕ ЗАПИСИ (production) ══════════════════════');
  await cleanCvs();
  await cleanJobs();
  await cleanApplications();
  await cleanJobOffers();

  // ─ C: Legacy responses ────────────────────────────────────────────────────
  console.log('\n════ C) LEGACY RESPONSES ══════════════════════════════════');
  await cleanResponses();

  // ─ D: Подколлекции ────────────────────────────────────────────────────────
  console.log('\n════ D) ПОДКОЛЛЕКЦИИ ПОЛЬЗОВАТЕЛЕЙ ════════════════════════');
  await cleanUserSubcollections();

  // ─ Итог ───────────────────────────────────────────────────────────────────
  printReport();
  process.exit(0);
}

main().catch((err) => {
  console.error('\n❌  Критическая ошибка:', err.message || err);
  console.error(err.stack);
  process.exit(1);
});
