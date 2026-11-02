import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import {
  chmodSync,
  existsSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';

// `tool/dev.sh` prints the URL an agent opens and assembles the `flutter run`
// command, so those strings are its interface. These tests put a stub `flutter`
// (and `npm`, for live mode) first on PATH and assert both.

const repoRoot = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const script = join(repoRoot, 'tool', 'dev.sh');
const fakeToken = 'aaa.bbb.ccc';
// A live run checks for scripts dependencies before it mints; without `npm ci`
// the success cases cannot exercise the command they are about.
const liveReady = existsSync(
  join(repoRoot, 'scripts', 'node_modules', 'firebase-admin'),
);
const liveSkip = liveReady
  ? {}
  : { skip: 'run `npm ci` in scripts to exercise live mode' };

function run(args, { env = {} } = {}) {
  const dir = mkdtempSync(join(tmpdir(), 'wt-dev-runner-'));
  const calls = join(dir, 'calls.txt');
  try {
    const flutter = join(dir, 'flutter');
    writeFileSync(
      flutter,
      `#!/usr/bin/env bash\nprintf '%s\\n' "$*" > "${calls}"\n`,
    );
    chmodSync(flutter, 0o755);

    const npm = join(dir, 'npm');
    writeFileSync(npm, `#!/usr/bin/env bash\nprintf '%s\\n' '${fakeToken}'\n`);
    chmodSync(npm, 0o755);

    const result = spawnSync('bash', [script, ...args], {
      cwd: repoRoot,
      encoding: 'utf8',
      env: {
        ...process.env,
        GOOGLE_APPLICATION_CREDENTIALS: '',
        PATH: `${dir}:${process.env.PATH}`,
        ...env,
      },
    });
    return {
      status: result.status,
      stdout: result.stdout,
      stderr: result.stderr,
      calls: existsSync(calls) ? readFileSync(calls, 'utf8').trim() : '',
    };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

test('help prints the usage without running flutter', () => {
  const result = run(['--help']);

  assert.equal(result.status, 0);
  assert.match(result.stdout, /Usage:/);
  assert.equal(result.calls, '');
});

test('the default fake session prints its URL and runs the committed entrypoint', () => {
  const result = run([]);

  assert.equal(result.status, 0);
  assert.match(result.stdout, /http:\/\/localhost:47923\/\?scenario=default/);
  assert.equal(
    result.calls,
    'run -t lib/dev/dev_main.dart -d web-server --web-port=47923',
  );
});

test('a scenario and a path become the printed entry URL', () => {
  const result = run(['large-wishlist', '/wishlist/lg-l1']);

  assert.equal(result.status, 0);
  assert.match(
    result.stdout,
    /http:\/\/localhost:47923\/wishlist\/lg-l1\?scenario=large-wishlist/,
  );
});

test('a lone path is the route, not a scenario', () => {
  const result = run(['/wishlist/fam-l1']);

  assert.equal(result.status, 0);
  assert.match(
    result.stdout,
    /http:\/\/localhost:47923\/wishlist\/fam-l1\?scenario=default/,
  );
});

test('chrome is launched at the printed URL rather than the site root', () => {
  const result = run(['family', '--chrome']);

  assert.equal(result.status, 0);
  assert.match(
    result.calls,
    /--web-launch-url=http:\/\/localhost:47923\/\?scenario=family/,
  );
  assert.match(result.calls, /-d chrome/);
});

test('arguments after -- reach the flutter command', () => {
  const result = run(['default', '--', '--dart-define=EXTRA=1']);

  assert.equal(result.status, 0);
  assert.match(result.calls, /--dart-define=EXTRA=1$/);
});

test('an unknown scenario fails and lists the committed ids', () => {
  const result = run(['nope']);

  assert.equal(result.status, 2);
  assert.match(result.stderr, /unknown scenario "nope"/);
  for (const id of [
    'default',
    'family',
    'large-wishlist',
    'empty',
    'overflow',
    'shared',
  ]) {
    assert.match(result.stderr, new RegExp(`\\b${id}\\b`));
  }
  assert.equal(result.calls, '');
});

test('a port below 1024 is refused', () => {
  const result = run(['--port', '80']);

  assert.equal(result.status, 2);
  assert.match(result.stderr, /between 1024 and 65535/);
});

test('a leading-zero port is read as decimal', () => {
  const result = run(['--port', '01024']);

  assert.equal(result.status, 0);
  assert.match(result.stdout, /http:\/\/localhost:1024\//);
  assert.match(result.calls, /--web-port=1024/);
});

test('a one-off entrypoint starts at its path without a scenario query', () => {
  const result = run([
    '--entrypoint',
    'lib/dev/scenarios/local/mine.dart',
    '/wishlist/x',
  ]);

  assert.equal(result.status, 0);
  assert.match(result.stdout, /entrypoint "lib\/dev\/scenarios\/local\/mine\.dart"/);
  assert.match(result.stdout, /http:\/\/localhost:47923\/wishlist\/x\n/);
  assert.doesNotMatch(result.stdout, /\?scenario=/);
  assert.match(result.calls, /-t lib\/dev\/scenarios\/local\/mine\.dart/);
});

test('a value after --entrypoint is a path, never a scenario', () => {
  const result = run(['--entrypoint', 'lib/dev/dev_main.dart', 'family']);

  assert.equal(result.status, 2);
  assert.match(result.stderr, /the path must start with "\/"/);
  assert.equal(result.calls, '');
});

test('live-only flags are refused in fake mode', () => {
  const result = run(['--uid', 'dev-1']);

  assert.equal(result.status, 2);
  assert.match(result.stderr, /--uid is live-only/);
});

test('live mode needs a uid', () => {
  const result = run(['live']);

  assert.equal(result.status, 2);
  assert.match(result.stderr, /needs --uid/);
});

test('live mode refuses the production database before minting', () => {
  const result = run(['live', '--uid', 'dev-1', '--database', '(default)']);

  assert.equal(result.status, 2);
  assert.match(result.stderr, /production database/);
  assert.equal(result.calls, '');
});

test('live mode refuses a port other than 59922', () => {
  const result = run(['live', '--uid', 'dev-1', '--port', '1234']);

  assert.equal(result.status, 2);
  assert.match(result.stderr, /always port 59922/);
});

test('live mode mints a token and pins the API-key port', liveSkip, () => {
  const result = run(['live', '/wishlist/x', '--uid', 'dev-1'], {
    env: {
      GOOGLE_APPLICATION_CREDENTIALS: '/tmp/fake-service-account.json',
    },
  });

  assert.equal(result.status, 0);
  assert.match(result.stdout, /http:\/\/localhost:59922\/wishlist\/x/);
  assert.match(result.calls, /-t lib\/dev\/dev_main\.dart -d web-server/);
  assert.match(result.calls, /--web-port=59922/);
  assert.match(result.calls, /--dart-define=WT_DEV_BACKEND=live/);
  assert.match(result.calls, /--dart-define=WT_FIRESTORE_DATABASE=staging/);
  assert.match(result.calls, new RegExp(`--dart-define=WT_DEV_TOKEN=${fakeToken}`));
});

test('live mode offers account deletion only when asked', liveSkip, () => {
  const enabled = run(['live', '--uid', 'dev-1', '--allow-account-deletion'], {
    env: {
      GOOGLE_APPLICATION_CREDENTIALS: '/tmp/fake-service-account.json',
    },
  });
  const disabled = run(['live', '--uid', 'dev-1'], {
    env: {
      GOOGLE_APPLICATION_CREDENTIALS: '/tmp/fake-service-account.json',
    },
  });

  assert.equal(enabled.status, 0);
  assert.match(enabled.calls, /--dart-define=WT_DEV_ALLOW_ACCOUNT_DELETION=true/);
  assert.doesNotMatch(disabled.calls, /WT_DEV_ALLOW_ACCOUNT_DELETION/);
});

test('live mode accepts the port it is already pinned to', liveSkip, () => {
  const result = run(['live', '--uid', 'dev-1', '--port', '59922'], {
    env: {
      GOOGLE_APPLICATION_CREDENTIALS: '/tmp/fake-service-account.json',
    },
  });

  assert.equal(result.status, 0);
  assert.match(result.calls, /--web-port=59922/);
});

test('live chrome is launched at the pinned URL', liveSkip, () => {
  const result = run(['live', '--uid', 'dev-1', '--chrome'], {
    env: {
      GOOGLE_APPLICATION_CREDENTIALS: '/tmp/fake-service-account.json',
    },
  });

  assert.equal(result.status, 0);
  assert.match(result.calls, /-d chrome/);
  assert.match(result.calls, /--web-launch-url=http:\/\/localhost:59922\//);
});
