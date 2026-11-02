#!/usr/bin/env node
// Mints a Firebase custom token for one uid, for the dev session's live backend.
//
// The token is a bearer credential for one uid and lasts about an hour. It
// reaches the app through --dart-define, which is why this prints the whole
// `flutter run` line rather than only the token: one copy-paste is the whole
// setup.
//
// The app refuses to start against the default (production) database, so this
// refuses to print a command for it. A token minted for a staging uid is
// harmless if misused, but a command that cannot run is a trap.
//
// Usage (credentials are never stored in the repo):
//
//   cd scripts && npm ci
//   GOOGLE_APPLICATION_CREDENTIALS=~/path/to/service-account.json \
//     npm run dev:token -- --uid <uid> [--database staging] [--web-port 59922]
//
// The uid needs no Auth account: the first sign-in creates one. Seed the data it
// should see with the same uid:
//
//   GOOGLE_APPLICATION_CREDENTIALS=... npm run seed:demo -- --yes \
//     --database staging --viewer-uid <uid>

import { readFileSync } from 'node:fs';

import { cert, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';

import { isEntryPoint } from './module-entry.mjs';
import { STAGING_DATABASE, isNamedDatabaseId } from './staging-config.mjs';

export const PROJECT_ID = 'wish-together-project';
export const DEFAULT_DATABASE_ID = STAGING_DATABASE;

// The only localhost port the project's browser API key allows: its HTTP
// referrer list holds http://localhost:59922/* and nothing else for localhost.
// A live sign-in from another port is rejected by the API key, so the printed
// command pins this one. lib/dev/dev_config.dart carries the same number, and
// test/dev/dev_live_test.dart fails if the two drift.
export const DEFAULT_WEB_PORT = 59922;

export const ENTRYPOINT = 'lib/dev/dev_main.dart';
export const UID_MAX_LENGTH = 128;
const WEB_PORT_MIN = 1024;
const WEB_PORT_MAX = 65535;

export const USAGE = `Usage: npm run dev:token -- --uid <uid> [options]

  --uid <uid>        the account the dev session signs in as (required)
  --database <id>    a named Firestore database (default "${DEFAULT_DATABASE_ID}")
  --web-port <port>  the port the app is served on (default ${DEFAULT_WEB_PORT})
  --help             print this message

Requires GOOGLE_APPLICATION_CREDENTIALS to point at a service-account JSON for
${PROJECT_ID}.`;

/// Splits `--flag=value` into its name and value, or returns a null value for
/// the `--flag value` form.
function splitFlag(arg) {
  const equals = arg.startsWith('--') ? arg.indexOf('=') : -1;
  if (equals === -1) {
    return [arg, null];
  }
  return [arg.slice(0, equals), arg.slice(equals + 1)];
}

function requireValue(args, index, flag) {
  const value = args[index];
  if (!value || value.startsWith('--')) {
    throw new Error(`${flag} needs a value`);
  }
  return value;
}

/// The uid to mint for: a non-empty string Firebase will accept as a uid.
///
/// Whitespace is refused rather than trimmed away: a uid with a space in it is
/// almost always a quoting mistake, and it would silently create a second
/// account next to the intended one.
export function validateUid(raw) {
  const uid = String(raw ?? '').trim();
  if (!uid) {
    throw new Error('Missing --uid <uid> (the account the dev session signs in as)');
  }
  if (uid.length > UID_MAX_LENGTH) {
    throw new Error(`Invalid --uid: ${uid.length} characters, Firebase allows at most ${UID_MAX_LENGTH}`);
  }
  if (/\s/.test(uid)) {
    throw new Error(`Invalid --uid ${JSON.stringify(uid)}: it contains whitespace`);
  }
  return uid;
}

/// A named database id. `(default)` is production and is refused here.
export function validateDatabaseId(raw) {
  const id = String(raw ?? '').trim();
  if (id === '(default)') {
    throw new Error(
      'Refusing --database "(default)": that is the production database, and the dev session refuses it too. Use "staging".',
    );
  }
  if (!isNamedDatabaseId(id)) {
    throw new Error(
      `Invalid --database ${JSON.stringify(id)}: expected a named database id, e.g. "${DEFAULT_DATABASE_ID}".`,
    );
  }
  return id;
}

/// The port the app is served on, as a number.
export function validateWebPort(raw) {
  const port = Number(raw);
  if (!Number.isInteger(port) || port < WEB_PORT_MIN || port > WEB_PORT_MAX) {
    throw new Error(
      `Invalid --web-port ${JSON.stringify(raw)}: expected a port between ${WEB_PORT_MIN} and ${WEB_PORT_MAX}.`,
    );
  }
  return port;
}

export function parseArgs(argv) {
  const options = {
    uid: null,
    databaseId: DEFAULT_DATABASE_ID,
    webPort: DEFAULT_WEB_PORT,
    help: false,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const [name, inline] = splitFlag(argv[index]);
    // Both `--uid value` and `--uid=value` are accepted; the latter is what a
    // shell completion and the npm script both produce.
    const value = () => (inline ?? requireValue(argv, (index += 1), name));
    switch (name) {
      case '--uid':
        options.uid = value();
        break;
      case '--database':
        options.databaseId = value();
        break;
      case '--web-port':
        options.webPort = value();
        break;
      case '--help':
        options.help = true;
        break;
      default:
        throw new Error(`Unknown option ${name}`);
    }
  }

  if (options.help) {
    return options;
  }
  options.uid = validateUid(options.uid);
  options.databaseId = validateDatabaseId(options.databaseId);
  options.webPort = validateWebPort(options.webPort);
  return options;
}

/// The command a reader pastes into a shell.
///
/// One line on purpose: a wrapped command is ambiguous about where the line
/// breaks belong, and this string is the whole setup instructions.
export function devRunCommand({ databaseId, token, webPort }) {
  return [
    'flutter run',
    `-t ${ENTRYPOINT}`,
    '-d chrome',
    `--web-port=${webPort}`,
    '--dart-define=WT_DEV_BACKEND=live',
    `--dart-define=WT_FIRESTORE_DATABASE=${databaseId}`,
    `--dart-define=WT_DEV_TOKEN=${token}`,
  ].join(' ');
}

export async function main(argv = process.argv.slice(2)) {
  let options;
  try {
    options = parseArgs(argv);
  } catch (error) {
    console.error(error.message);
    console.error(USAGE);
    return 2;
  }
  if (options.help) {
    console.log(USAGE);
    return 0;
  }

  const credentialsPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (!credentialsPath) {
    console.error(
      'Set GOOGLE_APPLICATION_CREDENTIALS to a Firebase service-account JSON.',
    );
    return 2;
  }

  let credentials;
  try {
    credentials = JSON.parse(readFileSync(credentialsPath, 'utf8'));
  } catch (error) {
    console.error(`Cannot read "${credentialsPath}": ${error.message}`);
    return 2;
  }
  if (credentials.project_id !== PROJECT_ID) {
    console.error(
      `Refusing to run: "${credentialsPath}" belongs to project "${credentials.project_id}", expected "${PROJECT_ID}".`,
    );
    return 2;
  }

  const app = initializeApp({
    credential: cert(credentials),
    projectId: PROJECT_ID,
  });

  let token;
  try {
    token = await getAuth(app).createCustomToken(options.uid);
  } catch (error) {
    console.error(`Could not mint a token for uid "${options.uid}": ${error.message}`);
    return 1;
  }

  console.log(`Project: ${PROJECT_ID} (Auth is shared with production)`);
  console.log(`UID: ${options.uid}`);
  console.log(`Database: ${options.databaseId}`);
  console.log('');
  console.log('Token (valid for about an hour):');
  console.log('');
  console.log(token);
  console.log('');
  console.log(
    `Run it (one line; the port is the one the project's API key allows):`,
  );
  console.log('');
  console.log(
    devRunCommand({
      databaseId: options.databaseId,
      token,
      webPort: options.webPort,
    }),
  );
  console.log('');
  console.log(
    'A new token needs a restart: --dart-define is compile-time, so stop the app and run the line again.',
  );
  return 0;
}

if (isEntryPoint(import.meta.url)) {
  process.exitCode = await main();
}
