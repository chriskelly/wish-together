import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

import {
  findSourceMaps,
  stripSourceMaps,
  verifyWebBuildDir,
} from '../web-source-maps.mjs';

const CLI = fileURLToPath(new URL('../web-source-maps.mjs', import.meta.url));

// A build shaped like `flutter build web --source-maps` output: the entry
// point the guard keys on, plus one map per script.
const BUILD_FILES = {
  'main.dart.js': 'console.log("app");',
  'main.dart.js.map': '{"version":3}',
  'flutter_service_worker.js': 'self.addEventListener("install", () => {});',
  'assets/AssetManifest.bin.json': '{}',
  'assets/packages/foo/bar.dart.js.map': '{"version":3}',
};

/** A throwaway build directory, removed when the test ends. */
function makeDir(t, files = BUILD_FILES) {
  const root = mkdtempSync(join(tmpdir(), 'web-build-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  for (const [path, contents] of Object.entries(files)) {
    const full = join(root, path);
    mkdirSync(dirname(full), { recursive: true });
    writeFileSync(full, contents);
  }
  return root;
}

function runCli(args) {
  return spawnSync(process.execPath, [CLI, ...args], { encoding: 'utf8' });
}

test('finds source maps at the top level and in nested directories', (t) => {
  const root = makeDir(t);

  assert.deepEqual(findSourceMaps(root), [
    'assets/packages/foo/bar.dart.js.map',
    'main.dart.js.map',
  ]);
});

test('strips every source map and leaves the rest of the build intact', (t) => {
  const root = makeDir(t);

  const removed = stripSourceMaps(root);

  assert.deepEqual(removed, [
    'assets/packages/foo/bar.dart.js.map',
    'main.dart.js.map',
  ]);
  assert.deepEqual(findSourceMaps(root), []);
  for (const path of [
    'main.dart.js',
    'flutter_service_worker.js',
    'assets/AssetManifest.bin.json',
  ]) {
    assert.ok(existsSync(join(root, path)), `${path} must survive the strip`);
  }
  assert.equal(
    runCli(['verify', root]).status,
    0,
    'a stripped build must pass the guard',
  );
});

test('refuses to strip a directory that does not exist', () => {
  const root = join(tmpdir(), 'definitely-not-a-build-9c4a2b');

  assert.throws(() => stripSourceMaps(root), /build directory not found/);
});

test('refuses a build that contains a symlink it cannot account for', (t) => {
  const root = makeDir(t, {
    'main.dart.js': 'console.log("app");',
    'index.html': '',
  });
  symlinkSync(join(root, 'main.dart.js'), join(root, 'linked.js'));

  assert.throws(() => findSourceMaps(root), /unexpected symlink/);
});

test('accepts a web build that contains no source maps', (t) => {
  const root = makeDir(t, { 'main.dart.js': 'console.log("app");' });

  assert.doesNotThrow(() => verifyWebBuildDir(root));
});

test('rejects a web build that still contains a source map', (t) => {
  const root = makeDir(t);

  assert.throws(
    () => verifyWebBuildDir(root),
    /source maps remain.*main\.dart\.js\.map/,
  );
});

test('rejects a directory that is not a web build', (t) => {
  const root = makeDir(t, { 'index.html': '<html></html>' });

  assert.throws(() => verifyWebBuildDir(root), /main\.dart\.js is missing/);
});

test('rejects a directory that does not exist', () => {
  const root = join(tmpdir(), 'definitely-not-a-build-2f8c1e');

  assert.throws(() => verifyWebBuildDir(root), /build directory not found/);
});

test('the strip command reports how many maps it removed', (t) => {
  const root = makeDir(t);

  const result = runCli(['strip', root]);

  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /removed 2 source map files/);
});

test('the strip command names a single map in the singular', (t) => {
  const root = makeDir(t, {
    'main.dart.js': 'console.log("app");',
    'main.dart.js.map': '{"version":3}',
  });

  const result = runCli(['strip', root]);

  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /removed 1 source map file from/);
});

test('the verify command fails and names the map that would have leaked', (t) => {
  const root = makeDir(t, { 'main.dart.js': 'x', 'main.dart.js.map': '{}' });

  const result = runCli(['verify', root]);

  assert.equal(result.status, 1);
  assert.match(result.stderr, /main\.dart\.js\.map/);
});

test('strip and verify both succeed on a build that produced no maps', (t) => {
  // A fork PR builds without `--source-maps`, so the strip step runs on a
  // directory with nothing to remove and must not fail.
  const root = makeDir(t, { 'main.dart.js': 'console.log("app");' });

  const stripped = runCli(['strip', root]);
  assert.equal(stripped.status, 0, stripped.stderr);
  assert.match(stripped.stdout, /removed 0 source map files/);

  const verified = runCli(['verify', root]);
  assert.equal(verified.status, 0, verified.stderr);
});

test('works when invoked through a symlink to the script', (t) => {
  const root = makeDir(t, { 'main.dart.js': 'console.log("app");' });
  const links = mkdtempSync(join(tmpdir(), 'web-build-links-'));
  t.after(() => rmSync(links, { recursive: true, force: true }));
  const link = join(links, 'verify-link.mjs');
  symlinkSync(CLI, link);

  const result = spawnSync(process.execPath, [link, 'verify', root], {
    encoding: 'utf8',
  });

  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /contains no source map files/);
});

test('the command rejects unknown usage', () => {
  const result = runCli(['publish', 'build/web']);

  assert.equal(result.status, 2);
  assert.match(result.stderr, /usage/);
});
