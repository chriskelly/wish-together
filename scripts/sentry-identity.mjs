// Derives the numeric Sentry organisation and project ids from a DSN.
//
// The DSN is public (it ships inside the web bundle and the app), and it already
// names both ids, so the repository stores no Sentry slug. sentry-cli accepts an
// id anywhere it accepts a slug. The output is `KEY=value` lines ready for
// `>> "$GITHUB_ENV"`, so a workflow never has to parse the DSN itself.

import { isEntryPoint } from './module-entry.mjs';

// Current-format SaaS DSN: the host is `o<org>.ingest.<region>.sentry.io` and
// the path is the project id. A self-hosted or legacy DSN has neither, so it
// cannot supply the organisation id this needs.
const DSN_PATTERN = /^https:\/\/[^@\s/]+@o(\d+)\.ingest\.[^/\s]+\/(\d+)$/;

/**
 * Returns `{orgId, projectId}` for a current-format DSN, or throws with the
 * reason and the shape this expects.
 */
export function parseSentryDsn(dsn) {
  const value = typeof dsn === 'string' ? dsn.trim() : '';
  if (!value) {
    throw new Error('SENTRY_DSN is empty');
  }

  const match = DSN_PATTERN.exec(value);
  if (!match) {
    throw new Error(
      'SENTRY_DSN does not carry an organisation id; expected ' +
        'https://<key>@o<org>.ingest.<region>.sentry.io/<project>, ' +
        'which is the DSN Sentry shows on the project Client Keys page',
    );
  }

  return { orgId: match[1], projectId: match[2] };
}

function main(argv) {
  if (argv.length > 0) {
    process.stderr.write(
      'usage: SENTRY_DSN=<dsn> node scripts/sentry-identity.mjs\n',
    );
    process.exitCode = 2;
    return;
  }

  try {
    const { orgId, projectId } = parseSentryDsn(process.env.SENTRY_DSN);
    process.stdout.write(
      `SENTRY_ORG=${orgId}\nSENTRY_PROJECT=${projectId}\n`,
    );
  } catch (error) {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  }
}

if (isEntryPoint(import.meta.url)) {
  main(process.argv.slice(2));
}
