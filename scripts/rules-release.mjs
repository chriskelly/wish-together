#!/usr/bin/env node
// Reads and verifies Firestore Security Rules releases.
//
// A staging deploy uses this to prove two things:
//   1. the candidate `firestore.rules` actually reached the staging database
//      (firebase-tools #9910 can silently skip an upload), and
//   2. the production release did not move.
//
// Auth: Application Default Credentials (GOOGLE_APPLICATION_CREDENTIALS in CI)
// or an explicit access token locally:
//
//   ACCESS_TOKEN=$(gcloud auth print-access-token) \
//     node rules-release.mjs show --database staging
//
// Usage:
//   node rules-release.mjs show --database staging [--project <id>] [--json]
//   node rules-release.mjs check --database staging --source ../firestore.rules
//   node rules-release.mjs check --database "(default)" --expect-ruleset <id>
//
// `show` prints the active ruleset resource name; `check` exits non-zero when
// the source or the expected ruleset id does not match.

import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

import { GoogleAuth } from 'google-auth-library';

export const DEFAULT_PROJECT_ID = 'wish-together-project';
export const RULES_SERVICE = 'cloud.firestore';
const RULES_API = 'https://firebaserules.googleapis.com/v1';

/// The release resource for a database. The default database has no suffix.
export function releaseName(projectId, databaseId) {
  if (!databaseId) {
    throw new Error('database id required');
  }
  const suffix = databaseId === '(default)' ? '' : `/${databaseId}`;
  return `projects/${projectId}/releases/${RULES_SERVICE}${suffix}`;
}

/// The trailing id of a resource name such as `projects/.../rulesets/<id>`.
function trailingResourceId(name) {
  return String(name ?? '').split('/').filter(Boolean).pop() ?? '';
}

/// The ruleset id the given release points at, or '' when unreadable.
export function releaseRulesetId(release) {
  return trailingResourceId(release?.rulesetName);
}

/// Compares source the way the Rules API stores it: LF line endings, no
/// trailing whitespace, no leading/trailing blank lines.
export function normalizeRulesSource(source) {
  return String(source ?? '')
    .replace(/\r\n/g, '\n')
    .split('\n')
    .map((line) => line.replace(/[ \t]+$/, ''))
    .join('\n')
    .trim();
}

export function rulesSourceFromRuleset(ruleset) {
  return (ruleset?.source?.files ?? [])
    .map((file) => file?.content ?? '')
    .join('\n');
}

export function sourcesMatch(localSource, liveSource) {
  return normalizeRulesSource(localSource) === normalizeRulesSource(liveSource);
}

function requireValue(args, index, flag) {
  const value = args[index];
  if (!value || value.startsWith('--')) {
    throw new Error(`${flag} needs a value`);
  }
  return value;
}

export function parseArgs(argv) {
  const [command, ...rest] = argv;
  if (command !== 'show' && command !== 'check') {
    throw new Error('Usage: rules-release.mjs <show|check> [options]');
  }

  const options = {
    command,
    project: DEFAULT_PROJECT_ID,
    database: null,
    source: null,
    expectRuleset: null,
    json: false,
  };

  for (let index = 0; index < rest.length; index += 1) {
    const flag = rest[index];
    switch (flag) {
      case '--project':
        options.project = requireValue(rest, (index += 1), flag);
        break;
      case '--database':
        options.database = requireValue(rest, (index += 1), flag);
        break;
      case '--source':
        options.source = requireValue(rest, (index += 1), flag);
        break;
      case '--expect-ruleset':
        options.expectRuleset = requireValue(rest, (index += 1), flag);
        break;
      case '--json':
        options.json = true;
        break;
      default:
        throw new Error(`Unknown option ${flag}`);
    }
  }

  if (command === 'show' && (options.source || options.expectRuleset)) {
    throw new Error('show does not accept --source or --expect-ruleset');
  }
  if (command === 'check' && options.json) {
    throw new Error('check does not accept --json');
  }
  if (!options.database) {
    throw new Error(`${command} needs --database`);
  }
  if (command === 'check') {
    if (!options.source && !options.expectRuleset) {
      throw new Error('check needs --source and/or --expect-ruleset');
    }
  }
  return options;
}

async function accessToken() {
  if (process.env.ACCESS_TOKEN) {
    return process.env.ACCESS_TOKEN;
  }
  const auth = new GoogleAuth({
    scopes: ['https://www.googleapis.com/auth/cloud-platform'],
  });
  const client = await auth.getClient();
  const { token } = await client.getAccessToken();
  if (!token) {
    throw new Error(
      'Could not obtain a Google access token. Set ACCESS_TOKEN or GOOGLE_APPLICATION_CREDENTIALS.',
    );
  }
  return token;
}

/// Headers for a Rules API request.
///
/// `x-goog-user-project` is only needed when the token comes from local user
/// ADC. A service-account token attributes quota to its own project, and
/// sending the header would require `serviceusage.services.use` on the deploy
/// service account.
export function requestHeaders(
  token,
  projectId,
  { userToken = Boolean(process.env.ACCESS_TOKEN) } = {},
) {
  const headers = { Authorization: `Bearer ${token}` };
  if (userToken) {
    headers['x-goog-user-project'] = projectId;
  }
  return headers;
}

async function getJson(url, token, projectId) {
  const response = await fetch(url, {
    headers: requestHeaders(token, projectId),
    signal: AbortSignal.timeout(30_000),
  });
  if (!response.ok) {
    const error = new Error(
      `${response.status} ${response.statusText}: ${await response.text()}`,
    );
    error.status = response.status;
    throw error;
  }
  return response.json();
}

async function fetchRelease(projectId, databaseId, token) {
  // Read the release directly rather than listing every release: the list is
  // paginated, and a missing database is a 404 here.
  try {
    return await getJson(
      `${RULES_API}/${releaseName(projectId, databaseId)}`,
      token,
      projectId,
    );
  } catch (error) {
    if (error.status === 404) {
      return null;
    }
    throw error;
  }
}

export async function main(argv = process.argv.slice(2)) {
  const options = parseArgs(argv);
  const token = await accessToken();
  const release = await fetchRelease(
    options.project,
    options.database,
    token,
  );

  if (!release) {
    throw new Error(
      `No Firestore rules release for "${options.database}" (${releaseName(options.project, options.database)}). Deploy the rules first.`,
    );
  }

  const rulesetId = releaseRulesetId(release);
  if (!rulesetId) {
    throw new Error(
      `Release "${options.database}" has no ruleset id; refusing to treat it as deployed.`,
    );
  }

  if (options.command === 'show') {
    if (options.json) {
      console.log(
        JSON.stringify(
          {
            database: options.database,
            release: release.name,
            rulesetName: release.rulesetName,
            rulesetId,
            updateTime: release.updateTime ?? null,
          },
          null,
          2,
        ),
      );
    } else {
      console.log(release.rulesetName);
    }
    return 0;
  }

  let failed = false;

  if (options.expectRuleset) {
    const expected = trailingResourceId(options.expectRuleset);
    // Fail closed when the expected id is unreadable, so two empty ids cannot
    // look like a match.
    if (!expected || expected !== rulesetId) {
      console.error(
        `Ruleset mismatch for "${options.database}": expected ${expected}, live ${rulesetId}.`,
      );
      failed = true;
    }
  }

  if (options.source) {
    const localSource = readFileSync(options.source, 'utf8');
    const ruleset = await getJson(
      `${RULES_API}/${release.rulesetName}`,
      token,
      options.project,
    );
    if (!sourcesMatch(localSource, rulesSourceFromRuleset(ruleset))) {
      console.error(
        `Source mismatch for "${options.database}": the live ruleset does not match ${options.source}.`,
      );
      failed = true;
    }
  }

  if (failed) {
    return 1;
  }

  console.log(`${release.name} -> ${release.rulesetName}`);
  return 0;
}

if (
  process.argv[1] &&
  import.meta.url === pathToFileURL(process.argv[1]).href
) {
  main()
    .then((exitCode) => {
      process.exitCode = exitCode;
    })
    .catch((error) => {
      console.error(error.message ?? error);
      process.exitCode = 1;
    });
}
