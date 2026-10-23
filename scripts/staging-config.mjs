#!/usr/bin/env node
// Validates the staging environment definition before anything is deployed.
//
// The deploy job runs this against the downloaded artifacts (never against the
// candidate checkout), so a config that was valid in the build job is checked
// again immediately before it is used. Every check here is a production guard:
// the staging deploy must never name `(default)`, an unexpected site, or a
// `predeploy`/`postdeploy` hook (firebase deploy executes those in the
// credential-holding job).
//
// Usage: node staging-config.mjs firebase.staging.json
//
// Prints the database id on success; exits non-zero on any mismatch.

import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

export const STAGING_DATABASE = 'staging';
export const STAGING_SITE = 'wish-together-staging';
export const STAGING_PUBLIC_DIR = 'build/web';
export const TESTED_RULES = 'firestore.rules';

/// Firestore named database ids are lowercase, 4-63 characters.
const namedDatabaseId = /^[a-z][a-z0-9-]{3,62}$/;

/// Whether [value] is a valid Firestore named database id.
export function isNamedDatabaseId(value) {
  return typeof value === 'string' && namedDatabaseId.test(value);
}

/// The staging environment uses no composite indexes today. If it gains one,
/// add `indexes` here, ship the file, and deploy `firestore:indexes` too.
const ROOT_KEYS = new Set(['hosting', 'firestore']);
const HOSTING_KEYS = new Set([
  'site',
  'public',
  'ignore',
  'rewrites',
  'headers',
]);
const FIRESTORE_KEYS = new Set(['database', 'rules']);

function fail(message) {
  throw new Error(message);
}

function rejectUnknownKeys(value, allowed, label) {
  for (const key of Object.keys(value ?? {})) {
    if (!allowed.has(key)) {
      fail(`${label} must not define "${key}"`);
    }
  }
}

export function validateStagingConfig(
  config,
  { database = STAGING_DATABASE, site = STAGING_SITE } = {},
) {
  rejectUnknownKeys(config, ROOT_KEYS, 'firebase.staging.json');

  const firestore = config?.firestore ?? {};
  const hosting = config?.hosting ?? {};
  rejectUnknownKeys(firestore, FIRESTORE_KEYS, 'firestore');
  rejectUnknownKeys(hosting, HOSTING_KEYS, 'hosting');

  // A rewrite may only serve static files; a function/run rewrite could point
  // at another service in the project.
  for (const rewrite of hosting.rewrites ?? []) {
    rejectUnknownKeys(rewrite, new Set(['source', 'destination']), 'rewrites');
  }

  const actualDatabase =
    typeof firestore.database === 'string' ? firestore.database : '';
  if (!isNamedDatabaseId(actualDatabase)) {
    fail(
      `firebase.staging.json must name a lowercase Firestore database id, got ${JSON.stringify(actualDatabase)}`,
    );
  }
  if (actualDatabase !== database) {
    fail(
      `firebase.staging.json must target the "${database}" database, got ${JSON.stringify(actualDatabase)}`,
    );
  }
  if (firestore.rules !== TESTED_RULES) {
    fail(
      `firebase.staging.json must deploy the tested ${TESTED_RULES}, got ${JSON.stringify(firestore.rules)}`,
    );
  }
  if (hosting.site !== site) {
    fail(
      `firebase.staging.json must deploy the "${site}" Hosting site, got ${JSON.stringify(hosting.site)}`,
    );
  }
  if (hosting.public !== STAGING_PUBLIC_DIR) {
    fail(
      `firebase.staging.json must publish only ${STAGING_PUBLIC_DIR}, got ${JSON.stringify(hosting.public)}`,
    );
  }

  return { database: actualDatabase, site: hosting.site };
}

function main(argv = process.argv.slice(2)) {
  const path = argv[0] ?? 'firebase.staging.json';
  const config = JSON.parse(readFileSync(path, 'utf8'));
  const result = validateStagingConfig(config);
  console.log(result.database);
}

if (
  process.argv[1] &&
  import.meta.url === pathToFileURL(process.argv[1]).href
) {
  try {
    main();
  } catch (error) {
    console.error(error.message ?? error);
    process.exitCode = 1;
  }
}
