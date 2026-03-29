#!/usr/bin/env node
/**
 * cleanup_integrity_safe.js
 *
 * Safe integrity cleanup for Worka Firestore data.
 *
 * Modes:
 * - default: audit-only dry-run (no writes)
 * - --run: soft cleanup mode (reversible actions)
 * - --run --hard-delete-*: optional destructive mode for explicitly-safe categories
 *
 * Usage:
 *   node scripts/cleanup_integrity_safe.js ./serviceAccountKey.json
 *   node scripts/cleanup_integrity_safe.js ./serviceAccountKey.json --run
 *   node scripts/cleanup_integrity_safe.js ./serviceAccountKey.json --run --mark-invalid-unfinished
 *   node scripts/cleanup_integrity_safe.js ./serviceAccountKey.json --run --soft-delete-explicit-duplicates
 *   node scripts/cleanup_integrity_safe.js ./serviceAccountKey.json --run --hard-delete-orphans
 */

/* eslint-disable no-console */
const path = require('path');
const admin = require('firebase-admin');

const args = process.argv.slice(2);
const isRun = args.includes('--run');
const dryRun = !isRun;
const markInvalidUnfinished = args.includes('--mark-invalid-unfinished');
const softDeleteExplicitDuplicates = args.includes('--soft-delete-explicit-duplicates');
const softDeleteGarbage = args.includes('--soft-delete-garbage') || isRun;
const softDeleteCopyTitle = args.includes('--soft-delete-copy-title');
const hardDeleteOrphans = args.includes('--hard-delete-orphans');
const hardDeleteExplicitDuplicates = args.includes('--hard-delete-explicit-duplicates');
const serviceAccountPath = args.find((a) => !a.startsWith('--')) || process.env.GOOGLE_APPLICATION_CREDENTIALS;

if (!serviceAccountPath) {
  console.error('Usage: node scripts/cleanup_integrity_safe.js ./serviceAccountKey.json [--run] [--mark-invalid-unfinished] [--soft-delete-garbage] [--soft-delete-copy-title] [--soft-delete-explicit-duplicates] [--hard-delete-orphans] [--hard-delete-explicit-duplicates]');
  process.exit(1);
}

const serviceAccount = require(path.resolve(serviceAccountPath));
admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });

const app = admin.app();
const projectId = app.options.projectId || serviceAccount.project_id || '';
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
  runMode: isRun ? 'WRITE' : 'DRY-RUN',
  allowProd,
  estimatedOps: 'unknown',
});

const db = admin.firestore();

const COL = {
  jobs: 'jobs',
  cvs: 'cvs',
  applications: 'applications',
  jobOffers: 'jobOffers',
  users: 'users',
};

const BATCH_SIZE = 380;
const nowTs = admin.firestore.FieldValue.serverTimestamp();

function s(v) {
  return (v ?? '').toString().trim();
}

function isTrue(v) {
  if (v === true) return true;
  if (typeof v === 'number') return v !== 0;
  const t = s(v).toLowerCase();
  return t === 'true' || t === '1' || t === 'yes' || t === 'да';
}

function isPlaceholderText(v) {
  const t = s(v).toLowerCase();
  return t === '' || t === '-' || t === 'n/a' || t === 'null' || t === 'undefined' || t === 'не указано' || t === 'не указан' || t === 'не указана';
}

function containsLetter(v) {
  return /[A-Za-zА-Яа-яЁё]/.test(s(v));
}

function looksGarbageText(v) {
  const t = s(v);
  if (t.length < 2) return true;
  if (!containsLetter(t)) return true;
  const chars = t.replace(/\s+/g, '');
  if (!chars) return true;
  const letters = (chars.match(/[A-Za-zА-Яа-яЁё]/g) || []).length;
  const digits = (chars.match(/\d/g) || []).length;
  const symbols = (chars.match(/[^A-Za-zА-Яа-яЁё0-9]/g) || []).length;
  if (letters === 0) return true;
  if (digits > letters * 2) return true;
  if (symbols > letters) return true;
  const uniqueChars = new Set(chars.toLowerCase().split('')).size;
  if (chars.length >= 6 && uniqueChars <= 2) return true;
  return false;
}

function hasCopyToken(text) {
  const t = s(text).toLowerCase();
  return t.includes('копия') || t.includes('copy');
}

function looksGuestLikeOwner(ownerId) {
  const v = s(ownerId).toLowerCase();
  if (!v) return true;
  return v.startsWith('guest_') ||
      v === 'guest' ||
      v === 'anonymous' ||
      v === 'anon' ||
      v === 'unknown' ||
      v === 'none' ||
      v === 'null' ||
      v === 'undefined' ||
      v === 'test' ||
      v === 'dev';
}

function isDeletedLike(doc) {
  if (isTrue(doc.isDeleted)) return true;
  if (doc.deletedAt != null) return true;
  const status = s(doc.status).toLowerCase();
  return ['deleted', 'archived', 'removed', 'blocked', 'banned', 'suspended'].includes(status);
}

function isDraftLike(doc) {
  if (isTrue(doc.isDraft) || isTrue(doc.draft)) return true;
  const st = s(doc.status).toLowerCase();
  return st === 'draft';
}

function isIncompleteLike(doc) {
  if (isTrue(doc.isIncomplete) || isTrue(doc.incomplete)) return true;
  if (Object.prototype.hasOwnProperty.call(doc, 'isComplete') && isTrue(doc.isComplete) === false) return true;
  const st = s(doc.status).toLowerCase();
  return st === 'unfinished' || st === 'incomplete';
}

function isStaleDuplicateLike(doc) {
  if (isTrue(doc.isStaleDuplicate) || isTrue(doc.isDuplicate) || isTrue(doc.duplicate) || isTrue(doc.isSuperseded) || isTrue(doc.superseded)) return true;
  if (s(doc.duplicateOfId) || s(doc.supersededById) || s(doc.replacedById)) return true;
  const st = s(doc.status).toLowerCase();
  return st === 'duplicate' || st === 'stale' || st === 'superseded';
}

function resolveOwnerId(doc, keys) {
  for (const key of keys) {
    const value = s(doc[key]);
    if (value) return value;
  }
  return '';
}

function vacancyOwnerId(doc) {
  return resolveOwnerId(doc, ['ownerId', 'ownerUid', 'ownerKey', 'authorId', 'userId', 'employerOwnerId', 'employerUid']);
}

function cvOwnerId(doc) {
  return resolveOwnerId(doc, ['ownerId', 'ownerUid', 'ownerKey', 'candidateOwnerId', 'candidateUid', 'userId']);
}

function hasValidSalaryVacancy(doc) {
  const n = doc.salaryAmount ?? doc.salaryFrom;
  if (typeof n === 'number') return n > 0 && n <= 200000;
  const salaryText = s(doc.salaryText) || s(doc.salary);
  if (isPlaceholderText(salaryText)) return false;
  const m = salaryText.replace(/\s/g, '').match(/(\d{2,7})/);
  if (!m) return false;
  const p = Number(m[1]);
  return Number.isFinite(p) && p > 0 && p <= 200000;
}

function hasValidSalaryCv(doc) {
  const desired = (doc.desired && typeof doc.desired === 'object') ? doc.desired : {};
  const n = desired.salaryAmount ?? desired.salaryFrom ?? desired.salaryExpected ?? doc.salaryAmount ?? doc.salaryFrom ?? doc.salaryExpected;
  if (typeof n === 'number') return n > 0 && n <= 200000;
  const salaryText = s(desired.salaryText) || s(doc.salaryText) || s(doc.salary);
  if (isPlaceholderText(salaryText)) return false;
  const m = salaryText.replace(/\s/g, '').match(/(\d{2,7})/);
  if (!m) return false;
  const p = Number(m[1]);
  return Number.isFinite(p) && p > 0 && p <= 200000;
}

function isValidPublicVacancy(doc) {
  if (isDeletedLike(doc)) return false;
  if (isDraftLike(doc) || isIncompleteLike(doc)) return false;
  if (Object.prototype.hasOwnProperty.call(doc, 'publishable') && isTrue(doc.publishable) === false) return false;
  if (Object.prototype.hasOwnProperty.call(doc, 'published') && isTrue(doc.published) === false) return false;
  if (Object.prototype.hasOwnProperty.call(doc, 'isPublished') && isTrue(doc.isPublished) === false) return false;
  if (isStaleDuplicateLike(doc)) return false;

  const title = s(doc.title);
  const category = s(doc.category);
  const city = s(doc.city);
  const country = s(doc.country);
  if (!title || hasCopyToken(title) || looksGarbageText(title)) return false;
  if (!category || looksGarbageText(category)) return false;
  if (!city || looksGarbageText(city)) return false;
  if (!country || looksGarbageText(country)) return false;
  if (!vacancyOwnerId(doc)) return false;
  if (!hasValidSalaryVacancy(doc)) return false;
  return true;
}

function isValidPublicCv(doc) {
  if (isDeletedLike(doc)) return false;
  if (isDraftLike(doc) || isIncompleteLike(doc)) return false;
  if (Object.prototype.hasOwnProperty.call(doc, 'publishable') && isTrue(doc.publishable) === false) return false;
  if (Object.prototype.hasOwnProperty.call(doc, 'published') && isTrue(doc.published) === false) return false;
  if (Object.prototype.hasOwnProperty.call(doc, 'isPublished') && isTrue(doc.isPublished) === false) return false;
  if (isStaleDuplicateLike(doc)) return false;

  const title = s(doc.title) || s(doc.profession);
  if (!title || hasCopyToken(title) || looksGarbageText(title)) return false;

  const desired = (doc.desired && typeof doc.desired === 'object') ? doc.desired : {};
  const city = s(doc.city) || s(desired.citiesText);
  const countries = Array.isArray(desired.countries) ? desired.countries : [];
  const country = countries.length > 0 ? s(countries[0]) : s(doc.country);
  if (!city || looksGarbageText(city)) return false;
  if (!country || looksGarbageText(country)) return false;
  if (!cvOwnerId(doc)) return false;
  if (!hasValidSalaryCv(doc)) return false;
  return true;
}

function normalizeCopyBaseTitle(title) {
  return s(title)
    .toLowerCase()
    .replace(/\((копия|copy)\)/g, ' ')
    .replace(/\b(копия|copy)\b/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function keyByOwnerAndBaseTitle(owner, title) {
  return `${owner}::${normalizeCopyBaseTitle(title)}`;
}

class BatchWriter {
  constructor() {
    this.batch = db.batch();
    this.count = 0;
    this.written = 0;
  }

  async set(ref, payload, options = { merge: true }) {
    this.batch.set(ref, payload, options);
    this.count += 1;
    if (this.count >= BATCH_SIZE) await this.flush();
  }

  async delete(ref) {
    this.batch.delete(ref);
    this.count += 1;
    if (this.count >= BATCH_SIZE) await this.flush();
  }

  async flush() {
    if (this.count === 0) return;
    await this.batch.commit();
    this.written += this.count;
    this.batch = db.batch();
    this.count = 0;
  }
}

async function readAllDocs(collectionName) {
  const out = [];
  let cursor = null;
  while (true) {
    let q = db.collection(collectionName).orderBy(admin.firestore.FieldPath.documentId()).limit(500);
    if (cursor) q = q.startAfter(cursor);
    const snap = await q.get();
    if (snap.empty) break;
    out.push(...snap.docs);
    cursor = snap.docs[snap.docs.length - 1].id;
  }
  return out;
}

function buildIssue({ category, collection, docId, reason, action, payload }) {
  return { category, collection, docId, reason, action, payload };
}

async function softDeleteWithCleanup(writer, { collection, docId, category, action }) {
  await writer.set(db.collection(collection).doc(docId), {
    isDeleted: true,
    deletedAt: nowTs,
    status: 'deleted',
    updatedAt: nowTs,
    cleanup: {
      integrity: true,
      category,
      action,
      at: nowTs,
      by: 'cleanup_integrity_safe.js',
    },
  }, { merge: true });
}

async function main() {
  console.log('╔══════════════════════════════════════════════════════╗');
  console.log(`║ Worka integrity cleanup ${dryRun ? '[DRY-RUN]' : '[RUN]'}${' '.repeat(dryRun ? 21 : 25)}║`);
  console.log('╚══════════════════════════════════════════════════════╝');
  if (!dryRun) {
    console.log(`flags: markInvalidUnfinished=${markInvalidUnfinished} softDeleteGarbage=${softDeleteGarbage} softDeleteCopyTitle=${softDeleteCopyTitle} softDeleteExplicitDuplicates=${softDeleteExplicitDuplicates} hardDeleteOrphans=${hardDeleteOrphans} hardDeleteExplicitDuplicates=${hardDeleteExplicitDuplicates}`);
  }

  const writer = new BatchWriter();
  const stats = {
    scanned: { jobs: 0, cvs: 0, applications: 0, jobOffers: 0, users: 0 },
    issues: {},
    actions: {},
  };

  const jobsDocs = await readAllDocs(COL.jobs);
  const cvsDocs = await readAllDocs(COL.cvs);
  const appDocs = await readAllDocs(COL.applications);
  const offerDocs = await readAllDocs(COL.jobOffers);
  const userDocs = await readAllDocs(COL.users);
  stats.scanned.jobs = jobsDocs.length;
  stats.scanned.cvs = cvsDocs.length;
  stats.scanned.applications = appDocs.length;
  stats.scanned.jobOffers = offerDocs.length;
  stats.scanned.users = userDocs.length;

  const jobById = new Map(jobsDocs.map((d) => [d.id, d.data() || {}]));
  const cvById = new Map(cvsDocs.map((d) => [d.id, d.data() || {}]));
  const validUserIds = new Set();
  for (const u of userDocs) {
    const m = u.data() || {};
    if (isDeletedLike(m)) continue;
    if (looksGuestLikeOwner(u.id)) continue;
    validUserIds.add(u.id.trim());
  }

  const possibleDuplicateVacancyGroups = new Map();
  const possibleDuplicateCvGroups = new Map();
  const allIssues = [];

  function pushIssue(issue) {
    allIssues.push(issue);
    stats.issues[issue.category] = (stats.issues[issue.category] || 0) + 1;
    console.log(`[${dryRun ? 'dry' : 'run'}] ${issue.collection}/${issue.docId} :: ${issue.category} :: ${issue.reason} -> ${issue.action}`);
  }

  for (const d of jobsDocs) {
    const m = d.data() || {};
    const owner = vacancyOwnerId(m);
    const title = s(m.title);

    if (isDeletedLike(m)) {
      pushIssue(buildIssue({
        category: 'deleted_vacancy_record',
        collection: COL.jobs,
        docId: d.id,
        reason: 'vacancy has deleted-like flags',
        action: 'audit_only',
      }));
      continue;
    }

    if (!owner) {
      pushIssue(buildIssue({
        category: 'owner_invalid_vacancy',
        collection: COL.jobs,
        docId: d.id,
        reason: 'ownerId/ownerUid/ownerKey/employerOwnerId missing',
        action: 'soft_delete_owner_invalid',
      }));
      if (!dryRun) {
        await softDeleteWithCleanup(writer, {
          collection: COL.jobs,
          docId: d.id,
          category: 'owner_invalid_vacancy',
          action: 'soft_delete_owner_invalid',
        });
        stats.actions.soft_delete_owner_invalid = (stats.actions.soft_delete_owner_invalid || 0) + 1;
      }
      continue;
    }
    if (!validUserIds.has(owner) || looksGuestLikeOwner(owner)) {
      pushIssue(buildIssue({
        category: 'owner_not_registered_vacancy',
        collection: COL.jobs,
        docId: d.id,
        reason: `owner "${owner}" has no valid users/{uid} doc`,
        action: 'soft_delete_owner_invalid',
      }));
      if (!dryRun) {
        await softDeleteWithCleanup(writer, {
          collection: COL.jobs,
          docId: d.id,
          category: 'owner_not_registered_vacancy',
          action: 'soft_delete_owner_invalid',
        });
        stats.actions.soft_delete_owner_invalid = (stats.actions.soft_delete_owner_invalid || 0) + 1;
      }
      continue;
    }
    if (hasCopyToken(title)) {
      pushIssue(buildIssue({
        category: 'copy_title_vacancy',
        collection: COL.jobs,
        docId: d.id,
        reason: 'title contains copy token',
        action: softDeleteCopyTitle ? 'soft_delete_copy_title' : 'move_to_unfinished',
      }));
      if (!dryRun && softDeleteCopyTitle) {
        await softDeleteWithCleanup(writer, {
          collection: COL.jobs,
          docId: d.id,
          category: 'copy_title_vacancy',
          action: 'soft_delete_copy_title',
        });
        stats.actions.soft_delete_copy_title = (stats.actions.soft_delete_copy_title || 0) + 1;
        continue;
      }
    }
    if (isDraftLike(m)) {
      pushIssue(buildIssue({
        category: 'draft_vacancy',
        collection: COL.jobs,
        docId: d.id,
        reason: 'draft flag/status',
        action: 'unfinished_owner_only',
      }));
    }
    if (isIncompleteLike(m)) {
      pushIssue(buildIssue({
        category: 'incomplete_vacancy',
        collection: COL.jobs,
        docId: d.id,
        reason: 'incomplete flag/status/isComplete=false',
        action: 'unfinished_owner_only',
      }));
    }
    if (isStaleDuplicateLike(m)) {
      pushIssue(buildIssue({
        category: 'duplicate_stale_vacancy_explicit',
        collection: COL.jobs,
        docId: d.id,
        reason: 'explicit duplicate/superseded markers',
        action: softDeleteExplicitDuplicates ? 'soft_delete' : 'audit_only',
      }));
      if (!dryRun && softDeleteExplicitDuplicates) {
        const ref = db.collection(COL.jobs).doc(d.id);
        if (hardDeleteExplicitDuplicates) {
          await writer.delete(ref);
          stats.actions.hard_delete = (stats.actions.hard_delete || 0) + 1;
        } else {
          await softDeleteWithCleanup(writer, {
            collection: COL.jobs,
            docId: d.id,
            category: 'duplicate_stale_vacancy_explicit',
            action: 'soft_delete',
          });
          stats.actions.soft_delete = (stats.actions.soft_delete || 0) + 1;
        }
      }
    }

    const hasGarbage =
      !s(title) || looksGarbageText(title) ||
      !s(m.category) || looksGarbageText(m.category) ||
      !s(m.city) || looksGarbageText(m.city) ||
      !s(m.country) || looksGarbageText(m.country) ||
      !hasValidSalaryVacancy(m);
    if (hasGarbage) {
      pushIssue(buildIssue({
        category: 'garbage_vacancy_fields',
        collection: COL.jobs,
        docId: d.id,
        reason: 'title/category/city/country/salary invalid for public',
        action: softDeleteGarbage ? 'soft_delete_garbage' : (markInvalidUnfinished ? 'mark_unfinished' : 'annotate_only'),
      }));
      if (!dryRun && softDeleteGarbage) {
        await softDeleteWithCleanup(writer, {
          collection: COL.jobs,
          docId: d.id,
          category: 'garbage_vacancy_fields',
          action: 'soft_delete_garbage',
        });
        stats.actions.soft_delete_garbage = (stats.actions.soft_delete_garbage || 0) + 1;
        continue;
      }
    }

    if (!isValidPublicVacancy(m)) {
      pushIssue(buildIssue({
        category: 'invalid_public_vacancy',
        collection: COL.jobs,
        docId: d.id,
        reason: 'fails public vacancy predicate',
        action: markInvalidUnfinished ? 'mark_unfinished' : 'annotate_only',
      }));
      if (!dryRun) {
        const patch = {
          updatedAt: nowTs,
          cleanup: {
            integrity: true,
            category: 'invalid_public_vacancy',
            action: markInvalidUnfinished ? 'mark_unfinished' : 'annotate_only',
            at: nowTs,
            by: 'cleanup_integrity_safe.js',
          },
        };
        if (markInvalidUnfinished) {
          patch.publishable = false;
          patch.isIncomplete = true;
        }
        await writer.set(db.collection(COL.jobs).doc(d.id), patch, { merge: true });
        stats.actions[markInvalidUnfinished ? 'mark_unfinished' : 'annotate_only'] =
          (stats.actions[markInvalidUnfinished ? 'mark_unfinished' : 'annotate_only'] || 0) + 1;
      }
    }

    const possibleKey = keyByOwnerAndBaseTitle(owner, title);
    if (owner && normalizeCopyBaseTitle(title)) {
      if (!possibleDuplicateVacancyGroups.has(possibleKey)) possibleDuplicateVacancyGroups.set(possibleKey, []);
      possibleDuplicateVacancyGroups.get(possibleKey).push(d.id);
    }
  }

  for (const d of cvsDocs) {
    const m = d.data() || {};
    const owner = cvOwnerId(m);
    const title = s(m.title) || s(m.profession);

    if (isDeletedLike(m)) {
      pushIssue(buildIssue({
        category: 'deleted_cv_record',
        collection: COL.cvs,
        docId: d.id,
        reason: 'cv has deleted-like flags',
        action: 'audit_only',
      }));
      continue;
    }

    if (!owner) {
      pushIssue(buildIssue({
        category: 'owner_invalid_cv',
        collection: COL.cvs,
        docId: d.id,
        reason: 'ownerId/ownerUid/candidateOwnerId missing',
        action: 'soft_delete_owner_invalid',
      }));
      if (!dryRun) {
        await writer.set(db.collection(COL.cvs).doc(d.id), {
          isDeleted: true,
          deletedAt: nowTs,
          status: 'deleted',
          updatedAt: nowTs,
          cleanup: {
            integrity: true,
            category: 'owner_invalid_cv',
            action: 'soft_delete_owner_invalid',
            at: nowTs,
            by: 'cleanup_integrity_safe.js',
          },
        }, { merge: true });
        stats.actions.soft_delete_owner_invalid = (stats.actions.soft_delete_owner_invalid || 0) + 1;
      }
      continue;
    }
    if (!validUserIds.has(owner) || looksGuestLikeOwner(owner)) {
      pushIssue(buildIssue({
        category: 'owner_not_registered_cv',
        collection: COL.cvs,
        docId: d.id,
        reason: `owner "${owner}" has no valid users/{uid} doc`,
        action: 'soft_delete_owner_invalid',
      }));
      if (!dryRun) {
        await softDeleteWithCleanup(writer, {
          collection: COL.cvs,
          docId: d.id,
          category: 'owner_not_registered_cv',
          action: 'soft_delete_owner_invalid',
        });
        stats.actions.soft_delete_owner_invalid = (stats.actions.soft_delete_owner_invalid || 0) + 1;
      }
      continue;
    }
    if (hasCopyToken(title)) {
      pushIssue(buildIssue({
        category: 'copy_title_cv',
        collection: COL.cvs,
        docId: d.id,
        reason: 'title/profession contains copy token',
        action: softDeleteCopyTitle ? 'soft_delete_copy_title' : 'move_to_unfinished',
      }));
      if (!dryRun && softDeleteCopyTitle) {
        await softDeleteWithCleanup(writer, {
          collection: COL.cvs,
          docId: d.id,
          category: 'copy_title_cv',
          action: 'soft_delete_copy_title',
        });
        stats.actions.soft_delete_copy_title = (stats.actions.soft_delete_copy_title || 0) + 1;
        continue;
      }
    }
    if (isDraftLike(m)) {
      pushIssue(buildIssue({
        category: 'draft_cv',
        collection: COL.cvs,
        docId: d.id,
        reason: 'draft flag/status',
        action: 'unfinished_owner_only',
      }));
    }
    if (isIncompleteLike(m)) {
      pushIssue(buildIssue({
        category: 'incomplete_cv',
        collection: COL.cvs,
        docId: d.id,
        reason: 'incomplete flag/status/isComplete=false',
        action: 'unfinished_owner_only',
      }));
    }
    if (isStaleDuplicateLike(m)) {
      pushIssue(buildIssue({
        category: 'duplicate_stale_cv_explicit',
        collection: COL.cvs,
        docId: d.id,
        reason: 'explicit duplicate/superseded markers',
        action: softDeleteExplicitDuplicates ? 'soft_delete' : 'audit_only',
      }));
      if (!dryRun && softDeleteExplicitDuplicates) {
        const ref = db.collection(COL.cvs).doc(d.id);
        if (hardDeleteExplicitDuplicates) {
          await writer.delete(ref);
          stats.actions.hard_delete = (stats.actions.hard_delete || 0) + 1;
        } else {
          await softDeleteWithCleanup(writer, {
            collection: COL.cvs,
            docId: d.id,
            category: 'duplicate_stale_cv_explicit',
            action: 'soft_delete',
          });
          stats.actions.soft_delete = (stats.actions.soft_delete || 0) + 1;
        }
      }
    }

    const desired = (m.desired && typeof m.desired === 'object') ? m.desired : {};
    const city = s(m.city) || s(desired.citiesText);
    const countries = Array.isArray(desired.countries) ? desired.countries : [];
    const country = countries.length ? s(countries[0]) : s(m.country);
    const hasGarbage =
      !s(title) || looksGarbageText(title) ||
      !city || looksGarbageText(city) ||
      !country || looksGarbageText(country) ||
      !hasValidSalaryCv(m);
    if (hasGarbage) {
      pushIssue(buildIssue({
        category: 'garbage_cv_fields',
        collection: COL.cvs,
        docId: d.id,
        reason: 'title/profession/location/salary invalid for public',
        action: softDeleteGarbage ? 'soft_delete_garbage' : (markInvalidUnfinished ? 'mark_unfinished' : 'annotate_only'),
      }));
      if (!dryRun && softDeleteGarbage) {
        await softDeleteWithCleanup(writer, {
          collection: COL.cvs,
          docId: d.id,
          category: 'garbage_cv_fields',
          action: 'soft_delete_garbage',
        });
        stats.actions.soft_delete_garbage = (stats.actions.soft_delete_garbage || 0) + 1;
        continue;
      }
    }

    if (!isValidPublicCv(m)) {
      pushIssue(buildIssue({
        category: 'invalid_public_cv',
        collection: COL.cvs,
        docId: d.id,
        reason: 'fails public cv predicate',
        action: markInvalidUnfinished ? 'mark_unfinished' : 'annotate_only',
      }));
      if (!dryRun) {
        const patch = {
          updatedAt: nowTs,
          cleanup: {
            integrity: true,
            category: 'invalid_public_cv',
            action: markInvalidUnfinished ? 'mark_unfinished' : 'annotate_only',
            at: nowTs,
            by: 'cleanup_integrity_safe.js',
          },
        };
        if (markInvalidUnfinished) {
          patch.publishable = false;
          patch.isIncomplete = true;
        }
        await writer.set(db.collection(COL.cvs).doc(d.id), patch, { merge: true });
        stats.actions[markInvalidUnfinished ? 'mark_unfinished' : 'annotate_only'] =
          (stats.actions[markInvalidUnfinished ? 'mark_unfinished' : 'annotate_only'] || 0) + 1;
      }
    }

    const possibleKey = keyByOwnerAndBaseTitle(owner, title);
    if (owner && normalizeCopyBaseTitle(title)) {
      if (!possibleDuplicateCvGroups.has(possibleKey)) possibleDuplicateCvGroups.set(possibleKey, []);
      possibleDuplicateCvGroups.get(possibleKey).push(d.id);
    }
  }

  function linkedVacancyId(m) {
    return s(m.jobId) || s(m.vacancyId);
  }
  function linkedCvId(m) {
    return s(m.candidateCvId) || s(m.cvId);
  }
  function isActiveSourceDoc(doc) {
    return !!doc && !isDeletedLike(doc);
  }

  for (const d of appDocs) {
    const m = d.data() || {};
    const type = s(m.type).toLowerCase();
    if (type && type !== 'apply' && type !== 'application' && type !== 'response') continue;
    if (isDeletedLike(m)) {
      pushIssue(buildIssue({
        category: 'deleted_application_record',
        collection: COL.applications,
        docId: d.id,
        reason: 'application already deleted-like',
        action: 'audit_only',
      }));
      continue;
    }
    const jobId = linkedVacancyId(m);
    const cvId = linkedCvId(m);
    const job = jobById.get(jobId);
    const cv = cvById.get(cvId);
    const jobOwner = job ? vacancyOwnerId(job) : '';
    const cvOwner = cv ? cvOwnerId(cv) : '';
    const orphan = !jobId ||
      !cvId ||
      !isActiveSourceDoc(job) ||
      !isActiveSourceDoc(cv) ||
      !isValidPublicVacancy(job || {}) ||
      !isValidPublicCv(cv || {}) ||
      !jobOwner ||
      !cvOwner ||
      !validUserIds.has(jobOwner) ||
      !validUserIds.has(cvOwner);
    if (orphan) {
      pushIssue(buildIssue({
        category: 'orphan_response',
        collection: COL.applications,
        docId: d.id,
        reason: `linked source missing/invalid jobId=${jobId || '-'} cvId=${cvId || '-'}`,
        action: hardDeleteOrphans ? 'hard_delete' : 'soft_delete',
      }));
      if (!dryRun) {
        const ref = db.collection(COL.applications).doc(d.id);
        if (hardDeleteOrphans) {
          await writer.delete(ref);
          stats.actions.hard_delete = (stats.actions.hard_delete || 0) + 1;
        } else {
          await softDeleteWithCleanup(writer, {
            collection: COL.applications,
            docId: d.id,
            category: 'orphan_response',
            action: 'soft_delete',
          });
          stats.actions.soft_delete = (stats.actions.soft_delete || 0) + 1;
        }
      }
    }
  }

  for (const d of offerDocs) {
    const m = d.data() || {};
    const type = s(m.type).toLowerCase();
    if (type && type !== 'offer') continue;
    if (isDeletedLike(m)) {
      pushIssue(buildIssue({
        category: 'deleted_offer_record',
        collection: COL.jobOffers,
        docId: d.id,
        reason: 'offer already deleted-like',
        action: 'audit_only',
      }));
      continue;
    }
    const jobId = linkedVacancyId(m);
    const cvId = linkedCvId(m);
    const job = jobById.get(jobId);
    const cv = cvById.get(cvId);
    const jobOwner = job ? vacancyOwnerId(job) : '';
    const cvOwner = cv ? cvOwnerId(cv) : '';
    const orphan = !jobId ||
      !cvId ||
      !isActiveSourceDoc(job) ||
      !isActiveSourceDoc(cv) ||
      !isValidPublicVacancy(job || {}) ||
      !isValidPublicCv(cv || {}) ||
      !jobOwner ||
      !cvOwner ||
      !validUserIds.has(jobOwner) ||
      !validUserIds.has(cvOwner);
    if (orphan) {
      pushIssue(buildIssue({
        category: 'orphan_offer',
        collection: COL.jobOffers,
        docId: d.id,
        reason: `linked source missing/invalid jobId=${jobId || '-'} cvId=${cvId || '-'}`,
        action: hardDeleteOrphans ? 'hard_delete' : 'soft_delete',
      }));
      if (!dryRun) {
        const ref = db.collection(COL.jobOffers).doc(d.id);
        if (hardDeleteOrphans) {
          await writer.delete(ref);
          stats.actions.hard_delete = (stats.actions.hard_delete || 0) + 1;
        } else {
          await softDeleteWithCleanup(writer, {
            collection: COL.jobOffers,
            docId: d.id,
            category: 'orphan_offer',
            action: 'soft_delete',
          });
          stats.actions.soft_delete = (stats.actions.soft_delete || 0) + 1;
        }
      }
    }
  }

  for (const [k, ids] of possibleDuplicateVacancyGroups.entries()) {
    if (ids.length <= 1) continue;
    pushIssue(buildIssue({
      category: 'duplicate_stale_vacancy_potential',
      collection: COL.jobs,
      docId: ids.join(','),
      reason: `same owner+normalized title group=${k} size=${ids.length}`,
      action: 'manual_review_only',
    }));
  }

  for (const [k, ids] of possibleDuplicateCvGroups.entries()) {
    if (ids.length <= 1) continue;
    pushIssue(buildIssue({
      category: 'duplicate_stale_cv_potential',
      collection: COL.cvs,
      docId: ids.join(','),
      reason: `same owner+normalized title/profession group=${k} size=${ids.length}`,
      action: 'manual_review_only',
    }));
  }

  if (!dryRun) await writer.flush();

  console.log('\n━━ SUMMARY ━━');
  console.log(`mode: ${dryRun ? 'dry-run' : 'run'}`);
  console.log(`scanned: users=${stats.scanned.users}, jobs=${stats.scanned.jobs}, cvs=${stats.scanned.cvs}, applications=${stats.scanned.applications}, jobOffers=${stats.scanned.jobOffers}`);
  console.log(`issues total: ${allIssues.length}`);
  console.log('by category:');
  for (const [k, v] of Object.entries(stats.issues).sort((a, b) => b[1] - a[1])) {
    console.log(`  - ${k}: ${v}`);
  }
  if (!dryRun) {
    console.log('writes:');
    for (const [k, v] of Object.entries(stats.actions).sort((a, b) => b[1] - a[1])) {
      console.log(`  - ${k}: ${v}`);
    }
    console.log(`batch ops committed: ${writer.written}`);
  } else {
    console.log('\nDry-run only. Re-run with --run to apply soft cleanup actions.');
  }
}

main().catch((err) => {
  console.error('cleanup_integrity_safe.js failed:', err);
  process.exit(1);
});
