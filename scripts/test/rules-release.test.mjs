import assert from 'node:assert/strict';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';

import {
  DEFAULT_PROJECT_ID,
  main,
  normalizeRulesSource,
  parseArgs,
  releaseName,
  releaseRulesetId,
  requestHeaders,
  rulesSourceFromRuleset,
  sourcesMatch,
} from '../rules-release.mjs';

test('releaseName targets the default database without a suffix', () => {
  assert.equal(
    releaseName('wish-together-project', '(default)'),
    'projects/wish-together-project/releases/cloud.firestore',
  );
});

test('releaseName targets a named database with its id as the suffix', () => {
  assert.equal(
    releaseName('wish-together-project', 'staging'),
    'projects/wish-together-project/releases/cloud.firestore/staging',
  );
});

test('releaseName rejects an empty database id', () => {
  assert.throws(() => releaseName('wish-together-project', ''), /database id required/);
});

test('releaseRulesetId extracts the ruleset id from a resource name', () => {
  assert.equal(
    releaseRulesetId({
      rulesetName: 'projects/wish-together-project/rulesets/abc-123',
    }),
    'abc-123',
  );
});

test('normalizeRulesSource ignores CRLF and trailing whitespace', () => {
  assert.equal(normalizeRulesSource('rules {\r\n  allow read: true;  \r\n}'), 'rules {\n  allow read: true;\n}');
});

test('rulesSourceFromRuleset joins every source file', () => {
  const ruleset = {
    source: { files: [{ content: 'first' }, { content: 'second' }] },
  };

  assert.equal(rulesSourceFromRuleset(ruleset), 'first\nsecond');
});

test('sourcesMatch compares normalized sources', () => {
  assert.equal(sourcesMatch('allow read;  \n', 'allow read;\r\n'), true);
  assert.equal(sourcesMatch('allow read;', 'allow write;'), false);
});

test('parseArgs accepts an explicit database for show', () => {
  assert.deepEqual(parseArgs(['show', '--database', 'staging']), {
    command: 'show',
    project: DEFAULT_PROJECT_ID,
    database: 'staging',
    source: null,
    expectRuleset: null,
    json: false,
  });
});

test('parseArgs requires a database for show and check', () => {
  assert.throws(() => parseArgs(['show']), /show needs --database/);
  assert.throws(
    () => parseArgs(['check', '--source', 'firestore.rules']),
    /check needs --database/,
  );
});

test('parseArgs accepts check flags', () => {
  assert.deepEqual(
    parseArgs([
      'check',
      '--project',
      'other-project',
      '--database',
      '(default)',
      '--source',
      'firestore.rules',
      '--expect-ruleset',
      'abc-123',
    ]),
    {
      command: 'check',
      project: 'other-project',
      database: '(default)',
      source: 'firestore.rules',
      expectRuleset: 'abc-123',
      json: false,
    },
  );
});

test('parseArgs rejects a check without a verification target', () => {
  assert.throws(
    () => parseArgs(['check', '--database', 'staging']),
    /--source and\/or --expect-ruleset/,
  );
});

test('parseArgs rejects an unknown option', () => {
  assert.throws(() => parseArgs(['show', '--wat']), /Unknown option/);
});

test('parseArgs rejects a flag without a value', () => {
  assert.throws(() => parseArgs(['show', '--database']), /needs a value/);
});

test('parseArgs rejects check-only flags on show', () => {
  assert.throws(
    () =>
      parseArgs(['show', '--database', 'staging', '--source', 'firestore.rules']),
    /show does not accept/,
  );
});

test('parseArgs rejects --json on check', () => {
  assert.throws(
    () =>
      parseArgs([
        'check',
        '--database',
        'staging',
        '--expect-ruleset',
        'live',
        '--json',
      ]),
    /check does not accept --json/,
  );
});

// --- Fail-closed CLI behavior -------------------------------------------------

function stubFetch(t, respond) {
  const originalToken = process.env.ACCESS_TOKEN;
  const urls = [];
  t.mock.method(globalThis, 'fetch', async (url) => {
    urls.push(String(url));
    return respond(String(url));
  });
  process.env.ACCESS_TOKEN = 'test-token';
  const errorMock = t.mock.method(console, 'error', () => {});
  t.mock.method(console, 'log', () => {});
  t.after(() => {
    if (originalToken === undefined) {
      delete process.env.ACCESS_TOKEN;
    } else {
      process.env.ACCESS_TOKEN = originalToken;
    }
  });
  return { urls, errorMock };
}

const release = (rulesetName) => ({
  name: 'projects/wish-together-project/releases/cloud.firestore/staging',
  rulesetName,
});

test('a missing release fails with the deploy-first message', async (t) => {
  stubFetch(t, () => new Response('not found', { status: 404 }));

  await assert.rejects(
    () => main(['show', '--database', 'staging']),
    /No Firestore rules release/,
  );
});

test('an API error is not reported as a missing release', async (t) => {
  stubFetch(t, () => new Response('boom', { status: 500 }));

  await assert.rejects(() => main(['show', '--database', 'staging']), (error) => {
    assert.match(error.message, /500/);
    assert.doesNotMatch(error.message, /No Firestore rules release/);
    return true;
  });
});

test('a release without a ruleset id fails closed', async (t) => {
  stubFetch(
    t,
    () =>
      new Response(
        JSON.stringify({ name: 'projects/p/releases/cloud.firestore/staging' }),
        { status: 200 },
      ),
  );

  await assert.rejects(
    () => main(['show', '--database', 'staging']),
    /has no ruleset id/,
  );
});

test('a mismatched expected ruleset returns non-zero', async (t) => {
  stubFetch(
    t,
    () =>
      new Response(
        JSON.stringify(release('projects/p/rulesets/live')),
        { status: 200 },
      ),
  );

  const exitCode = await main([
    'check',
    '--database',
    '(default)',
    '--expect-ruleset',
    'other',
  ]);

  assert.equal(exitCode, 1);
});

test('a matching expected ruleset returns zero', async (t) => {
  stubFetch(
    t,
    () =>
      new Response(
        JSON.stringify(release('projects/p/rulesets/live')),
        { status: 200 },
      ),
  );

  const exitCode = await main([
    'check',
    '--database',
    '(default)',
    '--expect-ruleset',
    'live',
  ]);

  assert.equal(exitCode, 0);
});

test('check --source returns zero when the live source matches', async (t) => {
  const dir = mkdtempSync(join(tmpdir(), 'wt-rules-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const sourcePath = join(dir, 'firestore.rules');
  writeFileSync(sourcePath, 'rules {\n  allow read;\n}\n');
  const { urls } = stubFetch(t, (url) => {
    if (url.includes('/rulesets/')) {
      return new Response(
        JSON.stringify({
          source: { files: [{ content: 'rules {\r\n  allow read;  \r\n}' }] },
        }),
        { status: 200 },
      );
    }
    return new Response(JSON.stringify(release('projects/p/rulesets/live')), {
      status: 200,
    });
  });

  const exitCode = await main([
    'check',
    '--database',
    'staging',
    '--source',
    sourcePath,
  ]);

  assert.equal(exitCode, 0);
  assert.equal(urls.length, 2);
  assert.match(urls[0], /releases\/cloud\.firestore\/staging$/);
  assert.match(urls[1], /rulesets\/live$/);
});

test('check --source reports a live-source mismatch', async (t) => {
  const dir = mkdtempSync(join(tmpdir(), 'wt-rules-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const sourcePath = join(dir, 'firestore.rules');
  writeFileSync(sourcePath, 'rules { allow read; }');
  const { errorMock } = stubFetch(t, (url) => {
    if (url.includes('/rulesets/')) {
      return new Response(
        JSON.stringify({
          source: { files: [{ content: 'rules { allow write; }' }] },
        }),
        { status: 200 },
      );
    }
    return new Response(JSON.stringify(release('projects/p/rulesets/live')), {
      status: 200,
    });
  });

  const exitCode = await main([
    'check',
    '--database',
    'staging',
    '--source',
    sourcePath,
  ]);

  assert.equal(exitCode, 1);
  assert.ok(
    errorMock.mock.calls.some((call) =>
      String(call.arguments[0]).includes('Source mismatch'),
    ),
  );
});

test('a missing live ruleset rejects instead of passing', async (t) => {
  const dir = mkdtempSync(join(tmpdir(), 'wt-rules-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const sourcePath = join(dir, 'firestore.rules');
  writeFileSync(sourcePath, 'rules { allow read; }');
  stubFetch(t, (url) => {
    if (url.includes('/rulesets/')) {
      return new Response('not found', { status: 404 });
    }
    return new Response(JSON.stringify(release('projects/p/rulesets/live')), {
      status: 200,
    });
  });

  await assert.rejects(
    () =>
      main(['check', '--database', 'staging', '--source', sourcePath]),
    /404/,
  );
});

test('user tokens send the quota-project header', () => {
  const headers = requestHeaders('test-token', 'wish-together-project', {
    userToken: true,
  });

  assert.equal(headers.Authorization, 'Bearer test-token');
  assert.equal(headers['x-goog-user-project'], 'wish-together-project');
});

test('service-account tokens do not send the quota-project header', () => {
  const headers = requestHeaders('test-token', 'wish-together-project', {
    userToken: false,
  });

  assert.equal(headers.Authorization, 'Bearer test-token');
  assert.equal(headers['x-goog-user-project'], undefined);
});

test('the default header shape is the service-account one', (t) => {
  const saved = process.env.ACCESS_TOKEN;
  delete process.env.ACCESS_TOKEN;
  t.after(() => {
    if (saved !== undefined) {
      process.env.ACCESS_TOKEN = saved;
    }
  });

  const headers = requestHeaders('test-token', 'wish-together-project');

  assert.equal(headers.Authorization, 'Bearer test-token');
  assert.equal(headers['x-goog-user-project'], undefined);
});
