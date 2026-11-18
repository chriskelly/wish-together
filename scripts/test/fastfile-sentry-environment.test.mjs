import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const fastfile = readFileSync(
  new URL('../../fastlane/Fastfile', import.meta.url),
  'utf8',
);

test('TestFlight reports the documented environment', () => {
  assert.match(fastfile, /^TESTFLIGHT_SENTRY_ENVIRONMENT = "testflight"$/m);
});

test('the TestFlight lane passes its own environment to the build', () => {
  assert.match(
    fastfile,
    /sentry_environment:\s*TESTFLIGHT_SENTRY_ENVIRONMENT/,
  );
});

test('the App Store lane stays underived', () => {
  assert.match(fastfile, /sentry_environment:\s*nil/);
});
