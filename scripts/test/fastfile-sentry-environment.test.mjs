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

test('TestFlight reports the documented environment', () => {
  assert.match(fastfile, /^TESTFLIGHT_SENTRY_ENVIRONMENT = "testflight"$/m);
});

test('the TestFlight lane passes its own environment to the build', () => {
  assert.match(
    laneBody('testflight_release'),
    /sentry_environment:\s*TESTFLIGHT_SENTRY_ENVIRONMENT/,
  );
});

test('the build checks the archive it just produced', () => {
  const buildIpa = fastfile.slice(fastfile.indexOf('def build_ipa'));

  assert.match(buildIpa, /sentry_environment = sentry_environment&\.strip/);
  assert.match(
    buildIpa,
    /check_ipa_diagnostics!\(dsn: dsn, sentry_environment: sentry_environment\)/,
  );
  // The define is conditional: the App Store lane must not gain one.
  assert.match(
    buildIpa,
    /unless sentry_environment\.nil\?\s*\n\s*defines << "--dart-define=WT_SENTRY_ENVIRONMENT=/,
  );
});

test('the App Store lane stays underived', () => {
  assert.match(laneBody('app_store_release'), /sentry_environment:\s*nil/);
});
