// Proves both Sentry defines reached the compiled Dart in an iOS archive.
//
// The archive's App.framework/App is the AOT snapshot, not text: read it as
// bytes. The two markers are checked together, so a lane that lost the DSN and
// a lane that lost the environment cannot each pass on the other's evidence.

import { readFileSync } from 'node:fs';

import { isEntryPoint } from './module-entry.mjs';

export const ENVIRONMENT_MARKER_PREFIX = 'wishtogether-sentry-environment=';

/**
 * The exact byte sequences the binary must contain.
 *
 * An empty value would match every binary, so it is refused rather than
 * checked. An undefined environment means the lane passed no override (the
 * release build derives production), and only the DSN is required.
 *
 * @param {string} dsn the public Sentry DSN compiled into the app
 * @param {string|undefined} environment the environment override, if any
 * @returns {string[]} the markers to look for
 */
export function requiredMarkers(dsn, environment) {
  const value = String(dsn ?? '').trim();
  if (!value) {
    throw new Error('SENTRY_DSN is empty; an empty marker matches every bundle');
  }

  const markers = [value];
  if (environment !== undefined) {
    const resolved = String(environment).trim();
    if (!resolved) {
      throw new Error('the Sentry environment marker value is blank');
    }
    markers.push(`${ENVIRONMENT_MARKER_PREFIX}${resolved}`);
  }
  return markers;
}

/**
 * Return the markers the bundle does not contain.
 *
 * @param {Buffer} bundle the compiled binary
 * @param {string[]} markers exact byte sequences to find
 * @returns {string[]} the missing markers, in input order
 */
export function missingMarkers(bundle, markers) {
  return markers.filter((marker) => !bundle.includes(Buffer.from(marker)));
}

function main(argv) {
  if (argv.length < 2) {
    process.stderr.write(
      'usage: node scripts/check-ipa-diagnostics.mjs <bundle> <dsn> [environment]\n',
    );
    process.exitCode = 1;
    return;
  }

  const [path, dsn, environment] = argv;

  let bundle;
  try {
    bundle = readFileSync(path);
  } catch (error) {
    process.stderr.write(
      `error: cannot read the bundle at ${path}: ${error.message}\n`,
    );
    process.exitCode = 1;
    return;
  }

  let markers;
  try {
    markers = requiredMarkers(dsn, environment);
  } catch (error) {
    process.stderr.write(`error: ${error.message}\n`);
    process.exitCode = 1;
    return;
  }

  const missing = missingMarkers(bundle, markers);
  if (missing.length > 0) {
    process.stderr.write(
      `error: the compiled app does not embed ${missing.join(', ')}; ` +
        'the matching --dart-define did not reach the build\n',
    );
    process.exitCode = 1;
    return;
  }

  process.stdout.write(
    `Compiled app embeds ${markers.length} Sentry marker(s).\n`,
  );
}

if (isEntryPoint(import.meta.url)) {
  main(process.argv.slice(2));
}
