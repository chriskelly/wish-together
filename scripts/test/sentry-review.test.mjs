import assert from 'node:assert/strict';
import * as fs from 'node:fs';
import { existsSync, mkdtempSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';

import {
  dismissProposal,
  eventFacts,
  formatStatus,
  listGitHubIssues,
  loadState,
  main,
  markProposal,
  matchGitHub,
  parseArgs,
  rankCandidates,
  reopenProposal,
  resolveToken,
  resolveWindow,
  review,
  saveState,
} from '../sentry-review.mjs';

const NOW = new Date('2026-11-22T04:00:00Z');
const TOKEN = 'read-only-token-sentinel';
const RELEASE_SHA = 'aace21980de286f211bbce10e197672edca4a3ec';
const EVENT_ID = 'd8f41026a53b4d39b22b8a225f213122';

function tempDir(t) {
  const dir = mkdtempSync(join(tmpdir(), 'sentry-review-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  return dir;
}

function iso(date) {
  return date.toISOString();
}

function makeIssue(overrides = {}) {
  return {
    id: '7855897843',
    shortId: 'WISH-TOGETHER-G',
    title: 'Bad state: Future already completed',
    culprit: '?(main.dart)',
    level: 'error',
    priority: 'high',
    status: 'unresolved',
    substatus: 'new',
    count: '1',
    userCount: 1,
    firstSeen: '2026-11-19T05:36:51Z',
    lastSeen: '2026-11-19T05:36:51Z',
    permalink: 'https://chris-kelly.sentry.io/issues/7855897843/',
    metadata: {
      type: 'StateError',
      value: 'Bad state: Future already completed',
      filename: '/gsi/client',
      function: 'ou',
    },
    stats: { '24h': [[1795237200, 1]] },
    project: { slug: 'wish-together' },
    ...overrides,
  };
}

function makeEvent(overrides = {}) {
  return {
    eventID: EVENT_ID,
    dateCreated: '2026-11-19T05:36:51Z',
    tags: [
      { key: 'environment', value: 'production' },
      { key: 'event', value: 'error' },
      { key: 'release', value: `wishtogether@${RELEASE_SHA}` },
      { key: 'dist', value: `web-${RELEASE_SHA}` },
      { key: 'route', value: '/login' },
    ],
    user: {
      id: 'PII-USER-ID-CANARY',
      email: 'PII-EMAIL-CANARY@example.com',
      ip_address: '203.0.113.9',
      name: 'PII-NAME-CANARY',
      username: 'PII-USERNAME-CANARY',
    },
    request: { url: 'https://wishtogether.gift/wishlist/PII-REQUEST-CANARY' },
    breadcrumbs: [{ message: 'PII-BREADCRUMB-CANARY' }],
    extra: { secret: 'PII-EXTRA-CANARY' },
    message: 'PII-EVENT-MESSAGE-CANARY',
    title: 'PII-EVENT-TITLE-CANARY',
    ...overrides,
  };
}

function makeGitHubIssue(overrides = {}) {
  return {
    number: 197,
    title: 'Router: load edit pages by id instead of requiring navigation extra',
    state: 'CLOSED',
    closedAt: '2026-11-22T02:35:13Z',
    url: 'https://github.com/chriskelly/wish-together/issues/197',
    ...overrides,
  };
}

function response(body, { status = 200, headers = {} } = {}) {
  return {
    ok: status >= 200 && status < 300,
    status,
    headers: {
      get(name) {
        return headers[String(name).toLowerCase()] ?? null;
      },
    },
    json: async () => body,
  };
}

function linkHeader(parts) {
  return parts
    .map(
      (part) =>
        `<https://sentry.io/next?cursor=${part.cursor}>; rel="${part.rel}"; results="${part.results}"; cursor="${part.cursor}"`,
    )
    .join(', ');
}

function fakeSentry({
  pages = {},
  events = {},
  statuses = {},
  links = {},
  eventStatuses = {},
} = {}) {
  const calls = [];
  const fetchImpl = async (url, options) => {
    calls.push({ url, options });
    const parsed = new URL(url);
    if (parsed.pathname.includes('/organizations/chris-kelly/issues/')) {
      const query = parsed.searchParams.get('query');
      if (statuses[query]) {
        return response({ detail: 'failed' }, { status: statuses[query] });
      }
      const list = pages[query] ?? [[]];
      const cursor = parsed.searchParams.get('cursor');
      const index = cursor ? Number(cursor.replace('page-', '')) : 0;
      const body = list[index] ?? [];
      const link = links[query]?.[index];
      return response(body, link ? { headers: { link } } : undefined);
    }
    const match = /\/issues\/(\d+)\/events\//.exec(parsed.pathname);
    if (match) {
      if (eventStatuses[match[1]]) {
        return response({ detail: 'failed' }, { status: eventStatuses[match[1]] });
      }
      return response(events[match[1]] ?? []);
    }
    throw new Error(`unexpected fetch ${url}`);
  };
  return { fetchImpl, calls };
}

function fakeGh(issues, { ok = true, error, truncated } = {}) {
  return () => ({
    ok,
    issues,
    error,
    truncated: truncated ?? (ok && Array.isArray(issues) && issues.length >= 1000),
  });
}

function fakeGit(status) {
  const fn = (args) => {
    fn.calls.push(args);
    return { status };
  };
  fn.calls = [];
  return fn;
}

async function runReview(t, overrides = {}) {
  const stateDir = overrides.stateDir ?? tempDir(t);
  const sentry = overrides.sentry ?? fakeSentry();
  const result = await review({
    now: NOW,
    runEnd: NOW,
    token: TOKEN,
    stateDir,
    fetchImpl: sentry.fetchImpl,
    ghList: overrides.ghList ?? fakeGh([]),
    gitRunner: overrides.gitRunner ?? fakeGit(0),
    ...overrides.review,
  });
  return { result, stateDir };
}

function stateWithProposal(overrides = {}) {
  return {
    version: 1,
    lastRunAt: '2026-11-19T00:00:00.000Z',
    lastWindowEnd: '2026-11-19T00:00:00.000Z',
    proposals: {
      '7855897843': {
        shortId: 'WISH-TOGETHER-G',
        status: 'proposed',
        firstProposedAt: '2026-11-20T00:00:00.000Z',
        lastProposedAt: '2026-11-20T00:00:00.000Z',
        lastSeenAt: '2026-11-19T05:36:51Z',
        issue: null,
        reason: null,
        ...overrides,
      },
    },
  };
}

// ---------------------------------------------------------------------------
// Window and cursor
// ---------------------------------------------------------------------------

test('first run uses 14 days', () => {
  const window = resolveWindow({ now: NOW });

  assert.equal(window.source, 'first-run');
  assert.equal(iso(window.start), '2026-11-08T04:00:00.000Z');
  assert.equal(iso(window.end), iso(NOW));
});

test('cursor run starts 5 minutes before the query snapshot', () => {
  const window = resolveWindow({
    now: NOW,
    lastWindowEnd: '2026-11-22T03:00:00.000Z',
  });

  assert.equal(window.source, 'cursor');
  assert.equal(iso(window.start), '2026-11-22T02:55:00.000Z');
});

test('a slow run anchors the next window on the query snapshot, not the run end', async (t) => {
  const t0 = new Date('2026-11-22T03:00:00Z');
  const runEnd = new Date(t0.getTime() + 10 * 60 * 1000);
  const sentry = fakeSentry();
  const { result } = await runReview(t, {
    sentry,
    review: { now: t0, runEnd },
  });

  assert.equal(result.state.lastWindowEnd, iso(t0));
  assert.equal(result.state.lastRunAt, iso(runEnd));

  const next = resolveWindow({
    now: new Date(t0.getTime() + 11 * 60 * 1000),
    lastWindowEnd: result.state.lastWindowEnd,
  });
  const lateEvent = new Date(t0.getTime() + 60 * 1000);
  assert.ok(next.start <= lateEvent && lateEvent <= next.end);
});

test('--since ISO sets the start and does not advance the cursor', async (t) => {
  const stateDir = tempDir(t);
  const state = stateWithProposal();
  saveState(stateDir, state);
  const sentry = fakeSentry({
    pages: {
      'is:unresolved': [
        [makeIssue({ id: '9', shortId: 'WISH-TOGETHER-9' })],
      ],
    },
    events: { 9: [makeEvent()] },
  });

  const { result } = await runReview(t, {
    stateDir,
    sentry,
    review: { since: '2026-11-01T00:00:00Z' },
  });

  assert.equal(result.window.source, 'override');
  assert.equal(result.window.start.toISOString(), '2026-11-01T00:00:00.000Z');
  const after = loadState(stateDir);
  assert.equal(after.lastWindowEnd, state.lastWindowEnd);
  assert.ok(after.proposals['9'], 'a backfill still records its proposal');
});

test('--since accepts a duration', () => {
  const window = resolveWindow({ now: NOW, since: '7d' });

  assert.equal(window.source, 'override');
  assert.equal(iso(window.start), '2026-11-15T04:00:00.000Z');
});

test('successful default run stores the query snapshot and run completion', async (t) => {
  const stateDir = tempDir(t);
  const { result } = await runReview(t, { stateDir });

  assert.equal(result.state.lastWindowEnd, iso(NOW));
  assert.equal(result.state.lastRunAt, iso(NOW));
});

test('a failed state write keeps the old cursor and leaves no temp file', async (t) => {
  const stateDir = tempDir(t);
  const oldState = stateWithProposal();
  saveState(stateDir, oldState);
  const before = readFileSync(join(stateDir, 'state.json'), 'utf8');

  assert.throws(
    () =>
      saveState(stateDir, { ...oldState, lastWindowEnd: iso(NOW) }, {
        writeFileSync: () => {
          throw new Error('disk full');
        },
      }),
    /could not save state/,
  );

  assert.equal(readFileSync(join(stateDir, 'state.json'), 'utf8'), before);
  assert.deepEqual(
    readdirSync(stateDir).filter((name) => name.endsWith('.tmp')),
    [],
  );
});

test('state is fsynced before it is renamed', (t) => {
  const stateDir = tempDir(t);
  const order = [];

  saveState(stateDir, stateWithProposal(), {
    openSync: (...args) => {
      order.push('open');
      return fs.openSync(...args);
    },
    writeFileSync: (...args) => {
      order.push('write');
      return fs.writeFileSync(...args);
    },
    fsyncSync: (...args) => {
      order.push('fsync');
      return fs.fsyncSync(...args);
    },
    closeSync: (...args) => {
      order.push('close');
      return fs.closeSync(...args);
    },
    renameSync: (...args) => {
      order.push('rename');
      return fs.renameSync(...args);
    },
  });

  assert.deepEqual(order, ['open', 'write', 'fsync', 'close', 'rename']);
});

test('an unreadable state file names the read error, not invalid JSON', (t) => {
  const stateDir = tempDir(t);
  fs.mkdirSync(join(stateDir, 'state.json'));

  assert.throws(() => loadState(stateDir), /could not read state file/);
});

test('a failed Sentry call keeps the cursor', async (t) => {
  const stateDir = tempDir(t);
  saveState(stateDir, stateWithProposal());
  const before = readFileSync(join(stateDir, 'state.json'), 'utf8');
  const sentry = fakeSentry({ statuses: { 'is:unresolved': 500 } });

  await assert.rejects(
    () =>
      review({
        now: NOW,
        token: TOKEN,
        stateDir,
        fetchImpl: sentry.fetchImpl,
        ghList: fakeGh([]),
      }),
    /Sentry unavailable/,
  );

  assert.equal(readFileSync(join(stateDir, 'state.json'), 'utf8'), before);
});

test('an empty successful window reports the limitation and advances', async (t) => {
  const { result, stateDir } = await runReview(t);

  assert.match(result.report, /No new production issues/);
  assert.match(result.report, /not proof/);
  assert.equal(loadState(stateDir).lastWindowEnd, iso(NOW));
});

// ---------------------------------------------------------------------------
// Sentry reads and filtering
// ---------------------------------------------------------------------------

test('the unresolved query carries project, environment, window and status', async (t) => {
  const sentry = fakeSentry({ pages: { 'is:unresolved': [[makeIssue()]] }, events: { '7855897843': [makeEvent()] } });

  await runReview(t, { sentry });

  const issueCall = sentry.calls.find((call) => call.url.includes('/organizations/chris-kelly/issues/'));
  const url = new URL(issueCall.url);
  assert.equal(url.searchParams.get('project'), 'wish-together');
  assert.equal(url.searchParams.get('environment'), 'production');
  assert.equal(url.searchParams.get('query'), 'is:unresolved');
  assert.equal(url.searchParams.get('start'), '2026-11-08T04:00:00.000Z');
  assert.equal(url.searchParams.get('end'), iso(NOW));
});

test('ignored and archived issues are combined and resolved issues are skipped', async (t) => {
  const ignored = makeIssue({ id: '1', shortId: 'WISH-TOGETHER-I', status: 'ignored', lastSeen: '2026-11-19T00:00:00Z' });
  const archived = makeIssue({ id: '2', shortId: 'WISH-TOGETHER-A', status: 'ignored', substatus: 'archived', lastSeen: '2026-11-19T00:00:00Z' });
  const resolved = makeIssue({ id: '3', shortId: 'WISH-TOGETHER-R', status: 'resolved', lastSeen: '2026-11-19T00:00:00Z' });
  const sentry = fakeSentry({
    pages: {
      'is:unresolved': [[resolved]],
      'is:ignored': [[ignored]],
      'is:archived': [[archived]],
    },
    events: {
      1: [makeEvent({ dateCreated: '2026-11-19T00:00:00Z' })],
      2: [makeEvent({ dateCreated: '2026-11-19T00:00:00Z' })],
    },
  });

  const { result } = await runReview(t, { sentry });

  assert.match(result.report, /WISH-TOGETHER-I/);
  assert.match(result.report, /WISH-TOGETHER-A/);
  assert.doesNotMatch(result.report, /WISH-TOGETHER-R/);
});

test('a status query that answers 400 is a limitation, not a crash', async (t) => {
  const sentry = fakeSentry({
    pages: { 'is:unresolved': [[makeIssue()]] },
    events: { '7855897843': [makeEvent()] },
    statuses: { 'is:ignored': 400 },
  });

  const { result } = await runReview(t, { sentry });

  assert.equal(result.exitCode, 0);
  assert.match(result.report, /Limitations/);
  assert.match(result.report, /is:ignored/);
  assert.match(result.report, /WISH-TOGETHER-G/);
});

test('a TestFlight-only issue is excluded', async (t) => {
  const issue = makeIssue({ id: '5', shortId: 'WISH-TOGETHER-5' });
  const event = makeEvent({ tags: [{ key: 'environment', value: 'testflight' }] });
  const sentry = fakeSentry({
    pages: { 'is:unresolved': [[issue]] },
    events: { 5: [event] },
  });

  const { result } = await runReview(t, { sentry });

  assert.doesNotMatch(result.report, /## 1\. WISH-TOGETHER-5/);
  assert.match(result.report, /no verified production event/);
});

test('pagination follows results=true and stops on results=false', async (t) => {
  const first = makeIssue({ id: '1', shortId: 'WISH-TOGETHER-1' });
  const second = makeIssue({ id: '2', shortId: 'WISH-TOGETHER-2' });
  const sentry = fakeSentry({
    pages: { 'is:unresolved': [[first], [second]] },
    events: {
      1: [makeEvent()],
      2: [makeEvent()],
    },
    links: {
      'is:unresolved': [
        linkHeader([{ rel: 'next', results: 'true', cursor: 'page-1' }]),
        linkHeader([{ rel: 'next', results: 'false', cursor: 'page-2' }]),
      ],
    },
  });

  const { result } = await runReview(t, { sentry });

  assert.match(result.report, /WISH-TOGETHER-1/);
  assert.match(result.report, /WISH-TOGETHER-2/);
});

test('the pagination cap is reported as a limitation', async (t) => {
  const pages = Array.from({ length: 11 }, (_, index) => [
    makeIssue({ id: String(index + 10), shortId: `WISH-TOGETHER-${index + 10}` }),
  ]);
  const links = Object.fromEntries(
    pages.map((_, index) => [
      index,
      linkHeader([{ rel: 'next', results: 'true', cursor: `page-${index + 1}` }]),
    ]),
  );
  const sentry = fakeSentry({
    pages: { 'is:unresolved': pages },
    links: { 'is:unresolved': links },
    events: Object.fromEntries(
      pages.map((page) => [page[0].id, [makeEvent()]]),
    ),
  });

  const { result } = await runReview(t, { sentry });

  assert.match(result.report, /pagination cap/i);
});

test('an event outside the window is rejected', async (t) => {
  const sentry = fakeSentry({
    pages: { 'is:unresolved': [[makeIssue()]] },
    events: { '7855897843': [makeEvent({ dateCreated: '2026-11-01T00:00:00Z' })] },
  });

  const { result } = await runReview(t, { sentry });

  assert.match(result.report, /no verified production event/);
  assert.doesNotMatch(result.report, /## 1\. WISH-TOGETHER-G/);
});

test('an unverifiable candidate does not consume a proposal slot', async (t) => {
  const issues = Array.from({ length: 21 }, (_, index) =>
    makeIssue({
      id: String(100 + index),
      shortId: `WISH-TOGETHER-${100 + index}`,
      priority: index === 0 ? 'high' : 'low',
      level: index === 0 ? 'fatal' : 'warning',
      lastSeen: index === 0 ? '2026-11-20T00:00:00Z' : '2026-11-19T00:00:00Z',
    }),
  );
  const events = Object.fromEntries(
    issues.slice(1).map((issue) => [issue.id, [makeEvent()]]),
  );
  const sentry = fakeSentry({
    pages: { 'is:unresolved': [issues] },
    events,
  });

  const { result } = await runReview(t, { sentry });

  assert.match(result.report, /Proposals: 20/);
  assert.match(result.report, /WISH-TOGETHER-100 — no verified production event/);
  assert.doesNotMatch(result.report, /beyond the 20-proposal cap/);
});

test('an event endpoint 404 skips that candidate, not the whole review', async (t) => {
  const sentry = fakeSentry({
    pages: { 'is:unresolved': [[makeIssue()]] },
    eventStatuses: { '7855897843': 404 },
  });

  const { result } = await runReview(t, { sentry });

  assert.equal(result.exitCode, 0);
  assert.match(result.report, /event endpoint returned HTTP 404/);
});

test('a web release on origin/master is verified', async (t) => {
  const git = fakeGit(0);
  const sentry = fakeSentry({
    pages: { 'is:unresolved': [[makeIssue()]] },
    events: { '7855897843': [makeEvent()] },
  });

  const { result } = await runReview(t, { sentry, gitRunner: git });

  assert.match(result.report, /Environment: verified/);
  assert.deepEqual(git.calls[0], ['merge-base', '--is-ancestor', RELEASE_SHA, 'origin/master']);
});

test('an unmerged web release is flagged unverified', async (t) => {
  const sentry = fakeSentry({
    pages: { 'is:unresolved': [[makeIssue()]] },
    events: { '7855897843': [makeEvent()] },
  });

  const { result } = await runReview(t, { sentry, gitRunner: fakeGit(1) });

  assert.match(result.report, /Environment: unverified/);
  assert.match(result.report, /Limitations/);
});

test('a web release without a matching dist is flagged unverified', async (t) => {
  const event = makeEvent({
    tags: [
      { key: 'environment', value: 'production' },
      { key: 'dist', value: 'web-ffffffffffffffffffffffffffffffffffffffff' },
    ],
  });
  const sentry = fakeSentry({
    pages: { 'is:unresolved': [[makeIssue()]] },
    events: { '7855897843': [event] },
  });

  const { result } = await runReview(t, { sentry });

  assert.match(result.report, /Environment: unverified/);
});

test('ranking is deterministic on priority, level, last seen and short id', () => {
  const high = makeIssue({ id: '1', shortId: 'B', priority: 'high', level: 'error', lastSeen: '2026-11-19T00:00:00Z' });
  const fatal = makeIssue({ id: '2', shortId: 'A', priority: 'high', level: 'fatal', lastSeen: '2026-11-19T00:00:00Z' });
  const medium = makeIssue({ id: '3', shortId: 'C', priority: 'medium', level: 'fatal', lastSeen: '2026-11-20T00:00:00Z' });

  const ranked = rankCandidates([medium, high, fatal]);

  assert.deepEqual(ranked.map((issue) => issue.shortId), ['A', 'B', 'C']);
});

test('last seen and short id break a priority and level tie', () => {
  const older = makeIssue({
    id: '4',
    shortId: 'D',
    priority: 'low',
    level: 'warning',
    lastSeen: '2026-11-10T00:00:00Z',
  });
  const newer = makeIssue({
    id: '5',
    shortId: 'E',
    priority: 'low',
    level: 'warning',
    lastSeen: '2026-11-20T00:00:00Z',
  });
  const sameA = makeIssue({
    id: '6',
    shortId: 'A',
    priority: 'low',
    level: 'warning',
    lastSeen: '2026-11-10T00:00:00Z',
  });
  const sameB = makeIssue({
    id: '7',
    shortId: 'B',
    priority: 'low',
    level: 'warning',
    lastSeen: '2026-11-10T00:00:00Z',
  });

  assert.deepEqual(
    rankCandidates([older, newer]).map((issue) => issue.shortId),
    ['E', 'D'],
  );
  assert.deepEqual(
    rankCandidates([sameB, sameA]).map((issue) => issue.shortId),
    ['A', 'B'],
  );
});

test('inherited property names sort last and display unknown', async (t) => {
  const unknown = makeIssue({
    id: '9',
    shortId: 'WISH-TOGETHER-9',
    priority: 'toString',
    level: 'constructor',
  });
  const known = makeIssue({ id: '8', shortId: 'WISH-TOGETHER-8', priority: 'low', level: 'warning' });
  const sentry = fakeSentry({
    pages: { 'is:unresolved': [[unknown, known]] },
    events: {
      9: [makeEvent()],
      8: [makeEvent()],
    },
  });

  const { result } = await runReview(t, { sentry });

  assert.match(result.report, /Priority: unknown · Level: unknown/);
  assert.match(result.report, /## 1\. WISH-TOGETHER-8/);
});

test('lifetime counts are parsed and labelled', async (t) => {
  const issue = makeIssue({ count: '9', userCount: 2 });
  const sentry = fakeSentry({
    pages: { 'is:unresolved': [[issue]] },
    events: { '7855897843': [makeEvent()] },
  });

  const { result } = await runReview(t, { sentry });

  assert.match(result.report, /Lifetime totals: 9 events, 2 users/);
});

// ---------------------------------------------------------------------------
// Ledger
// ---------------------------------------------------------------------------

test('a proposed entry with no new activity is suppressed', async (t) => {
  const stateDir = tempDir(t);
  saveState(stateDir, stateWithProposal());
  const sentry = fakeSentry({
    pages: { 'is:unresolved': [[makeIssue()]] },
    events: { '7855897843': [makeEvent()] },
  });

  const { result } = await runReview(t, { stateDir, sentry });

  assert.match(result.report, /already proposed/);
  assert.doesNotMatch(result.report, /## 1\. WISH-TOGETHER-G/);
});

test('a proposed entry with new activity is re-shown as resurfaced', async (t) => {
  const stateDir = tempDir(t);
  saveState(stateDir, stateWithProposal({ lastSeenAt: '2026-11-18T00:00:00Z' }));
  const sentry = fakeSentry({
    pages: { 'is:unresolved': [[makeIssue()]] },
    events: { '7855897843': [makeEvent()] },
  });

  const { result } = await runReview(t, { stateDir, sentry });

  assert.match(result.report, /## 1\. WISH-TOGETHER-G/);
  assert.match(result.report, /Resurfaced: yes/);
  assert.equal(
    loadState(stateDir).proposals['7855897843'].lastSeenAt,
    '2026-11-19T05:36:51Z',
  );
});

test('a handled entry with no new activity is suppressed', async (t) => {
  const stateDir = tempDir(t);
  saveState(stateDir, stateWithProposal({ status: 'handled', issue: 197 }));
  const sentry = fakeSentry({
    pages: { 'is:unresolved': [[makeIssue()]] },
    events: { '7855897843': [makeEvent()] },
  });

  const { result } = await runReview(t, { stateDir, sentry });

  assert.match(result.report, /already handled/);
  assert.doesNotMatch(result.report, /## 1\. WISH-TOGETHER-G/);
});

test('a dismissed entry with no new activity is suppressed', async (t) => {
  const stateDir = tempDir(t);
  saveState(stateDir, stateWithProposal({ status: 'dismissed', reason: 'noise' }));
  const sentry = fakeSentry({
    pages: { 'is:unresolved': [[makeIssue()]] },
    events: { '7855897843': [makeEvent()] },
  });

  const { result } = await runReview(t, { stateDir, sentry });

  assert.match(result.report, /already dismissed/);
});

test('a handled entry with a regression is shown flagged', async (t) => {
  const stateDir = tempDir(t);
  saveState(stateDir, stateWithProposal({ status: 'handled', issue: 197 }));
  const sentry = fakeSentry({
    pages: {
      'is:unresolved': [[makeIssue({ substatus: 'regressed' })]],
    },
    events: { '7855897843': [makeEvent()] },
  });

  const { result } = await runReview(t, { stateDir, sentry });

  assert.match(result.report, /## 1\. WISH-TOGETHER-G/);
  assert.match(result.report, /Resurfaced: yes/);
});

test('mark stores a valid GitHub issue number', () => {
  const state = stateWithProposal();

  markProposal(state, 'WISH-TOGETHER-G', '197');

  assert.equal(state.proposals['7855897843'].status, 'handled');
  assert.equal(state.proposals['7855897843'].issue, 197);
  assert.equal(state.proposals['7855897843'].reason, null);
});

test('dismiss stores a valid reason and rejects an unknown one', () => {
  const state = stateWithProposal();

  dismissProposal(state, 'WISH-TOGETHER-G', 'noise');
  assert.equal(state.proposals['7855897843'].status, 'dismissed');
  assert.equal(state.proposals['7855897843'].reason, 'noise');

  const other = stateWithProposal();
  assert.throws(() => dismissProposal(other, 'WISH-TOGETHER-G', 'because'), /reason/);
});

test('reopen returns an entry to proposed and clears the decision', () => {
  const state = stateWithProposal({ status: 'handled', issue: 197 });

  reopenProposal(state, 'WISH-TOGETHER-G');

  assert.equal(state.proposals['7855897843'].status, 'proposed');
  assert.equal(state.proposals['7855897843'].issue, null);
  assert.equal(state.proposals['7855897843'].reason, null);
});

test('status prints pending entries with their Sentry link', () => {
  const text = formatStatus(stateWithProposal());

  assert.match(text, /WISH-TOGETHER-G/);
  assert.match(text, /https:\/\/chris-kelly\.sentry\.io\/issues\/7855897843\//);
});

test('an unknown short id errors', () => {
  assert.throws(() => markProposal(stateWithProposal(), 'WISH-TOGETHER-Z', 1), /unknown proposal/);
});

test('state is 0600, atomic and stores no titles', (t) => {
  const stateDir = tempDir(t);
  const state = stateWithProposal();

  saveState(stateDir, state);

  const path = join(stateDir, 'state.json');
  assert.equal(statSync(path).mode & 0o777, 0o600);
  const text = readFileSync(path, 'utf8');
  assert.doesNotMatch(text, /Bad state: Future already completed/);
  assert.doesNotMatch(text, /PII/);
});

// ---------------------------------------------------------------------------
// GitHub dedupe
// ---------------------------------------------------------------------------

test('an open GitHub match is flagged, not suppressed', () => {
  const issue = makeIssue({ title: 'Firestore permission denied listing wishlists' });
  const gh = [
    makeGitHubIssue({
      number: 42,
      title: 'Firestore permission denied when listing wishlists',
      state: 'OPEN',
      closedAt: null,
    }),
  ];

  const matches = matchGitHub({ issue, events: [] }, gh, NOW);

  assert.equal(matches.length, 1);
  assert.equal(matches[0].number, 42);
  assert.equal(matches[0].state, 'OPEN');
});

test('a closed match within 90 days is flagged and an older one is ignored', () => {
  const issue = makeIssue({ title: 'Firestore permission denied listing wishlists' });
  const recent = makeGitHubIssue({
    number: 42,
    title: 'Firestore permission denied when listing wishlists',
    closedAt: '2026-08-25T00:00:00Z',
  });
  const old = makeGitHubIssue({
    number: 43,
    title: 'Firestore permission denied when listing wishlists',
    closedAt: '2026-08-23T00:00:00Z',
  });

  assert.deepEqual(
    matchGitHub({ issue, events: [] }, [recent, old], NOW).map((m) => m.number),
    [42],
  );
});

test('a stopword-only overlap does not match', () => {
  const issue = makeIssue({ title: 'error failed with state' });
  const gh = [makeGitHubIssue({ title: 'error failed with state' })];

  assert.deepEqual(matchGitHub({ issue, events: [] }, gh, NOW), []);
});

test('a reordered title still matches on two significant tokens', () => {
  const issue = makeIssue({ title: 'permission denied listing wishlists' });
  const gh = [makeGitHubIssue({ title: 'wishlists listing denied permission' })];

  assert.equal(matchGitHub({ issue, events: [] }, gh, NOW).length, 1);
});

test('a tag-only duplicate matches without the Sentry title', () => {
  const issue = makeIssue({ title: 'Unrelated report', metadata: { type: '' } });
  const events = [
    {
      event: 'firestoreError',
      route: null,
      collection: 'wishlists',
      op: 'listen',
      errorCode: 'permission-denied',
    },
  ];
  const gh = [
    makeGitHubIssue({
      title: 'Firestore permission denied when listing wishlists',
      state: 'OPEN',
      closedAt: null,
    }),
  ];

  assert.equal(matchGitHub({ issue, events }, gh, NOW).length, 1);
});

test('a generic culprit does not create a match', () => {
  const issue = makeIssue({
    title: 'Something happened',
    culprit: '?(main.dart)',
    metadata: { type: '' },
  });
  const gh = [
    makeGitHubIssue({ title: 'Something main dart', state: 'OPEN', closedAt: null }),
  ];

  assert.deepEqual(matchGitHub({ issue, events: [] }, gh, NOW), []);
});

test('a GitHub failure reports the limitation and does not advance the cursor', async (t) => {
  const stateDir = tempDir(t);
  const state = stateWithProposal();
  state.proposals = {};
  saveState(stateDir, state);
  const before = readFileSync(join(stateDir, 'state.json'), 'utf8');
  const sentry = fakeSentry({ pages: { 'is:unresolved': [[makeIssue()]] }, events: { '7855897843': [makeEvent()] } });

  const { result } = await runReview(t, {
    stateDir,
    sentry,
    ghList: fakeGh([], { ok: false, error: 'not logged in' }),
  });

  assert.equal(result.exitCode, 1);
  assert.match(result.report, /GitHub dedupe unavailable/);
  assert.doesNotMatch(result.report, /GitHub: no match/);
  assert.match(result.report, /GitHub: not checked/);
  assert.equal(readFileSync(join(stateDir, 'state.json'), 'utf8'), before);
});

test('only the GitHub number, state and constructed URL are printed', async (t) => {
  const ghIssue = makeGitHubIssue({
    title: 'Future already completed PII-GITHUB-TITLE-CANARY',
    state: 'OPEN',
    closedAt: null,
  });
  const sentry = fakeSentry({ pages: { 'is:unresolved': [[makeIssue()]] }, events: { '7855897843': [makeEvent()] } });

  const { result } = await runReview(t, { sentry, ghList: fakeGh([ghIssue]) });

  assert.match(result.report, /#197 \(OPEN\)/);
  assert.doesNotMatch(result.report, /PII-GITHUB-TITLE-CANARY/);
});

test('a 1000-issue GitHub response reports possible truncation', async (t) => {
  const sentry = fakeSentry({ pages: { 'is:unresolved': [[makeIssue()]] }, events: { '7855897843': [makeEvent()] } });
  const many = Array.from({ length: 1000 }, (_, index) =>
    makeGitHubIssue({ number: index + 1, state: 'OPEN', closedAt: null }),
  );

  const { result } = await runReview(t, { sentry, ghList: fakeGh(many) });

  assert.match(result.report, /truncated/i);
});

// ---------------------------------------------------------------------------
// Safety and CLI
// ---------------------------------------------------------------------------

test('a missing token names SENTRY_ACCESS_TOKEN', () => {
  assert.throws(() => resolveToken({}), /SENTRY_ACCESS_TOKEN/);
});

test('the upload token is rejected in favour of the read-only token', () => {
  assert.throws(
    () => resolveToken({ SENTRY_AUTH_TOKEN: 'upload' }),
    /read-only/,
  );
});

test('every Sentry call is a GET to the allowlisted API base', async (t) => {
  const sentry = fakeSentry({ pages: { 'is:unresolved': [[makeIssue()]] }, events: { '7855897843': [makeEvent()] } });

  await runReview(t, { sentry });

  assert.ok(sentry.calls.length > 0);
  for (const call of sentry.calls) {
    assert.equal(call.options.method, 'GET');
    assert.match(call.url, /^https:\/\/sentry\.io\/api\/0\//);
  }
});

test('an unknown flag, including --token, exits 2', () => {
  assert.throws(() => parseArgs(['review', '--token', 'x']), (error) => error.exitCode === 2);
  assert.throws(() => parseArgs(['review', '--nope']), (error) => error.exitCode === 2);
});

test('--help exits 0 and prints usage', async () => {
  const out = [];
  const err = [];
  const code = await main(['--help'], {
    writeOut: (value) => out.push(value),
    writeErr: (value) => err.push(value),
  });

  assert.equal(code, 0);
  assert.match(out.join(''), /Usage/);
  assert.equal(err.join(''), '');
});

test('every subcommand accepts --help', () => {
  for (const command of ['review', 'mark', 'dismiss', 'reopen', 'status']) {
    const args = parseArgs([command, '--help']);
    assert.equal(args.help, true, `${command} --help`);
  }
});

test('parseArgs accepts --state-dir and --since', () => {
  const args = parseArgs(['review', '--state-dir', '/tmp/review-state', '--since', '7d']);

  assert.equal(args.stateDir, '/tmp/review-state');
  assert.equal(args.since, '7d');
});

test('the CLI accepts --state-dir and --since and does not advance a backfill', async (t) => {
  const stateDir = tempDir(t);
  const sentry = fakeSentry({
    pages: { 'is:unresolved': [[makeIssue()]] },
    events: { '7855897843': [makeEvent()] },
  });
  const out = [];

  const code = await main(['review', '--state-dir', stateDir, '--since', '7d'], {
    env: { SENTRY_ACCESS_TOKEN: TOKEN },
    now: NOW,
    fetchImpl: sentry.fetchImpl,
    ghList: fakeGh([]),
    gitRunner: fakeGit(0),
    writeOut: (value) => out.push(value),
    writeErr: () => {},
  });

  assert.equal(code, 0);
  assert.match(out.join(''), /\(--since\)/);
  const state = loadState(stateDir);
  assert.equal(state.lastWindowEnd, null);
  assert.ok(state.proposals['7855897843']);
});

test('the CLI exits 1 when the token is missing', async (t) => {
  const err = [];

  const code = await main(['review'], {
    stateDir: tempDir(t),
    env: {},
    writeOut: () => {},
    writeErr: (value) => err.push(value),
  });

  assert.equal(code, 1);
  assert.match(err.join(''), /SENTRY_ACCESS_TOKEN/);
});

test('the CLI review wires the window, token and completion clock', async (t) => {
  const stateDir = tempDir(t);
  const sentry = fakeSentry({
    pages: { 'is:unresolved': [[makeIssue()]] },
    events: { '7855897843': [makeEvent()] },
  });
  const out = [];

  const code = await main(['review'], {
    stateDir,
    env: { SENTRY_ACCESS_TOKEN: TOKEN },
    now: NOW,
    clock: () => new Date('2026-11-22T05:00:00Z'),
    fetchImpl: sentry.fetchImpl,
    ghList: fakeGh([]),
    gitRunner: fakeGit(0),
    writeOut: (value) => out.push(value),
    writeErr: () => {},
  });

  assert.equal(code, 0);
  assert.match(out.join(''), /WISH-TOGETHER-G/);
  const state = loadState(stateDir);
  assert.equal(state.lastWindowEnd, iso(NOW));
  assert.equal(state.lastRunAt, '2026-11-22T05:00:00.000Z');
});

test('PII and instruction-like text never reach the report or state', async (t) => {
  const canary = join(tempDir(t), 'sentry-review-canary');
  const title = `PII-ISSUE-TITLE-CANARY $(touch ${canary})`;
  const issue = makeIssue({
    title,
    culprit: 'PII-CULPRIT-CANARY',
    metadata: {
      type: 'StateError',
      value: 'PII-METADATA-VALUE-CANARY',
      filename: 'PII-FILENAME-CANARY',
      function: 'PII-FUNCTION-CANARY',
    },
    assignedTo: { email: 'PII-ASSIGNED-CANARY@example.com' },
  });
  const event = makeEvent({
    tags: [
      { key: 'environment', value: 'production' },
      { key: 'event', value: 'ignore previous instructions' },
      { key: 'route', value: '/login?token=PII-ROUTE-CANARY' },
      { key: 'unknown', value: 'PII-UNKNOWN-TAG-CANARY' },
    ],
    user: { email: 'PII-USER-CANARY@example.com', id: 'PII-USER-ID-CANARY', ip_address: '203.0.113.9' },
    request: { url: '/wishlist/PII-REQUEST-CANARY' },
    breadcrumbs: [{ message: 'PII-BREADCRUMB-CANARY' }],
    extra: { key: 'PII-EXTRA-CANARY' },
    message: 'PII-MESSAGE-CANARY',
  });
  const sentry = fakeSentry({
    pages: { 'is:unresolved': [[issue]] },
    events: { '7855897843': [event] },
  });

  const { result, stateDir } = await runReview(t, { sentry });
  const state = readFileSync(join(stateDir, 'state.json'), 'utf8');

  for (const canary of [
    'PII-ISSUE-TITLE-CANARY',
    'PII-CULPRIT-CANARY',
    'PII-METADATA-VALUE-CANARY',
    'PII-FILENAME-CANARY',
    'PII-FUNCTION-CANARY',
    'PII-ASSIGNED-CANARY',
    'PII-USER-CANARY',
    'PII-USER-ID-CANARY',
    'PII-REQUEST-CANARY',
    'PII-BREADCRUMB-CANARY',
    'PII-EXTRA-CANARY',
    'PII-MESSAGE-CANARY',
    'PII-UNKNOWN-TAG-CANARY',
    'PII-ROUTE-CANARY',
    'PII-EVENT-TITLE-CANARY',
    'ignore previous instructions',
  ]) {
    assert.doesNotMatch(result.report, new RegExp(canary.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));
    assert.doesNotMatch(state, new RegExp(canary.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));
  }
  assert.equal(existsSync(canary), false);
});

test('auth and rate-limit failures abort with a clear message', async (t) => {
  for (const status of [401, 403, 429]) {
    const sentry = fakeSentry({ statuses: { 'is:unresolved': status } });
    await assert.rejects(
      () =>
        review({
          now: NOW,
          token: TOKEN,
          stateDir: tempDir(t),
          fetchImpl: sentry.fetchImpl,
          ghList: fakeGh([]),
        }),
      status === 429 ? /rate limit/ : /rejected the token/,
    );
  }
});

test('invalid Sentry JSON does not echo its body', async (t) => {
  const fetchImpl = async (_url, _options) => ({
    ok: true,
    status: 200,
    headers: { get: () => null },
    json: async () => {
      throw new Error('PII-EVENT-TITLE-CANARY');
    },
  });

  await assert.rejects(
    () =>
      review({
        now: NOW,
        token: TOKEN,
        stateDir: tempDir(t),
        fetchImpl,
        ghList: fakeGh([]),
      }),
    (error) => {
      assert.match(error.message, /Sentry returned invalid JSON/);
      assert.doesNotMatch(error.message, /PII-EVENT-TITLE-CANARY/);
      return true;
    },
  );
});
test('the GitHub command uses constant argv', () => {
  let captured;
  listGitHubIssues({
    run: (command, args) => {
      captured = { command, args };
      return { status: 0, stdout: '[]', stderr: '' };
    },
  });

  assert.equal(captured.command, 'gh');
  assert.ok(captured.args.includes('chriskelly/wish-together'));
  assert.ok(!captured.args.join(' ').includes('PII'));
});

test('a gh failure is a fixed message, not its stderr', () => {
  const result = listGitHubIssues({
    run: () => ({ status: 1, stdout: '', stderr: 'PII-GITHUB-TITLE-CANARY' }),
  });

  assert.equal(result.ok, false);
  assert.match(result.error, /gh auth status/);
  assert.doesNotMatch(result.error, /PII-GITHUB-TITLE-CANARY/);
});

test('invalid gh JSON is a fixed error, not the body prefix', () => {
  const result = listGitHubIssues({
    run: () => ({ status: 0, stdout: 'PII-GITHUB-TITLE-CANARY not json', stderr: '' }),
  });

  assert.equal(result.ok, false);
  assert.match(result.error, /invalid JSON/);
  assert.doesNotMatch(result.error, /PII-GITHUB-TITLE-CANARY/);
});

test('a non-array gh JSON shape is rejected', () => {
  for (const stdout of ['null', '{}']) {
    const result = listGitHubIssues({
      run: () => ({ status: 0, stdout, stderr: '' }),
    });
    assert.equal(result.ok, false);
    assert.match(result.error, /unexpected JSON shape/);
  }
});

test('a non-array ghList payload is treated as dedupe unavailable', async (t) => {
  const sentry = fakeSentry({
    pages: { 'is:unresolved': [[makeIssue()]] },
    events: { '7855897843': [makeEvent()] },
  });

  const { result } = await runReview(t, {
    sentry,
    ghList: () => ({ ok: true, issues: null }),
  });

  assert.equal(result.exitCode, 1);
  assert.match(result.report, /GitHub dedupe unavailable/);
});

test('mark works without a Sentry token', async (t) => {
  const stateDir = tempDir(t);
  saveState(stateDir, stateWithProposal());
  const out = [];
  const code = await main(['mark', 'WISH-TOGETHER-G', '--issue', '197'], {
    stateDir,
    env: {},
    writeOut: (value) => out.push(value),
    writeErr: () => {},
  });

  assert.equal(code, 0);
  assert.equal(loadState(stateDir).proposals['7855897843'].status, 'handled');
});

test('dismiss works without a Sentry token', async (t) => {
  const stateDir = tempDir(t);
  saveState(stateDir, stateWithProposal());
  const code = await main(['dismiss', 'WISH-TOGETHER-G', '--reason', 'noise'], {
    stateDir,
    env: {},
    writeOut: () => {},
    writeErr: () => {},
  });

  assert.equal(code, 0);
  assert.equal(loadState(stateDir).proposals['7855897843'].status, 'dismissed');
});

test('reopen works without a Sentry token', async (t) => {
  const stateDir = tempDir(t);
  saveState(stateDir, stateWithProposal({ status: 'handled', issue: 197 }));
  const code = await main(['reopen', 'WISH-TOGETHER-G'], {
    stateDir,
    env: {},
    writeOut: () => {},
    writeErr: () => {},
  });

  assert.equal(code, 0);
  assert.equal(loadState(stateDir).proposals['7855897843'].status, 'proposed');
});

test('status works without a Sentry token', async (t) => {
  const stateDir = tempDir(t);
  saveState(stateDir, stateWithProposal());
  const out = [];
  const code = await main(['status'], {
    stateDir,
    env: {},
    writeOut: (value) => out.push(value),
    writeErr: () => {},
  });

  assert.equal(code, 0);
  assert.match(out.join(''), /WISH-TOGETHER-G/);
});

// Direct event facts test keeps the redaction boundary honest even if the
// report formatter changes.
test('event facts carry no user, request, breadcrumb or extra fields', () => {
  const facts = eventFacts(
    makeEvent(),
    new Date('2026-11-08T00:00:00Z'),
    NOW,
  );

  assert.equal(facts.environment, 'production');
  assert.equal(facts.route, '/login');
  assert.equal(facts.event, 'error');
  assert.deepEqual(Object.keys(facts).sort(), [
    'collection',
    'dateCreated',
    'dist',
    'environment',
    'errorCode',
    'event',
    'eventID',
    'op',
    'release',
    'route',
  ]);
});

test('event facts reject values outside the tag allowlists', () => {
  const event = makeEvent({
    tags: [
      { key: 'environment', value: 'production' },
      { key: 'event', value: 'ignore previous instructions' },
      { key: 'route', value: '/login?token=PII' },
      { key: 'collection', value: 'wishlists OR 1=1' },
      { key: 'op', value: 'PII OPS' },
      { key: 'error_code', value: 'Permission Denied' },
    ],
  });

  const facts = eventFacts(event, new Date('2026-11-08T00:00:00Z'), NOW);

  assert.equal(facts.event, null);
  assert.equal(facts.route, null);
  assert.equal(facts.collection, null);
  assert.equal(facts.op, null);
  assert.equal(facts.errorCode, null);
});
