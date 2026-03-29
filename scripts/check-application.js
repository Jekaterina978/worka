#!/usr/bin/env node
/**
 * Temporary helper to inspect applications by job_code.
 * Usage: ensure DATABASE_URL (or PG_CONNECTION_STRING) is set in .env
 */
require('dotenv').config();

const { Pool } = require('pg');

const connectionString =
  process.env.PG_CONNECTION_STRING ||
  process.env.DATABASE_URL;

if (!connectionString) {
  console.error('Missing DATABASE_URL or PG_CONNECTION_STRING in env');
  process.exit(1);
}

const pool = new Pool({ connectionString });

const JOB_CODE = '1774432746535';
const sql =
  'SELECT * FROM applications WHERE job_code = $1 ORDER BY created_at DESC LIMIT 10';

(async () => {
  try {
    const { rows } = await pool.query(sql, [JOB_CODE]);
    console.log(`Rows for job_code=${JOB_CODE}:`);
    console.dir(rows, { depth: null, colors: true });
  } catch (err) {
    console.error('Query failed:', err);
    process.exitCode = 1;
  } finally {
    await pool.end();
  }
})();

