/* eslint-disable no-console */
const admin = require('firebase-admin');

const BATCH_SIZE = 300;

function parseArg(name) {
  const idx = process.argv.findIndex((a) => a === `--${name}`);
  if (idx < 0) return '';
  return (process.argv[idx + 1] || '').trim();
}

const projectId = parseArg('project');
const allowProd = process.argv.includes('--allow-prod');
if (projectId) {
  admin.initializeApp({ projectId });
} else {
  admin.initializeApp();
}

const resolvedProjectId = admin.app().options.projectId || projectId || '';
if (!resolvedProjectId) {
  console.error('❌ Cannot determine projectId (provide --project or GOOGLE_CLOUD_PROJECT). Aborting.');
  process.exit(1);
}
if (resolvedProjectId === 'worka-416c0' && !allowProd) {
  console.error('❌ Refusing to run against production project worka-416c0 without --allow-prod');
  process.exit(1);
}

console.log('[env]', { projectId: resolvedProjectId, allowProd });

const db = admin.firestore();

async function docExists(collectionName, docId) {
  if (!docId) return false;
  const snap = await db.collection(collectionName).doc(docId).get();
  return snap.exists;
}

async function responseIsValid(doc, env) {
  const data = doc.data() || {};
  const jobId = (data.jobId || '').toString().trim();
  const cvId = (data.candidateCvId || data.cvId || '').toString().trim();
  if (!jobId || !cvId) return false;

  const jobCol = env === 'test' ? 'jobs_test' : 'jobs';
  const cvCol = env === 'test' ? 'cvs_test' : 'cvs';

  const [jobOk, cvOk] = await Promise.all([
    docExists(jobCol, jobId),
    docExists(cvCol, cvId),
  ]);
  return jobOk && cvOk;
}

function dedupeKey(data) {
  const type = (data.type || '').toString().trim().toLowerCase();
  const jobId = (data.jobId || '').toString().trim();
  const cvId = (data.candidateCvId || data.cvId || '').toString().trim();
  const candidateOwnerId = (data.candidateOwnerId || '').toString().trim();
  const employerOwnerId = (data.employerOwnerId || '').toString().trim();
  if (!type || !jobId || !cvId) return '';
  if (type === 'apply') return `${type}|${jobId}|${candidateOwnerId}|${cvId}`;
  if (type === 'offer') return `${type}|${jobId}|${employerOwnerId}|${candidateOwnerId}`;
  return `${type}|${jobId}|${candidateOwnerId}|${employerOwnerId}|${cvId}`;
}

async function cleanupCollection(collectionName, env) {
  let scanned = 0;
  let deleted = 0;
  let deletedDuplicates = 0;
  let cursor = '';
  const seenKeys = new Set();

  while (true) {
    let query = db
      .collection(collectionName)
      .orderBy(admin.firestore.FieldPath.documentId())
      .limit(BATCH_SIZE);
    if (cursor) {
      query = query.startAfter(cursor);
    }
    const snap = await query.get();
    if (snap.empty) break;

    const refsToDelete = [];
    for (const doc of snap.docs) {
      scanned += 1;
      const data = doc.data() || {};
      const valid = await responseIsValid(doc, env);
      if (!valid) {
        refsToDelete.push(doc.ref);
        continue;
      }
      const key = dedupeKey(data);
      if (!key) continue;
      if (seenKeys.has(key)) {
        refsToDelete.push(doc.ref);
        deletedDuplicates += 1;
      } else {
        seenKeys.add(key);
      }
    }

    if (refsToDelete.length > 0) {
      const batch = db.batch();
      for (const ref of refsToDelete) {
        batch.delete(ref);
        deleted += 1;
      }
      await batch.commit();
      console.log(
        `[${collectionName}] deleted ${refsToDelete.length} orphan responses`,
      );
    }

    cursor = snap.docs[snap.docs.length - 1].id;
    if (snap.size < BATCH_SIZE) break;
  }

  return { scanned, deleted, deletedDuplicates };
}

async function run() {
  console.log('Starting orphan responses cleanup...');
  const prod = await cleanupCollection('responses', 'prod');
  const test = await cleanupCollection('responses_test', 'test');
  console.log('Cleanup completed.');
  console.log(
    JSON.stringify(
      {
        projectId: projectId || process.env.GCLOUD_PROJECT || 'default',
        responses: prod,
        responses_test: test,
      },
      null,
      2,
    ),
  );
}

run()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error('Cleanup failed:', e);
    process.exit(1);
  });
