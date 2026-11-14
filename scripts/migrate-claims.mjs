#!/usr/bin/env node
// Migrates legacy item claims ({ claimedBy, claimedAt }) to the multi-claim
// shape ({ claims: { uid: Timestamp }, claimLimit: 1 }) once. Legacy keys are
// deleted; an item with a claims map is never re-claimed. Only a missing or
// invalid limit and leftover legacy keys are written for it, and a map with
// several claims and no integer limit stops the run. A rerun writes only the
// remainder. Dry run unless --yes; the default target is staging. See
// docs/migration-runbook.md for the export, freeze and rollback runbook.

import { readFileSync } from 'node:fs';

import { cert, initializeApp } from 'firebase-admin/app';
import {
  FieldValue,
  Timestamp,
  getFirestore,
} from 'firebase-admin/firestore';

import { isEntryPoint } from './module-entry.mjs';
import { STAGING_DATABASE, isNamedDatabaseId } from './staging-config.mjs';

export const PROJECT_ID = 'wish-together-project';
const PRODUCTION_DATABASE = '(default)';
const BATCH_SIZE = 400;
const PREVIEW_COUNT = 10;

const USAGE = `Usage: npm run migrate:claims -- [options]

  (no flags)          dry run against staging; writes nothing
  --yes               perform the migration
  --verify            read again and report problems; exits 1 on any
  --limit <n>         stop after n scanned items, for a canary run
  --database <id>     a named database, or "(default)" (default "staging")
  --print-target      print the resolved database and exit
  --help              print this message

Requires GOOGLE_APPLICATION_CREDENTIALS for ${PROJECT_ID}. An item that already
has a claims map is not re-claimed; a multi-claim map without an integer limit
stops the run.`;

/// A mistake in how the command was invoked. The CLI maps it to exit 2.
class UsageError extends Error {}

function requireValue(argv, index, flag) {
  const value = argv[index];
  if (!value || value.startsWith('--')) {
    throw new UsageError(`${flag} needs a value`);
  }
  return value;
}

function validateDatabaseId(raw) {
  const id = String(raw ?? '').trim();
  if (id === PRODUCTION_DATABASE) {
    return id;
  }
  if (!isNamedDatabaseId(id)) {
    throw new UsageError(
      `Invalid --database ${JSON.stringify(id)}: expected a named database id, e.g. "staging", or "${PRODUCTION_DATABASE}".`,
    );
  }
  return id;
}

function validateLimit(raw) {
  const value = String(raw ?? '');
  if (!/^[1-9]\d*$/.test(value) || Number(value) > 2_147_483_647) {
    throw new UsageError(
      `Invalid --limit ${JSON.stringify(raw)}: expected a positive integer`,
    );
  }
  return Number(value);
}

export function parseArgs(argv) {
  const options = {
    databaseId: STAGING_DATABASE,
    yes: false,
    verify: false,
    printTarget: false,
    help: false,
    limit: null,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (!arg.startsWith('--')) {
      throw new UsageError(`Unexpected argument ${JSON.stringify(arg)}`);
    }
    const equals = arg.indexOf('=');
    const name = equals === -1 ? arg : arg.slice(0, equals);
    const inline = equals === -1 ? null : arg.slice(equals + 1);
    switch (name) {
      case '--database': {
        const value =
          inline === null ? requireValue(argv, (index += 1), name) : inline;
        options.databaseId = validateDatabaseId(value);
        break;
      }
      case '--limit': {
        const value =
          inline === null ? requireValue(argv, (index += 1), name) : inline;
        options.limit = validateLimit(value);
        break;
      }
      case '--yes':
      case '--verify':
      case '--print-target':
      case '--help':
        if (inline !== null) {
          throw new UsageError(`${name} does not take a value`);
        }
        if (name === '--yes') options.yes = true;
        if (name === '--verify') options.verify = true;
        if (name === '--print-target') options.printTarget = true;
        if (name === '--help') options.help = true;
        break;
      default:
        throw new UsageError(`Unknown option ${name}`);
    }
  }

  if (options.verify && options.limit !== null) {
    throw new UsageError(
      '--limit cannot be combined with --verify; a partial check is not a check',
    );
  }
  if (options.verify && options.yes) {
    throw new UsageError('--yes cannot be combined with --verify');
  }
  if (options.verify && options.printTarget) {
    throw new UsageError('--print-target cannot be combined with --verify');
  }
  return options;
}

function resolveMode(options) {
  if (options.help) return 'help';
  if (options.printTarget) return 'print-target';
  if (options.verify) return 'verify';
  return options.yes ? 'apply' : 'dry-run';
}

/// The service-account credentials for this project, or a refusal that names
/// what is wrong. Nothing is read at import time.
function requireCredentials(env = process.env) {
  const path = env.GOOGLE_APPLICATION_CREDENTIALS;
  if (!path) {
    throw new UsageError(
      'Set GOOGLE_APPLICATION_CREDENTIALS to a Firebase service-account JSON.',
    );
  }
  let credentials;
  try {
    credentials = JSON.parse(readFileSync(path, 'utf8'));
  } catch (error) {
    throw new UsageError(`Cannot read "${path}": ${error.message}`);
  }
  if (!isPlainObject(credentials)) {
    throw new UsageError(`"${path}" is not a service-account key.`);
  }
  if (credentials.project_id !== PROJECT_ID) {
    throw new UsageError(
      `Refusing to run: "${path}" belongs to project "${credentials.project_id}", expected "${PROJECT_ID}".`,
    );
  }
  if (
    credentials.type !== 'service_account' ||
    typeof credentials.private_key !== 'string' ||
    typeof credentials.client_email !== 'string'
  ) {
    throw new UsageError(`"${path}" is not a service-account key.`);
  }
  return credentials;
}

function openDatabase({ credentials, databaseId }) {
  const app = initializeApp({
    credential: cert(credentials),
    projectId: PROJECT_ID,
  });
  const db = getFirestore(app, databaseId);
  db.settings({ ignoreUndefinedProperties: true });
  return db;
}

function isPlainObject(value) {
  if (value === null || typeof value !== 'object') {
    return false;
  }
  const prototype = Object.getPrototypeOf(value);
  return prototype === Object.prototype || prototype === null;
}

/// The fields to write for one item, legacy or already migrated, or null when
/// there is nothing to write. A missing or invalid limit is repaired to 1 and an
/// existing valid one is kept. A claimed uid without a usable timestamp is
/// repaired with [now].
export function planItem(data, now = Timestamp.now()) {
  if (isPlainObject(data.claims)) {
    // Already migrated. A missing or invalid limit, or leftover legacy keys, is
    // written so a rerun converges instead of leaving verify to report it. A
    // legacy claim beside a claims map is stale and deleted; the freeze makes
    // that unreachable, because no writer can add one after the backfill starts.
    const claimCount = Object.keys(data.claims).length;
    const validLimit =
      Number.isInteger(data.claimLimit) && data.claimLimit >= 0;
    if (!validLimit && claimCount > 1) {
      throw new Error('claims map has several claims but needs an integer claimLimit');
    }
    const cleanup = {};
    if (!validLimit) {
      cleanup.claimLimit = 1;
    }
    if (Object.hasOwn(data, 'claimedBy')) {
      cleanup.claimedBy = FieldValue.delete();
    }
    if (Object.hasOwn(data, 'claimedAt')) {
      cleanup.claimedAt = FieldValue.delete();
    }
    return Object.keys(cleanup).length > 0 ? cleanup : null;
  }
  if (data.claims !== undefined && data.claims !== null) {
    throw new Error('claims is not a map');
  }
  if (
    data.claimedBy !== undefined &&
    data.claimedBy !== null &&
    (typeof data.claimedBy !== 'string' || data.claimedBy === '')
  ) {
    throw new Error('claimedBy is not a non-empty string');
  }
  const claimedAt = data.claimedAt instanceof Timestamp ? data.claimedAt : now;
  const claims = data.claimedBy ? { [data.claimedBy]: claimedAt } : {};
  const validLimit = Number.isInteger(data.claimLimit) && data.claimLimit >= 0;
  return {
    claims,
    claimLimit: validLimit ? data.claimLimit : 1,
    claimedBy: FieldValue.delete(),
    claimedAt: FieldValue.delete(),
  };
}

/// The problems that make one item unreadable after the migration. The caller
/// prefixes each with the document path.
export function verifyItem(data) {
  const problems = [];
  if (data.claims === undefined) {
    problems.push('missing claims map');
  } else if (!isPlainObject(data.claims)) {
    problems.push('claims is not a map');
  } else {
    for (const [uid, value] of Object.entries(data.claims)) {
      if (!(value instanceof Timestamp)) {
        problems.push(`invalid claim timestamp for ${uid}`);
      }
    }
  }
  if (data.claimLimit === undefined) {
    problems.push('missing claimLimit');
  } else if (!Number.isInteger(data.claimLimit) || data.claimLimit < 0) {
    problems.push(`invalid claimLimit ${String(data.claimLimit)}`);
  } else if (
    isPlainObject(data.claims) &&
    data.claimLimit > 0 &&
    Object.keys(data.claims).length > data.claimLimit
  ) {
    problems.push(`claims exceed claimLimit ${data.claimLimit}`);
  }
  if (Object.hasOwn(data, 'claimedBy')) {
    problems.push('leftover claimedBy');
  }
  if (Object.hasOwn(data, 'claimedAt')) {
    problems.push('leftover claimedAt');
  }
  return problems;
}

/// Scans every item in every wishlist and applies, verifies or previews the
/// migration. The db is injectable so the tests need no Firestore.
export async function runClaims({
  db,
  mode,
  limit = null,
  log = console,
}) {
  const now = Timestamp.now();
  if (!['dry-run', 'apply', 'verify'].includes(mode)) {
    throw new Error(`Unknown mode ${JSON.stringify(mode)}`);
  }
  if (mode === 'verify' && limit !== null) {
    throw new Error('limit cannot be combined with verify');
  }
  const result = {
    scanned: 0,
    skipped: 0,
    planned: 0,
    written: 0,
    problems: [],
  };
  const query = db.collectionGroup('items');
  const snapshot = await (limit === null ? query.get() : query.limit(limit).get());

  if (mode === 'verify') {
    for (const doc of snapshot.docs) {
      result.scanned += 1;
      for (const problem of verifyItem(doc.data())) {
        result.problems.push(`${doc.ref.path}: ${problem}`);
      }
    }
    return result;
  }

  const planned = [];
  let previewed = 0;
  for (const doc of snapshot.docs) {
    if (limit !== null && result.scanned >= limit) {
      break;
    }
    result.scanned += 1;
    let fields;
    try {
      fields = planItem(doc.data(), now);
    } catch (error) {
      throw new Error(`${doc.ref.path}: ${error.message}`);
    }
    if (fields === null) {
      result.skipped += 1;
      continue;
    }
    result.planned += 1;
    if (mode !== 'dry-run') {
      planned.push({ ref: doc.ref, fields });
    }
    if (mode === 'dry-run' && previewed < PREVIEW_COUNT) {
      log.log(`would update ${doc.ref.path}`);
      previewed += 1;
    }
  }

  if (mode === 'dry-run') {
    return result;
  }

  for (let start = 0; start < planned.length; start += BATCH_SIZE) {
    const chunk = planned.slice(start, start + BATCH_SIZE);
    try {
      const batch = db.batch();
      for (const entry of chunk) {
        batch.update(entry.ref, entry.fields);
      }
      await batch.commit();
    } catch (error) {
      log.error(
        `Batch failed after ${result.written} of ${planned.length} items: ${error.message}`,
      );
      return { ...result, failed: true };
    }
    result.written += chunk.length;
  }
  return result;
}

/// The command, with its collaborators injectable so the tests need neither
/// credentials nor a database.
export async function main(
  argv = process.argv.slice(2),
  {
    env = process.env,
    credentials = requireCredentials,
    openDb = openDatabase,
    log = console,
  } = {},
) {
  let options;
  let mode;
  try {
    options = parseArgs(argv);
    mode = resolveMode(options);
  } catch (error) {
    if (error instanceof UsageError) {
      log.error(error.message);
      log.error(USAGE);
      return 2;
    }
    throw error;
  }

  if (mode === 'help') {
    log.log(USAGE);
    return 0;
  }
  if (mode === 'print-target') {
    log.log(options.databaseId);
    return 0;
  }

  try {
    log.log(`Target: ${PROJECT_ID}/${options.databaseId} (${mode})`);
    if (options.databaseId === PRODUCTION_DATABASE) {
      log.warn(
        'Target is the PRODUCTION database. Pass --database staging to rehearse.',
      );
    }

    const db = openDb({
      credentials: credentials(env),
      databaseId: options.databaseId,
    });
    const result = await runClaims({
      db,
      mode,
      limit: options.limit,
      log,
    });

    if (result.scanned === 0) {
      log.warn('No items found; check --database and the items collection.');
    }
    if (mode === 'verify') {
      for (const problem of result.problems) {
        log.error(problem);
      }
      log.log(
        `Scanned ${result.scanned} item(s); ${result.problems.length} problem(s).`,
      );
      return result.problems.length > 0 || result.scanned === 0 ? 1 : 0;
    }

    const limited = options.limit === null ? '' : ` (limited to ${options.limit})`;
    log.log(
      `Scanned ${result.scanned} item(s), planned ${result.planned}, skipped ${result.skipped}, wrote ${result.written}${limited}.`,
    );
    return result.failed || result.scanned === 0 ? 1 : 0;
  } catch (error) {
    if (error instanceof UsageError) {
      log.error(error.message);
      return 2;
    }
    log.error(error.message ?? String(error));
    return 1;
  }
}

if (isEntryPoint(import.meta.url)) {
  process.exitCode = await main();
}
