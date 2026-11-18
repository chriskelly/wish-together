import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const fastfile = readFileSync(
  new URL('../../fastlane/Fastfile', import.meta.url),
  'utf8',
);

// Split at the lane declarations so an argument cannot satisfy the wrong
// lane's assertion: swapping them between lanes is exactly the mistake this
// test exists to catch.
const lanes = fastfile.split(/^\s*lane :/m);
const laneBody = (name) =>
  lanes.find((block) => block.startsWith(`${name} do`)) ?? '';

// `def build_ipa` starts in the first column and its matching `end` is the
// first one there too (every inner block is indented), so this slice ends at
// the method instead of running to the end of the file.
const buildIpa = /^def build_ipa\b[\s\S]*?^end$/m.exec(fastfile)?.[0] ?? '';
const buildCommand = buildIpa.indexOf('"flutter build ipa');
const guardCall = buildIpa.search(
  /^ {2}check_ipa_diagnostics!\(dsn: dsn, sentry_environment: sentry_environment\)$/m,
);

test('TestFlight reports the documented environment', () => {
  assert.match(fastfile, /^TESTFLIGHT_SENTRY_ENVIRONMENT = "testflight"$/m);
});

test('the TestFlight lane passes its own environment to the build', () => {
  assert.match(
    laneBody('testflight_release'),
    /sentry_environment:\s*TESTFLIGHT_SENTRY_ENVIRONMENT/,
  );
});

test('the App Store lane passes no environment', () => {
  assert.match(laneBody('app_store_release'), /sentry_environment:\s*nil/);
});

test('the build normalises the environment and rejects a blank one', () => {
  assert.match(buildIpa, /sentry_environment = sentry_environment&\.strip/);
  assert.match(buildIpa, /if sentry_environment&\.empty\?/);
});

test('the build adds the environment define only for a value', () => {
  assert.match(
    buildIpa,
    /unless sentry_environment\.nil\?\s*\n\s*defines << "--dart-define=WT_SENTRY_ENVIRONMENT=/,
  );
});

test('the build checks the archive it just produced', () => {
  assert.ok(buildCommand > -1, 'the build command is missing from build_ipa');
  assert.ok(guardCall > -1, 'the guard call is missing from build_ipa');
  assert.ok(guardCall > buildCommand, 'the guard must run after the build');
});
