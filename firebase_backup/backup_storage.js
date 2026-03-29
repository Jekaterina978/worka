'use strict';

/**
 * backup_storage.js
 * Downloads ALL files from Firebase Storage, preserving the folder structure.
 *
 * Output:
 *   backup/storage/<original/path/in/bucket/file.ext>
 *
 * Large files are streamed — no memory issues.
 */

const admin = require('firebase-admin');
const fs    = require('fs');
const path  = require('path');

// ─── Init ────────────────────────────────────────────────────────────────────

const SA_PATH     = path.resolve(__dirname, 'serviceAccountKey.json');
const BACKUP_ROOT = path.resolve(__dirname, 'backup', 'storage');
const TIMESTAMP   = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);

if (!fs.existsSync(SA_PATH)) {
  console.error('❌  serviceAccountKey.json not found.');
  process.exit(1);
}

const sa = JSON.parse(fs.readFileSync(SA_PATH, 'utf8'));
if (sa._PLACEHOLDER) {
  console.error('❌  serviceAccountKey.json is still a placeholder. Replace it with your real key.');
  process.exit(1);
}

// storageBucket is required — read from the service account project_id.
const PROJECT_ID    = sa.project_id;
const STORAGE_BUCKET = `${PROJECT_ID}.appspot.com`;

const allowProd = process.argv.includes('--allow-prod');
if (!PROJECT_ID) {
  console.error('❌ Cannot determine projectId from service account. Aborting.');
  process.exit(1);
}
if (PROJECT_ID === 'worka-416c0' && !allowProd) {
  console.error('❌ Refusing to run backup against production project worka-416c0 without --allow-prod');
  process.exit(1);
}

admin.initializeApp({
  credential: admin.credential.cert(sa),
  storageBucket: STORAGE_BUCKET,
});

console.log('[env]', { projectId: PROJECT_ID, serviceAccountEmail: sa.client_email || 'n/a', allowProd });

const bucket = admin.storage().bucket();

// ─── Stats ───────────────────────────────────────────────────────────────────

let totalFiles   = 0;
let totalBytes   = 0;
let skippedFiles = 0;

// ─── Helpers ─────────────────────────────────────────────────────────────────

function ensureDir(dir) {
  fs.mkdirSync(dir, { recursive: true });
}

function formatBytes(bytes) {
  if (bytes < 1024)        return `${bytes} B`;
  if (bytes < 1024 ** 2)   return `${(bytes / 1024).toFixed(1)} KB`;
  if (bytes < 1024 ** 3)   return `${(bytes / 1024 ** 2).toFixed(1)} MB`;
  return `${(bytes / 1024 ** 3).toFixed(2)} GB`;
}

/**
 * Downloads a single Storage file, streaming directly to disk.
 */
async function downloadFile(file) {
  const remotePath = file.name;

  // Skip "folder placeholder" objects (end with '/')
  if (remotePath.endsWith('/')) {
    skippedFiles++;
    return;
  }

  const localPath = path.join(BACKUP_ROOT, remotePath);
  ensureDir(path.dirname(localPath));

  const metadata = file.metadata || {};
  const sizeBytes = parseInt(metadata.size || '0', 10);

  return new Promise((resolve, reject) => {
    const writeStream = fs.createWriteStream(localPath);
    const readStream  = file.createReadStream();

    readStream.on('error', reject);
    writeStream.on('error', reject);
    writeStream.on('finish', () => {
      totalFiles++;
      totalBytes += sizeBytes;
      resolve();
    });

    readStream.pipe(writeStream);
  });
}

// ─── List all files (handles pagination automatically) ───────────────────────

async function listAllFiles() {
  const allFiles = [];
  let pageToken;

  do {
    const options = { maxResults: 1000 };
    if (pageToken) options.pageToken = pageToken;

    const [files, , response] = await bucket.getFiles(options);
    allFiles.push(...files);
    pageToken = response && response.nextPageToken;
  } while (pageToken);

  return allFiles;
}

// ─── Main ────────────────────────────────────────────────────────────────────

async function main() {
  console.log('');
  console.log('╔══════════════════════════════════════╗');
  console.log('║     STORAGE BACKUP STARTED           ║');
  console.log(`║     ${TIMESTAMP}     ║`);
  console.log('╚══════════════════════════════════════╝');
  console.log(`Bucket → gs://${STORAGE_BUCKET}`);
  console.log(`Output → ${BACKUP_ROOT}\n`);

  ensureDir(BACKUP_ROOT);

  console.log('Listing all files in Storage …');
  let files;
  try {
    files = await listAllFiles();
  } catch (err) {
    console.error('❌  Failed to list files:', err.message);
    console.error('   Make sure your service account has Storage Object Viewer role.');
    process.exit(1);
  }

  if (files.length === 0) {
    console.log('Storage bucket is empty — nothing to backup.');
    return;
  }

  console.log(`Found ${files.length} objects. Starting download …\n`);

  const CONCURRENCY = 5; // parallel downloads
  let index = 0;

  async function worker() {
    while (index < files.length) {
      const file = files[index++];
      const num  = String(totalFiles + skippedFiles + 1).padStart(
        String(files.length).length, ' '
      );
      process.stdout.write(`  [${num}/${files.length}] ${file.name} … `);

      try {
        await downloadFile(file);
        if (file.name.endsWith('/')) {
          console.log('(folder placeholder, skipped)');
        } else {
          const meta = file.metadata || {};
          console.log(`✓  ${formatBytes(parseInt(meta.size || '0', 10))}`);
        }
      } catch (err) {
        console.log(`\n    ⚠️  Failed: ${err.message}`);
        skippedFiles++;
      }
    }
  }

  // Run N workers in parallel.
  await Promise.all(Array.from({ length: CONCURRENCY }, worker));

  console.log('');
  console.log('╔══════════════════════════════════════╗');
  console.log('║     STORAGE BACKUP COMPLETE          ║');
  console.log(`║  Files       : ${String(totalFiles).padStart(6)}                ║`);
  console.log(`║  Total size  : ${formatBytes(totalBytes).padStart(6)}                ║`);
  if (skippedFiles > 0) {
    console.log(`║  Skipped     : ${String(skippedFiles).padStart(6)}                ║`);
  }
  console.log('╚══════════════════════════════════════╝');
  console.log(`\nFiles saved to: ${BACKUP_ROOT}`);
}

main().catch((err) => {
  console.error('\n❌  Fatal error:', err.message);
  process.exit(1);
});
