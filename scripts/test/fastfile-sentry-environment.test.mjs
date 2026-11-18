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

test('the App Store lane stays underived', () => {
  assert.match(laneBody('app_store_release'), /sentry_environment:\s*nil/);
});
