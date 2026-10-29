// Guards the deployed web bundle against shipping Flutter's source maps.
//
// `flutter build web --source-maps` writes a `.map` file beside every script.
// Those maps carry the app's source, so they are uploaded to Sentry and then
// deleted from the directory that is about to be deployed. The two steps are
// separate commands because the upload in between must fail the build before
// anything is stripped.

import { readdirSync, rmSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';

import { isEntryPoint } from './module-entry.mjs';

const SOURCE_MAP_EXTENSION = '.map';
const ENTRY_POINT = 'main.dart.js';

/**
 * `statSync` for callers that only care whether a path exists and what it is:
 * a missing or unreadable path yields `undefined` instead of throwing.
 */
function statOrUndefined(path) {
  try {
    return statSync(path);
  } catch {
    return undefined;
  }
}

/**
 * Asserts that `root` is an existing directory, so a typo in a workflow path
 * cannot turn a strip or a check into a silent no-op.
 */
function assertDirectory(root) {
  if (!statOrUndefined(root)?.isDirectory()) {
    throw new Error(`build directory not found: ${root}`);
  }
}

/**
 * Every file under `root` whose name ends in `.map`, as paths relative to
 * `root`, sorted so log output and failures are stable.
 *
 * A symlink inside the build is an error rather than something to follow or
 * delete: it could put a map, or a directory of them, where this walk cannot see
 * it, and the caller's guarantee is that nothing reachable is left behind.
 */
export function findSourceMaps(root) {
  assertDirectory(root);

  const maps = [];
  const walk = (directory) => {
    for (const entry of readdirSync(directory, { withFileTypes: true })) {
      const path = join(directory, entry.name);
      if (entry.isSymbolicLink()) {
        throw new Error(`unexpected symlink in the build: ${path}`);
      }
      if (entry.isDirectory()) {
        walk(path);
      } else if (entry.name.endsWith(SOURCE_MAP_EXTENSION)) {
        maps.push(relative(root, path));
      }
    }
  };
  walk(root);

  return maps.sort();
}

/**
 * Deletes every source map under `root` and returns the paths it removed.
 * Everything else in the build directory is left alone.
 */
export function stripSourceMaps(root) {
  const maps = findSourceMaps(root);
  for (const map of maps) {
    rmSync(join(root, map), { force: true });
  }
  return maps;
}

/**
 * Throws unless `root` is a web build that is safe to deploy: the entry point
 * is present (so this is the directory we meant) and no source map remains.
 */
export function verifyWebBuildDir(root) {
  assertDirectory(root);

  if (!statOrUndefined(join(root, ENTRY_POINT))?.isFile()) {
    throw new Error(`not a web build: ${ENTRY_POINT} is missing from ${root}`);
  }

  const maps = findSourceMaps(root);
  if (maps.length > 0) {
    throw new Error(`source maps remain in ${root}: ${maps.join(', ')}`);
  }
}

function usage(message) {
  const prefix = message ? `${message}\n` : '';
  process.stderr.write(
    `${prefix}usage: node scripts/web-source-maps.mjs <strip|verify> <build-dir>\n`,
  );
  process.exitCode = 2;
}

function main(argv) {
  const [command, directory, ...extra] = argv;
  if (extra.length > 0 || !directory) {
    usage('expected exactly one command and one build directory');
    return;
  }

  try {
    if (command === 'strip') {
      const removed = stripSourceMaps(directory);
      const files = removed.length === 1 ? 'file' : 'files';
      process.stdout.write(
        `removed ${removed.length} source map ${files} from ${directory}\n`,
      );
    } else if (command === 'verify') {
      verifyWebBuildDir(directory);
      process.stdout.write(`${directory} contains no source map files\n`);
    } else {
      usage(`unknown command: ${command}`);
    }
  } catch (error) {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  }
}

if (isEntryPoint(import.meta.url)) {
  main(process.argv.slice(2));
}
