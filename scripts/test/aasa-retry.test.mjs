import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import {
  chmodSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = fileURLToPath(new URL('../..', import.meta.url));
const COMMITTED = readFileSync(
  new URL('../../web/.well-known/apple-app-site-association', import.meta.url),
  'utf8',
);
// Same document, different bytes: only normalised equality may accept it.
const RESERIALISED = JSON.stringify(JSON.parse(COMMITTED), null, 4);
const OTHER = JSON.stringify({ applinks: { apps: [], details: [] } });

/**
 * Pull the `run: |` body out of a named step, so the tests exercise the real
 * workflow text instead of a copy that can drift from it.
 */
function stepScript(workflow, stepName) {
  const file = join(ROOT, '.github', 'workflows', workflow);
  const lines = readFileSync(file, 'utf8').split('\n');
  const step = lines.findIndex((l) => l.trim() === `- name: ${stepName}`);
  assert.notEqual(step, -1, `step not found in ${workflow}: ${stepName}`);
  const run = lines.findIndex((l, n) => n > step && l.trim() === 'run: |');
  assert.notEqual(run, -1, `run block not found for ${stepName}`);
  const indent = lines[run].length - lines[run].trimStart().length;
  const body = [];
  for (const line of lines.slice(run + 1)) {
    if (line.trim() && line.length - line.trimStart().length <= indent) break;
    body.push(line.trim() ? line.slice(indent + 2) : '');
  }
  const script = body.join('\n');
  assert.match(script, /curl /, `extracted block looks wrong: ${stepName}`);
  return script;
}

const readNumber = (file) => {
  try {
    return Number(readFileSync(file, 'utf8').trim() || 0);
  } catch {
    return 0;
  }
};

const readLines = (file) => {
  try {
    return readFileSync(file, 'utf8').split('\n').filter(Boolean);
  } catch {
    return [];
  }
};

/**
 * Run one workflow block against a scripted sequence of curl attempts.
 * scenario: [{ rc, status, contentType, body }], one entry per curl call.
 * Bodies are base64-encoded so a multi-line document stays one scenario line.
 */
function runBlock({ workflow, stepName, scenario, expected = COMMITTED, expectedPath, url, t }) {
  const dir = mkdtempSync(join(tmpdir(), 'aasa-retry-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));

  const bin = join(dir, 'bin');
  mkdirSync(bin);
  if (expected !== null) {
    const expectedFile = join(dir, expectedPath);
    mkdirSync(dirname(expectedFile), { recursive: true });
    writeFileSync(expectedFile, expected);
  }

  const scenarioFile = join(dir, 'scenario');
  writeFileSync(
    scenarioFile,
    scenario
      .map((s) =>
        [
          s.rc ?? 0,
          s.status ?? 200,
          s.omitContentType ? '-' : (s.contentType ?? 'application/json'),
          Buffer.from(s.body ?? '').toString('base64'),
          s.extraContentType ?? '',
        ].join('|'),
      )
      .join('\n') + '\n',
  );
  const counter = join(dir, 'counter');
  const sleeps = join(dir, 'sleeps');
  const bounds = join(dir, 'bounds');
  const urls = join(dir, 'urls');

  writeFileSync(
    join(bin, 'curl'),
    `#!/usr/bin/env bash
set -u
n=$(( $(cat "$STUB_COUNTER" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$STUB_COUNTER"
line=$(sed -n "\${n}p" "$STUB_SCENARIO")
if [ -z "$line" ]; then echo "stub: scenario exhausted" >&2; exit 99; fi
IFS='|' read -r rc status ctype body64 extra <<< "$line"
connect=""; total=""; headers=""; bodypath=""
while [ $# -gt 0 ]; do
  case "$1" in
    --connect-timeout) connect="$2"; shift 2 ;;
    --max-time) total="$2"; shift 2 ;;
    -D) headers="$2"; shift 2 ;;
    -o) bodypath="$2"; shift 2 ;;
    -w|-H) shift 2 ;;
    -*) shift ;;
    *) printf '%s\n' "$1" >> "$STUB_URLS"; shift ;;
  esac
done
echo "$connect $total" >> "$STUB_BOUNDS"
: > "$headers"; : > "$bodypath"
if [ "\${rc:-}" != "0" ]; then
  echo "curl: (\${rc:-?}) scripted transport failure" >&2
  exit "\${rc:-1}"
fi
{
  printf 'HTTP/2 %s\\r\\n' "$status"
  [ "$ctype" != "-" ] && printf 'content-type: %s\\r\\n' "$ctype"
  [ -n "\${extra:-}" ] && printf 'content-type: %s\\r\\n' "$extra"
  printf '\\r\\n'
} > "$headers"
printf '%s' "$body64" | base64 -d > "$bodypath"
printf '%s' "$status"
`,
  );
  writeFileSync(join(bin, 'sleep'), '#!/usr/bin/env bash\necho "$1" >> "$STUB_SLEEPS"\n');
  chmodSync(join(bin, 'curl'), 0o755);
  chmodSync(join(bin, 'sleep'), 0o755);

  const result = spawnSync(
    'bash',
    ['--noprofile', '--norc', '-eo', 'pipefail', '-c', stepScript(workflow, stepName)],
    {
      cwd: dir,
      encoding: 'utf8',
      timeout: 60_000,
      env: {
        PATH: `${bin}:${process.env.PATH}`,
        HOME: process.env.HOME,
        RUNNER_TEMP: dir,
        STUB_SCENARIO: scenarioFile,
        STUB_COUNTER: counter,
        STUB_SLEEPS: sleeps,
        STUB_BOUNDS: bounds,
        STUB_URLS: urls,
        ...url,
      },
    },
  );
  assert.equal(result.signal, null, 'the step hung');

  return {
    status: result.status,
    output: `${result.stdout ?? ''}${result.stderr ?? ''}`,
    requests: readNumber(counter),
    sleeps: readLines(sleeps),
    urls: readLines(urls),
    bounds: readLines(bounds),
  };
}

const TARGETS = [
  {
    workflow: 'ci-web.yml',
    stepName: 'Verify the AASA on the preview',
    expectedPath: 'web/.well-known/apple-app-site-association',
    kind: 'committed',
    url: { PREVIEW_URL: 'https://preview.example/' },
    noSlashUrl: { PREVIEW_URL: 'https://preview.example' },
  },
  {
    workflow: 'deploy-staging.yml',
    stepName: 'Verify the staging AASA is served',
    expectedPath: 'staging/build/web/.well-known/apple-app-site-association',
    kind: 'built',
    url: { STAGING_URL: 'https://staging.example/' },
    noSlashUrl: { STAGING_URL: 'https://staging.example' },
  },
];

for (const target of TARGETS) {
  const run = (scenario, extra = {}) => runBlock({ ...target, scenario, ...extra });
  const repeat = (n, entry) => Array.from({ length: n }, () => entry);
  const ok = { status: 200, body: COMMITTED };
  const notFound = { status: 404, contentType: 'text/html', body: 'not here' };
  const noConnection = { rc: 7, body: '' };

  test(`${target.workflow}: a first-attempt success costs one request`, (t) => {
    const r = run([ok], { t });
    assert.equal(r.status, 0, r.output);
    assert.equal(r.requests, 1);
    assert.equal(r.sleeps.length, 0);
    const base = (target.url.PREVIEW_URL ?? target.url.STAGING_URL).replace(/\/$/, '');
    assert.deepEqual(r.urls, [`${base}/.well-known/apple-app-site-association`]);
  });

  test(`${target.workflow}: a 404 that clears is retried`, (t) => {
    const r = run([notFound, ok], { t });
    assert.equal(r.status, 0, r.output);
    assert.equal(r.requests, 2);
    assert.equal(r.sleeps.length, 1);
  });

  test(`${target.workflow}: a persistent 404 fails after the full budget`, (t) => {
    const r = run(repeat(6, notFound), { t });
    assert.equal(r.status, 1);
    assert.equal(r.requests, 6);
    assert.equal(r.sleeps.length, 5);
    assert.match(r.output, /::error::/);
    assert.match(r.output, /last failure: HTTP 404/);
    assert.deepEqual(r.sleeps, Array(5).fill('5'));
  });

  test(`${target.workflow}: a stalled connection that clears is retried`, (t) => {
    const r = run([noConnection, ok], { t });
    assert.equal(r.status, 0, r.output);
    assert.equal(r.requests, 2);
  });

  test(`${target.workflow}: a persistent transport failure names curl, not an HTTP code`, (t) => {
    const r = run(repeat(6, noConnection), { t });
    assert.equal(r.status, 1);
    assert.equal(r.requests, 6);
    assert.match(r.output, /::error::/);
    assert.match(r.output, /last failure: request failed with curl exit 7/);
    assert.doesNotMatch(r.output, /HTTP curl/);
  });

  test(`${target.workflow}: a stale body is retried until it matches`, (t) => {
    const r = run([{ status: 200, body: OTHER }, ok], { t });
    assert.equal(r.status, 0, r.output);
    assert.equal(r.requests, 2);
  });

  test(`${target.workflow}: a persistent body mismatch fails with the wording for its target`, (t) => {
    const r = run(repeat(6, { status: 200, body: OTHER }), { t });
    assert.equal(r.status, 1);
    assert.equal(r.requests, 6);
    assert.match(r.output, /::error::/);
    assert.match(r.output, new RegExp(`last failure: body does not match the ${target.kind} file`));
    assert.match(r.output, /^--- /m, 'the diff is not printed');
  });

  test(`${target.workflow}: a JSON content type with parameters is accepted`, (t) => {
    const r = run([{ status: 200, contentType: 'application/json; charset=utf-8', body: RESERIALISED }], { t });
    assert.equal(r.status, 0, r.output);
  });

  test(`${target.workflow}: json-like content types are rejected`, (t) => {
    for (const contentType of ['application/jsonp', 'application/json-seq']) {
      const r = run(repeat(6, { status: 200, contentType, body: COMMITTED }), { t });
      assert.equal(r.status, 1, contentType);
      assert.match(r.output, new RegExp(`content-type is ${contentType.replace('/', '\\/')}`));
    }
  });

  test(`${target.workflow}: a missing or duplicated content type fails closed`, (t) => {
    for (const scenario of [
      { status: 200, body: COMMITTED, omitContentType: true },
      { status: 200, body: COMMITTED, extraContentType: 'application/json' },
    ]) {
      const r = run(repeat(6, scenario), { t });
      assert.equal(r.status, 1, JSON.stringify(scenario));
      assert.match(r.output, /content-type header is missing or duplicated/);
    }
  });

  test(`${target.workflow}: a base URL without a trailing slash still works`, (t) => {
    const r = run([ok], { t, url: target.noSlashUrl });
    assert.equal(r.status, 0, r.output);
    const base = Object.values(target.noSlashUrl)[0];
    assert.deepEqual(r.urls, [`${base}/.well-known/apple-app-site-association`]);
  });

  test(`${target.workflow}: an empty source file fails fast`, (t) => {
    const r = run([ok], { t, expected: '  \n' });
    assert.equal(r.status, 1);
    assert.equal(r.requests, 0);
    assert.match(r.output, /is not valid JSON/);
  });

  test(`${target.workflow}: a whitespace-only body is not valid JSON`, (t) => {
    const r = run(repeat(6, { status: 200, body: '  \n' }), { t });
    assert.equal(r.status, 1);
    assert.match(r.output, /body is not valid JSON/);
  });

  test(`${target.workflow}: a re-serialised body passes (normalised equality)`, (t) => {
    const r = run([{ status: 200, body: RESERIALISED }], { t });
    assert.equal(r.status, 0, r.output);
    assert.equal(r.requests, 1);
  });

  test(`${target.workflow}: a wrong content type fails and names it`, (t) => {
    const r = run(repeat(6, { status: 200, contentType: 'text/html', body: COMMITTED }), { t });
    assert.equal(r.status, 1);
    assert.match(r.output, /::error::/);
    assert.match(r.output, /content-type is text\/html/);
    assert.match(r.output, /^content-type: text\/html/im, 'the header dump is not printed');
  });

  test(`${target.workflow}: a non-JSON body is reported as such, not as a diff`, (t) => {
    const r = run(repeat(6, { status: 200, contentType: 'application/json', body: '<html>oops' }), { t });
    assert.equal(r.status, 1);
    assert.match(r.output, /::error::/);
    assert.match(r.output, /body is not valid JSON/);
    assert.match(r.output, /<html>oops/);
    assert.doesNotMatch(r.output, /does not match/);
  });

  test(`${target.workflow}: a corrupt source file fails fast before any request`, (t) => {
    const r = run([ok], { t, expected: '{not json' });
    assert.equal(r.status, 1);
    assert.equal(r.requests, 0);
    assert.match(r.output, /is not valid JSON/);
  });

  test(`${target.workflow}: a missing source file fails fast with its own message`, (t) => {
    const r = run([ok], { t, expected: null });
    assert.equal(r.status, 1);
    assert.equal(r.requests, 0);
    assert.match(r.output, /is missing/);
  });

  test(`${target.workflow}: every request is time-bounded and the total budget holds`, (t) => {
    const r = run(repeat(6, noConnection), { t });
    assert.equal(r.bounds.length, 6);
    for (const bound of r.bounds) assert.equal(bound, '3 10');
    const seconds =
      r.bounds.reduce((sum, b) => sum + Number(b.split(' ')[1] ?? 0), 0) +
      r.sleeps.reduce((sum, s) => sum + Number(s), 0);
    assert.ok(seconds <= 85, `the retry budget is ${seconds}s, over the 85s bound`);
  });
}
