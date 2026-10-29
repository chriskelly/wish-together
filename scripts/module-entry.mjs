// Tells a script whether it is the program being run or a module being imported.
//
// `import.meta.url` is already resolved, while `process.argv[1]` keeps whatever
// path the caller used, so comparing them unresolved makes a script invoked
// through a symlink decide it is a module — it exits 0 having done nothing.
// Both sides are resolved here for that reason.

import { realpathSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

/**
 * True when the module at `moduleUrl` was started directly, for example by
 * `node scripts/sentry-identity.mjs`, rather than imported by a test.
 */
export function isEntryPoint(moduleUrl) {
  if (!process.argv[1]) {
    return false;
  }
  try {
    return realpathSync(process.argv[1]) === fileURLToPath(moduleUrl);
  } catch {
    return false;
  }
}
