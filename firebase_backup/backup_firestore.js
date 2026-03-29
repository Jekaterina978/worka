'use strict';

/**
 * backup_firestore.js
 * Downloads ALL Firestore collections (including subcollections) and saves
 * each document as an individual JSON file.
 *
 * Output:
 *   backup/firestore/<collection>/<docId>.json
 *   backup/firestore/<collection>/<docId>/<subCollection>/<subDocId>.json
 */

const admin  = require('firebase-admin');
const fs     = require('fs');
const path   = require('path');

// ─── Init ────────────────────────────────────────────────────────────────────

const SA_PATH      = path.resolve(__dirname, 'serviceAccountKey.json');
const BACKUP_ROOT  = path.resolve(__dirname, 'backup', 'firestore');
const TIMESTAMP    = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);

if (!fs.existsSync(SA_PATH)) {
  console.error('❌  serviceAccountKey.json not found. Read the placeholder file for instructions.');
  process.exit(1);
}

const sa = JSON.parse(fs.readFileSync(SA_PATH, 'utf8'));
if (sa._PLACEHOLDER) {
  console.error('❌  serviceAccountKey.json is still a placeholder. Replace it with your real key.');
  process.exit(1);
}

admin.initializeApp({ credential: admin.credential.cert(sa) });

const allowProd = process.argv.includes('--allow-prod');
const projectId = admin.app().options.projectId || sa.project_id || '';
if (!projectId) {
  console.error('❌ Cannot determine projectId from service account. Aborting.');
  process.exit(1);
}
if (projectId === 'worka-416c0' && !allowProd) {
  console.error('❌ Refusing to run backup against production project worka-416c0 without --allow-prod');
  process.exit(1);
}

console.log('[env]', { projectId, serviceAccountEmail: sa.client_email || 'n/a', allowProd });

const db = admin.firestore();

// ─── Stats ───────────────────────────────────────────────────────────────────

let totalDocs = 0;
let totalCols = 0;

// ─── Helpers ─────────────────────────────────────────────────────────────────

function ensureDir(dir) {
  fs.mkdirSync(dir, { recursive: true });
}

/**
 * Converts Firestore Timestamps → ISO strings so JSON.stringify works.
 */
function serialize(data) {
  if (data === null || data === undefined) return data;
  if (typeof data !== 'object') return data;
  if (data.toDate && typeof data.toDate === 'function') {
    return data.toDate().toISOString();
  }
  if (Array.isArray(data)) return data.map(serialize);
  const out = {};
  for (const [k, v] of Object.entries(data)) {
    out[k] = serialize(v);
  }
  return out;
}

function saveDoc(filePath, docId, data) {
  ensureDir(path.dirname(filePath));
  const payload = { _id: docId, ...serialize(data) };
  fs.writeFileSync(filePath, JSON.stringify(payload, null, 2), 'utf8');
}

// ─── Recursive backup ────────────────────────────────────────────────────────

async function backupCollection(colRef, outputDir, depth = 0) {
  const indent = '  '.repeat(depth);
  const colName = colRef.id;
  totalCols++;

  process.stdout.write(`${indent}📂 /${colName} … `);

  let snapshot;
  try {
    snapshot = await colRef.get();
  } catch (err) {
    console.log(`\n${indent}   ⚠️  Could not read /${colName}: ${err.message}`);
    return;
  }

  if (snapshot.empty) {
    console.log('(empty)');
    return;
  }

  console.log(`${snapshot.size} docs`);
  ensureDir(outputDir);

  for (const doc of snapshot.docs) {
    const docDir  = path.join(outputDir, doc.id);
    const docFile = path.join(outputDir, `${doc.id}.json`);

    saveDoc(docFile, doc.id, doc.data());
    totalDocs++;

    // Recurse into subcollections.
    let subCols;
    try {
      subCols = await doc.ref.listCollections();
    } catch {
      subCols = [];
    }
    for (const subCol of subCols) {
      await backupCollection(subCol, path.join(docDir, subCol.id), depth + 1);
    }
  }
}

// ─── Main ────────────────────────────────────────────────────────────────────

async function main() {
  console.log('');
  console.log('╔══════════════════════════════════════╗');
  console.log('║     FIRESTORE BACKUP STARTED         ║');
  console.log(`║     ${TIMESTAMP}     ║`);
  console.log('╚══════════════════════════════════════╝');
  console.log(`Output → ${BACKUP_ROOT}\n`);

  ensureDir(BACKUP_ROOT);

  const rootCols = await db.listCollections();
  if (rootCols.length === 0) {
    console.log('No collections found in Firestore.');
    return;
  }

  for (const col of rootCols) {
    await backupCollection(col, path.join(BACKUP_ROOT, col.id));
  }

  console.log('');
  console.log('╔══════════════════════════════════════╗');
  console.log('║     FIRESTORE BACKUP COMPLETE        ║');
  console.log(`║  Collections : ${String(totalCols).padStart(6)}                ║`);
  console.log(`║  Documents   : ${String(totalDocs).padStart(6)}                ║`);
  console.log('╚══════════════════════════════════════╝');
  console.log(`\nFiles saved to: ${BACKUP_ROOT}`);
}

main().catch((err) => {
  console.error('\n❌  Fatal error:', err.message);
  process.exit(1);
});
