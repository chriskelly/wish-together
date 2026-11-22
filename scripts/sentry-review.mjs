// Reviews WishTogether's production Sentry data over a time window and prints
// safe, ranked proposals for the operator. Read-only toward Sentry and GitHub;
// the only write is the local cursor/proposal ledger.
//
// Run `node scripts/sentry-review.mjs --help` for usage.

import { spawnSync } from 'node:child_process';
import {
  closeSync,
  existsSync,
  fsyncSync,
  mkdirSync,
  openSync,
  readFileSync,
  renameSync,
  unlinkSync,
  writeFileSync,
} from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';

import { isEntryPoint } from './module-entry.mjs';

const API_BASE = 'https://sentry.io/api/0';
const SENTRY_ORG = 'chris-kelly';
const SENTRY_PROJECT = 'wish-together';
const SENTRY_WEB = 'https://chris-kelly.sentry.io';
const GITHUB_REPO = 'chriskelly/wish-together';
const GITHUB_WEB = 'https://github.com';
const DEFAULT_WINDOW_MS = 14 * 24 * 60 * 60 * 1000;
const OVERLAP_MS = 5 * 60 * 1000;
const MAX_PAGES = 10;
const MAX_PROPOSALS = 20;
const EVENTS_PER_ISSUE = 3;
const CLOSED_WITHIN_DAYS = 90;
const GITHUB_LIMIT = 1000;
const STATE_VERSION = 1;
const STATUS_QUERIES = ['is:unresolved', 'is:ignored', 'is:archived'];
const PRIORITY_RANK = Object.freeze(
  Object.assign(Object.create(null), { high: 3, medium: 2, low: 1 }),
);
const LEVEL_RANK = Object.freeze(
  Object.assign(Object.create(null), { fatal: 4, error: 3, warning: 2, info: 1, debug: 0 }),
);
const EVENT_FAMILIES = new Set([
  'error',
  'firestoreError',
  'authState',
  'updateGate',
  'claimAction',
  'sessionStart',
  'routeChanged',
  'appCheck',
]);
const COLLECTIONS = new Set(['wishlists', 'items', 'groups', 'users', 'other']);
const DISMISS_REASONS = new Set(['duplicate', 'not-actionable', 'noise', 'fixed']);
const STATUSES = new Set(['unresolved', 'ignored', 'resolved']);
const LEDGER_STATUSES = new Set(['proposed', 'handled', 'dismissed']);
const STOPWORDS = new Set([
  'error',
  'failure',
  'failed',
  'exception',
  'bad',
  'state',
  'when',
  'with',
  'from',
  'this',
  'that',
]);
const SAFE_TIMESTAMP = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z$/;

const USAGE = `Usage: node scripts/sentry-review.mjs <command> [options]

Commands:
  review                              review production issues since the last run
  mark <shortId> [--issue <number>]   record that the operator filed the proposal
  dismiss <shortId> --reason <reason> record a declined proposal
  reopen <shortId>                    return a handled/dismissed proposal to pending
  status                              list the proposal ledger

Options:
  --since <iso|7d|14d>  override the review window (does not advance the cursor)
  --state-dir <path>    override the local state directory
  --help                show this help
`;

export class ReviewError extends Error {
  constructor(message, exitCode = 1) {
    super(message);
    this.name = 'ReviewError';
    this.exitCode = exitCode;
  }
}

function emptyState() {
  return {
    version: STATE_VERSION,
    lastRunAt: null,
    lastWindowEnd: null,
    proposals: {},
  };
}

function nextValue(flag, tokens) {
  const value = tokens.shift();
  if (value === undefined || value.startsWith('--')) {
    throw new ReviewError(`${flag} needs a value`, 2);
  }
  return value;
}

export function parseArgs(argv) {
  const args = {
    command: 'review',
    shortId: null,
    since: null,
    stateDir: null,
    issue: null,
    reason: null,
    help: false,
  };
  const tokens = [...argv];

  if (tokens[0] === '--help' || tokens[0] === '-h') {
    args.help = true;
    return args;
  }
  if (tokens.length > 0) {
    const command = tokens.shift();
    if (!['review', 'mark', 'dismiss', 'reopen', 'status'].includes(command)) {
      throw new ReviewError(`unknown command: ${command}`, 2);
    }
    args.command = command;
  }
  if (args.command === 'mark' || args.command === 'dismiss' || args.command === 'reopen') {
    if (tokens[0] === '--help' || tokens[0] === '-h') {
      args.help = true;
      return args;
    }
    const shortId = tokens.shift();
    if (!shortId || shortId.startsWith('--')) {
      throw new ReviewError(`${args.command} needs a short id`, 2);
    }
    args.shortId = shortId;
  }

  while (tokens.length > 0) {
    const flag = tokens.shift();
    if (flag === '--help' || flag === '-h') {
      args.help = true;
    } else if (flag === '--state-dir') {
      args.stateDir = nextValue(flag, tokens);
    } else if (flag === '--since') {
      args.since = nextValue(flag, tokens);
    } else if (flag === '--issue') {
      args.issue = nextValue(flag, tokens);
    } else if (flag === '--reason') {
      args.reason = nextValue(flag, tokens);
    } else {
      throw new ReviewError(`unknown flag: ${flag}`, 2);
    }
  }

  if (args.since !== null && args.command !== 'review') {
    throw new ReviewError('--since is only valid for review', 2);
  }
  if (args.issue !== null && args.command !== 'mark') {
    throw new ReviewError('--issue is only valid for mark', 2);
  }
  if (args.reason !== null && args.command !== 'dismiss') {
    throw new ReviewError('--reason is only valid for dismiss', 2);
  }
  return args;
}

export function resolveToken(env = process.env) {
  const access = typeof env.SENTRY_ACCESS_TOKEN === 'string' ? env.SENTRY_ACCESS_TOKEN.trim() : '';
  if (access) {
    return access;
  }
  const upload = typeof env.SENTRY_AUTH_TOKEN === 'string' ? env.SENTRY_AUTH_TOKEN.trim() : '';
  if (upload) {
    throw new ReviewError(
      'SENTRY_AUTH_TOKEN is the upload token; set SENTRY_ACCESS_TOKEN ' +
        '(read-only: org:read, project:read, event:read) instead.',
    );
  }
  throw new ReviewError(
    'SENTRY_ACCESS_TOKEN is not set. Create a read-only token with ' +
      'org:read, project:read and event:read.',
  );
}

function parseSince(value, end) {
  const duration = /^(\d+)([dhm])$/.exec(value);
  if (duration) {
    const multiplier = { d: 86400000, h: 3600000, m: 60000 }[duration[2]];
    return new Date(end.getTime() - Number(duration[1]) * multiplier);
  }
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
}

export function resolveWindow({ now = new Date(), lastWindowEnd, since } = {}) {
  const end = new Date(now);
  if (Number.isNaN(end.getTime())) {
    throw new ReviewError('the review clock is not a valid date');
  }

  let start;
  let source;
  if (since) {
    start = parseSince(since, end);
    if (!start) {
      throw new ReviewError('--since must be an ISO timestamp or a duration such as 7d');
    }
    source = 'override';
  } else if (lastWindowEnd) {
    const anchor = new Date(lastWindowEnd);
    if (Number.isNaN(anchor.getTime())) {
      throw new ReviewError('the saved cursor is not a valid date; pass --since');
    }
    start = new Date(anchor.getTime() - OVERLAP_MS);
    source = 'cursor';
  } else {
    start = new Date(end.getTime() - DEFAULT_WINDOW_MS);
    source = 'first-run';
  }

  if (start.getTime() >= end.getTime()) {
    throw new ReviewError('window start must be before end');
  }
  return { start, end, source };
}

export function loadState(stateDir) {
  const path = join(stateDir, 'state.json');
  if (!existsSync(path)) {
    return emptyState();
  }
  let text;
  try {
    text = readFileSync(path, 'utf8');
  } catch (error) {
    throw new ReviewError(
      `could not read state file ${path}: ${error.code ?? error.message}`,
    );
  }
  let parsed;
  try {
    parsed = JSON.parse(text);
  } catch {
    throw new ReviewError(
      `state file ${path} is not valid JSON; fix or remove it before reviewing.`,
    );
  }
  if (
    !parsed ||
    parsed.version !== STATE_VERSION ||
    typeof parsed.proposals !== 'object' ||
    parsed.proposals === null ||
    Array.isArray(parsed.proposals)
  ) {
    throw new ReviewError(
      `state file ${path} has an unsupported shape; fix or remove it before reviewing.`,
    );
  }
  return parsed;
}

export function saveState(stateDir, state, fsOps = {}) {
  const open = fsOps.openSync ?? openSync;
  const write = fsOps.writeFileSync ?? writeFileSync;
  const sync = fsOps.fsyncSync ?? fsyncSync;
  const close = fsOps.closeSync ?? closeSync;
  const rename = fsOps.renameSync ?? renameSync;
  const unlink = fsOps.unlinkSync ?? unlinkSync;
  const mkdir = fsOps.mkdirSync ?? mkdirSync;
  const path = join(stateDir, 'state.json');
  const temp = join(
    stateDir,
    `.state.${process.pid}.${Date.now()}.${Math.random().toString(16).slice(2)}.tmp`,
  );

  try {
    mkdir(stateDir, { recursive: true });
    const descriptor = open(temp, 'w', 0o600);
    try {
      write(descriptor, `${JSON.stringify(state, null, 2)}\n`);
      sync(descriptor);
    } finally {
      close(descriptor);
    }
    rename(temp, path);
  } catch (error) {
    try {
      unlink(temp);
    } catch {
      // The temp file may never have been created.
    }
    throw new ReviewError(`could not save state: ${error.message}`);
  }
}

function safeShortId(value) {
  return typeof value === 'string' && /^[A-Z0-9-]{1,40}$/.test(value) ? value : null;
}

function safeType(value) {
  return typeof value === 'string' && /^[A-Za-z0-9_.$:-]{1,80}$/.test(value) ? value : null;
}

function safeStatus(value) {
  return STATUSES.has(value) ? value : 'unknown';
}

function safeLedgerStatus(value) {
  return LEDGER_STATUSES.has(value) ? value : 'unknown';
}

function safeLine(value, max = 200) {
  if (typeof value !== 'string') {
    return '';
  }
  return value
    .replace(/[\u0000-\u001f\u007f-\u009f]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, max);
}

function safeTag(key, value) {
  if (typeof value !== 'string') {
    return null;
  }
  switch (key) {
    case 'environment':
      return /^[a-z]+$/.test(value) ? value : null;
    case 'release':
      return /^wishtogether@([0-9a-f]{7,40}|[0-9]{1,7})$/.test(value) ? value : null;
    case 'dist':
      return /^(web-[0-9a-f]{7,40}|ios-[0-9]+)$/.test(value) ? value : null;
    case 'route':
      return /^\/[A-Za-z0-9_/*:.-]{0,120}$/.test(value) ? value : null;
    case 'event':
      return EVENT_FAMILIES.has(value) ? value : null;
    case 'error_code':
      return /^[a-z0-9-]{1,60}$/.test(value) ? value : null;
    case 'collection':
      return COLLECTIONS.has(value) ? value : null;
    case 'op':
      return /^[A-Za-z]{1,32}$/.test(value) ? value : null;
    default:
      return null;
  }
}

function isoOrUnknown(value) {
  if (typeof value !== 'string' || !SAFE_TIMESTAMP.test(value)) {
    return 'unknown';
  }
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? 'unknown' : value;
}

function issueLink(id) {
  return /^\d+$/.test(String(id)) ? `${SENTRY_WEB}/issues/${id}/` : 'unknown';
}

function eventLink(id, eventID) {
  if (!/^\d+$/.test(String(id)) || !/^[0-9a-f]{32}$/.test(eventID)) {
    return 'unknown';
  }
  return `${SENTRY_WEB}/issues/${id}/events/${eventID}/`;
}

function issueLabel(issue) {
  return safeShortId(issue.shortId) ?? `ISSUE-${issue.id}`;
}

export function eventFacts(event, start, end) {
  if (!event || typeof event !== 'object') {
    return null;
  }
  const created = new Date(event.dateCreated);
  if (
    Number.isNaN(created.getTime()) ||
    created.getTime() < new Date(start).getTime() ||
    created.getTime() > new Date(end).getTime()
  ) {
    return null;
  }
  if (!/^[0-9a-f]{32}$/.test(String(event.eventID))) {
    return null;
  }

  const tags = {};
  for (const tag of Array.isArray(event.tags) ? event.tags : []) {
    if (tag && typeof tag.key === 'string' && typeof tag.value === 'string') {
      tags[tag.key] = tag.value;
    }
  }

  const facts = {
    eventID: event.eventID,
    dateCreated: created.toISOString(),
    environment: safeTag('environment', tags.environment),
    release: safeTag('release', tags.release),
    dist: safeTag('dist', tags.dist),
    route: safeTag('route', tags.route),
    event: safeTag('event', tags.event),
    errorCode: safeTag('error_code', tags.error_code),
    collection: safeTag('collection', tags.collection),
    op: safeTag('op', tags.op),
  };
  return facts.environment === 'production' ? facts : null;
}

function compareIssues(a, b) {
  return (
    (PRIORITY_RANK[b.priority] ?? 0) - (PRIORITY_RANK[a.priority] ?? 0) ||
    (LEVEL_RANK[b.level] ?? 0) - (LEVEL_RANK[a.level] ?? 0) ||
    Date.parse(b.lastSeen) - Date.parse(a.lastSeen) ||
    String(a.shortId ?? '').localeCompare(String(b.shortId ?? ''))
  );
}

export function rankCandidates(candidates) {
  return [...candidates].sort(compareIssues);
}

function tokenSet(text) {
  return new Set(
    String(text ?? '')
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, ' ')
      .split(' ')
      .filter((token) => token.length >= 4 && !STOPWORDS.has(token)),
  );
}

function proposalTokens(proposal) {
  const issue = proposal.issue ?? {};
  const pieces = [issue.title, safeType(issue.metadata?.type)];
  for (const fact of proposal.events ?? []) {
    pieces.push(fact.event, fact.route, fact.collection, fact.op, fact.errorCode);
  }
  return tokenSet(pieces.filter(Boolean).join(' '));
}

export function matchGitHub(proposal, ghIssues, now) {
  const cutoff = new Date(now).getTime() - CLOSED_WITHIN_DAYS * 86400000;
  const tokens = proposalTokens(proposal);
  const matches = [];

  for (const issue of ghIssues ?? []) {
    const number = Number(issue.number);
    if (!Number.isInteger(number) || number <= 0) {
      continue;
    }
    if (issue.state !== 'OPEN') {
      const closed = Date.parse(issue.closedAt);
      if (!Number.isFinite(closed) || closed < cutoff) {
        continue;
      }
    }
    const shared = [...tokenSet(issue.title)].filter((token) =>
      tokens.has(token),
    );
    if (shared.length < 2) {
      continue;
    }
    matches.push({
      number,
      state: issue.state,
      url: `${GITHUB_WEB}/${GITHUB_REPO}/issues/${number}`,
      shared: shared.length,
    });
  }

  return matches
    .sort(
      (a, b) =>
        (a.state === 'OPEN' ? 0 : 1) - (b.state === 'OPEN' ? 0 : 1) ||
        b.shared - a.shared ||
        a.number - b.number,
    )
    .slice(0, 3);
}

function findProposal(state, shortId) {
  for (const entry of Object.values(state.proposals ?? {})) {
    if (entry.shortId === shortId) {
      return entry;
    }
  }
  return null;
}

function requireProposal(state, shortId) {
  const entry = findProposal(state, shortId);
  if (!entry) {
    throw new ReviewError(`unknown proposal ${shortId}`);
  }
  return entry;
}

export function markProposal(state, shortId, issue) {
  const entry = requireProposal(state, shortId);
  if (issue === undefined || issue === null) {
    entry.issue = null;
  } else {
    const text = String(issue);
    if (!/^[1-9]\d{0,8}$/.test(text)) {
      throw new ReviewError('--issue must be a positive GitHub issue number');
    }
    entry.issue = Number(text);
  }
  entry.reason = null;
  entry.status = 'handled';
  return state;
}

export function dismissProposal(state, shortId, reason) {
  const entry = requireProposal(state, shortId);
  if (!DISMISS_REASONS.has(reason)) {
    throw new ReviewError(
      '--reason must be one of duplicate, not-actionable, noise, fixed',
    );
  }
  entry.status = 'dismissed';
  entry.reason = reason;
  entry.issue = null;
  return state;
}

export function reopenProposal(state, shortId) {
  const entry = requireProposal(state, shortId);
  entry.status = 'proposed';
  entry.reason = null;
  entry.issue = null;
  return state;
}

export function formatStatus(state) {
  const entries = Object.entries(state.proposals ?? {});
  if (entries.length === 0) {
    return 'No proposals recorded.\n';
  }
  const lines = ['# Sentry review ledger', ''];
  for (const [id, entry] of entries) {
    let decision = safeLedgerStatus(entry.status);
    if (Number.isInteger(entry.issue) && entry.issue > 0) {
      decision += ` as #${entry.issue}`;
    }
    if (DISMISS_REASONS.has(entry.reason)) {
      decision += ` (${entry.reason})`;
    }
    lines.push(`- ${safeShortId(entry.shortId) ?? 'unknown'} — ${decision} — ${issueLink(id)}`);
  }
  return `${lines.join('\n')}\n`;
}

function display(value, ranks) {
  return ranks[value] === undefined ? 'unknown' : value;
}

function parseCount(value) {
  const number = Number.parseInt(value, 10);
  return Number.isFinite(number) ? number : 0;
}

function sourceLabel(source) {
  return (
    {
      'first-run': 'first run',
      cursor: 'since last run',
      override: '--since',
    }[source] ?? source
  );
}

function formatReport(result) {
  const { window, totalIssues, newIssues, proposals, skipped, limitations } = result;
  const lines = [
    `# Sentry production review — ${window.end.toISOString()}`,
    '',
    `Window: ${window.start.toISOString()} → ${window.end.toISOString()} (${sourceLabel(window.source)})`,
    '',
    `Issues with production activity: ${totalIssues}. New after dedupe: ${newIssues}. Proposals: ${proposals.length}.`,
    '',
  ];

  if (proposals.length === 0) {
    lines.push(
      'No new production issues in this window. This is not proof the app is healthy; run the checklist in docs/diagnostics.md → Before concluding "nothing happened".',
      '',
    );
  }

  proposals.forEach((proposal, index) => {
    const issue = proposal.issue;
    const event = proposal.events[0] ?? {};
    const family =
      [event.event, event.route, event.collection, event.op].filter(Boolean).join(' · ') ||
      safeType(issue.metadata?.type) ||
      'unclassified';
    const resurfaced = proposal.resurfaced ? ' · Resurfaced: yes' : '';
    lines.push(`## ${index + 1}. ${issueLabel(issue)} — ${family}`);
    lines.push(
      `Priority: ${display(issue.priority, PRIORITY_RANK)} · Level: ${display(issue.level, LEVEL_RANK)} · Status: ${safeStatus(issue.status)}${resurfaced}`,
    );
    lines.push(`Last seen: ${isoOrUnknown(issue.lastSeen)}`);
    lines.push(
      `Lifetime totals: ${parseCount(issue.count)} events, ${parseCount(issue.userCount)} users`,
    );
    lines.push(`Sentry: ${issueLink(issue.id)}`);
    lines.push('Events:');
    for (const fact of proposal.events) {
      lines.push(`- ${eventLink(issue.id, fact.eventID)}`);
    }
    if (proposal.events.length === 0) {
      lines.push('- none verified');
    }
    lines.push(
      proposal.environment === 'unverified'
        ? 'Environment: unverified'
        : 'Environment: verified',
    );
    if (proposal.githubMatches == null) {
      lines.push('GitHub: not checked (dedupe unavailable)');
    } else if (proposal.githubMatches.length === 0) {
      lines.push('GitHub: no match');
    } else {
      for (const match of proposal.githubMatches) {
        const state = match.state === 'OPEN' ? 'OPEN' : 'CLOSED';
        lines.push(`GitHub: #${match.number} (${state}) ${match.url}`);
      }
    }
    lines.push('');
  });

  if (skipped.length > 0) {
    lines.push('## Skipped', '');
    for (const item of skipped) {
      lines.push(`- ${item}`);
    }
    lines.push('');
  }

  if (limitations.length > 0) {
    lines.push('## Limitations', '');
    for (const item of limitations) {
      lines.push(`- ${item}`);
    }
    lines.push('');
  }

  return `${lines.join('\n')}`;
}

function githubArgs() {
  return [
    'issue',
    'list',
    '--repo',
    GITHUB_REPO,
    '--state',
    'all',
    '--limit',
    String(GITHUB_LIMIT),
    '--json',
    'number,title,state,closedAt,url',
  ];
}

export function listGitHubIssues({ run = spawnSync } = {}) {
  const result = run('gh', githubArgs(), { encoding: 'utf8', timeout: 30000 });
  if (result.status !== 0) {
    return {
      ok: false,
      error: `gh issue list failed (exit ${result.status}); check gh auth status.`,
      issues: [],
      truncated: false,
    };
  }
  let issues;
  try {
    issues = JSON.parse(result.stdout || '[]');
  } catch {
    return {
      ok: false,
      error: 'gh returned invalid JSON.',
      issues: [],
      truncated: false,
    };
  }
  if (!Array.isArray(issues)) {
    return {
      ok: false,
      error: 'gh returned an unexpected JSON shape.',
      issues: [],
      truncated: false,
    };
  }
  return {
    ok: true,
    issues,
    truncated: issues.length >= GITHUB_LIMIT,
  };
}

async function getJson(fetchImpl, token, url) {
  const response = await fetchImpl(url, {
    method: 'GET',
    headers: {
      Authorization: `Bearer ${token}`,
      Accept: 'application/json',
    },
  });
  if (!response.ok) {
    if (response.status === 401 || response.status === 403) {
      const error = new ReviewError(
        `Sentry rejected the token (HTTP ${response.status}). Use a read-only token with org:read, project:read, event:read.`,
      );
      error.httpStatus = response.status;
      throw error;
    }
    if (response.status === 429) {
      const retry = safeLine(response.headers?.get?.('retry-after'), 40);
      const error = new ReviewError(
        `Sentry rate limit (HTTP 429). Retry after ${retry || 'a short wait'}.`,
      );
      error.httpStatus = 429;
      throw error;
    }
    const error = new ReviewError(
      response.status === 400
        ? 'Sentry rejected the query (HTTP 400).'
        : `Sentry unavailable (HTTP ${response.status}).`,
    );
    error.httpStatus = response.status;
    throw error;
  }
  let body;
  try {
    body = await response.json();
  } catch {
    throw new ReviewError('Sentry returned invalid JSON.');
  }
  return { body, headers: response.headers };
}

function issueUrl({ query, start, end, cursor }) {
  const params = new URLSearchParams({
    project: SENTRY_PROJECT,
    environment: 'production',
    start: new Date(start).toISOString(),
    end: new Date(end).toISOString(),
    query,
    limit: '100',
  });
  if (cursor) {
    params.set('cursor', cursor);
  }
  return `${API_BASE}/organizations/${SENTRY_ORG}/issues/?${params.toString()}`;
}

function nextCursor(linkHeader) {
  if (!linkHeader) {
    return null;
  }
  for (const part of String(linkHeader).split(/,\s*(?=<)/)) {
    if (!/rel="next"/.test(part)) {
      continue;
    }
    if (!/results="true"/.test(part)) {
      return null;
    }
    const cursor = /cursor="([^"]+)"/.exec(part);
    return cursor ? cursor[1] : null;
  }
  return null;
}

async function fetchIssuePages({ fetchImpl, token, query, start, end, limitations }) {
  const issues = [];
  let cursor = null;
  for (let page = 0; page < MAX_PAGES; page += 1) {
    const { body, headers } = await getJson(
      fetchImpl,
      token,
      issueUrl({ query, start, end, cursor }),
    );
    if (!Array.isArray(body)) {
      throw new ReviewError('Sentry returned an unexpected issue list.');
    }
    issues.push(...body);
    const next = nextCursor(headers?.get?.('link'));
    if (!next) {
      return issues;
    }
    if (page === MAX_PAGES - 1) {
      limitations.push(
        `Sentry pagination cap reached after ${MAX_PAGES} pages; results may be incomplete.`,
      );
      return issues;
    }
    cursor = next;
  }
}

async function fetchVerifiedEvents({ fetchImpl, token, issueId, start, end }) {
  const params = new URLSearchParams({
    environment: 'production',
    start: new Date(start).toISOString(),
    end: new Date(end).toISOString(),
    per_page: String(EVENTS_PER_ISSUE),
    full: 'false',
  });
  const { body } = await getJson(
    fetchImpl,
    token,
    `${API_BASE}/issues/${issueId}/events/?${params.toString()}`,
  );
  if (!Array.isArray(body)) {
    return [];
  }
  return body
    .map((event) => eventFacts(event, start, end))
    .filter(Boolean)
    .slice(0, EVENTS_PER_ISSUE);
}

function isWindowed(issue, window) {
  const lastSeen = Date.parse(issue.lastSeen);
  return (
    Number.isFinite(lastSeen) &&
    lastSeen >= window.start.getTime() &&
    lastSeen <= window.end.getTime()
  );
}

function rawTimestamp(value, fallback) {
  return isoOrUnknown(value) === 'unknown' ? fallback : value;
}

function verifyEnvironment(facts, gitRunner, webCache) {
  for (const fact of facts) {
    if (!fact.dist || !fact.dist.startsWith('web-')) {
      continue;
    }
    const distSha = fact.dist.slice(4);
    const releaseSha = /^wishtogether@([0-9a-f]{7,40})$/.exec(
      fact.release ?? '',
    )?.[1];
    if (!releaseSha || releaseSha !== distSha) {
      return {
        status: 'unverified',
        reason: 'the web release is missing or does not match its dist',
      };
    }
    if (!webCache.has(distSha)) {
      const result = gitRunner([
        'merge-base',
        '--is-ancestor',
        distSha,
        'origin/master',
      ]);
      webCache.set(distSha, result.status === 0);
    }
    if (!webCache.get(distSha)) {
      return {
        status: 'unverified',
        reason: 'the web release is not on origin/master',
      };
    }
  }
  return { status: 'verified', reason: null };
}

export async function review(options = {}) {
  const {
    now = new Date(),
    runEnd = null,
    clock = () => new Date(),
    since = null,
    stateDir,
    token,
    fetchImpl = fetch,
    ghList = listGitHubIssues,
    gitRunner = (args) => spawnSync('git', args, { encoding: 'utf8', timeout: 5000 }),
    env = process.env,
  } = options;

  if (!stateDir) {
    throw new ReviewError('stateDir is required');
  }
  const accessToken = token ?? resolveToken(env);
  const state = loadState(stateDir);
  const window = resolveWindow({ now, lastWindowEnd: state.lastWindowEnd, since });
  const limitations = [];
  const issues = new Map();

  for (const query of STATUS_QUERIES) {
    try {
      const page = await fetchIssuePages({
        fetchImpl,
        token: accessToken,
        query,
        start: window.start,
        end: window.end,
        limitations,
      });
      for (const issue of page) {
        if (issue && typeof issue.id === 'string' && /^\d+$/.test(issue.id) && !issues.has(issue.id)) {
          issues.set(issue.id, issue);
        }
      }
    } catch (error) {
      if (
        error instanceof ReviewError &&
        error.httpStatus === 400 &&
        query !== 'is:unresolved'
      ) {
        limitations.push(`${query} is not supported by this Sentry API; skipped.`);
        continue;
      }
      throw error;
    }
  }

  const candidates = [];
  const skipped = [];
  let totalIssues = 0;

  for (const issue of issues.values()) {
    if (!isWindowed(issue, window)) {
      continue;
    }
    totalIssues += 1;
    if (issue.status === 'resolved') {
      continue;
    }
    const lastSeen = Date.parse(issue.lastSeen);
    const entry = state.proposals[issue.id];
    let resurfaced = issue.status !== 'unresolved';
    if (entry) {
      const newer =
        Number.isFinite(lastSeen) && lastSeen > Date.parse(entry.lastSeenAt ?? 0);
      const regressed = issue.substatus === 'regressed';
      if (!newer && !regressed) {
        skipped.push(`${issueLabel(issue)} — already ${safeLedgerStatus(entry.status)}`);
        continue;
      }
      resurfaced = true;
    }
    candidates.push({ issue, resurfaced });
  }

  candidates.sort((a, b) => compareIssues(a.issue, b.issue));
  const newIssues = candidates.length;

  const proposals = [];
  const webCache = new Map();
  let index = 0;
  for (; index < candidates.length && proposals.length < MAX_PROPOSALS; index += 1) {
    const candidate = candidates[index];
    let facts;
    try {
      facts = await fetchVerifiedEvents({
        fetchImpl,
        token: accessToken,
        issueId: candidate.issue.id,
        start: window.start,
        end: window.end,
      });
    } catch (error) {
      if (
        error instanceof ReviewError &&
        (error.httpStatus === 404 || error.httpStatus === 410)
      ) {
        skipped.push(
          `${issueLabel(candidate.issue)} — event endpoint returned HTTP ${error.httpStatus}`,
        );
        continue;
      }
      throw error;
    }
    if (facts.length === 0) {
      skipped.push(`${issueLabel(candidate.issue)} — no verified production event in window`);
      continue;
    }

    const environment = verifyEnvironment(facts, gitRunner, webCache);
    if (environment.status === 'unverified') {
      limitations.push(
        `${issueLabel(candidate.issue)} — environment unverified: ${environment.reason}.`,
      );
    }

    proposals.push({
      issue: candidate.issue,
      events: facts,
      resurfaced: candidate.resurfaced,
      environment: environment.status,
      githubMatches: [],
    });
  }

  if (index < candidates.length) {
    const unreviewed = candidates.slice(index);
    limitations.push(
      `${unreviewed.length} candidates beyond the ${MAX_PROPOSALS}-proposal cap: ` +
        unreviewed.map((candidate) => issueLabel(candidate.issue)).join(', '),
    );
  }

  const finish = (exitCode, finalState = state) => ({
    report: formatReport({
      window,
      totalIssues,
      newIssues,
      proposals,
      skipped,
      limitations,
    }),
    state: finalState,
    window,
    proposals,
    skipped,
    limitations,
    exitCode,
  });

  let github;
  try {
    github = await ghList();
  } catch {
    github = { ok: false, error: 'gh issue list failed', issues: [], truncated: false };
  }
  if (github.ok && !Array.isArray(github.issues)) {
    github = {
      ok: false,
      error: 'gh returned an unexpected JSON shape.',
      issues: [],
      truncated: false,
    };
  }

  if (!github.ok) {
    limitations.push(
      `GitHub dedupe unavailable: ${safeLine(github.error) || 'gh issue list failed'}. Cursor unchanged.`,
    );
    for (const proposal of proposals) {
      proposal.githubMatches = null;
    }
    return finish(1);
  }

  if (github.truncated) {
    limitations.push(
      `GitHub dedupe may be truncated at ${GITHUB_LIMIT} issues; check the repository directly.`,
    );
  }
  for (const proposal of proposals) {
    proposal.githubMatches = matchGitHub(proposal, github.issues, now);
  }

  const proposedAt = new Date(now).toISOString();
  const next = {
    ...state,
    proposals: { ...state.proposals },
  };
  for (const proposal of proposals) {
    const id = proposal.issue.id;
    const existing = next.proposals[id];
    next.proposals[id] = {
      shortId: safeShortId(proposal.issue.shortId) ?? `ISSUE-${id}`,
      status: existing?.status ?? 'proposed',
      firstProposedAt: existing?.firstProposedAt ?? proposedAt,
      lastProposedAt: proposedAt,
      lastSeenAt: rawTimestamp(proposal.issue.lastSeen, proposedAt),
      issue: existing?.issue ?? null,
      reason: existing?.reason ?? null,
    };
  }
  if (window.source !== 'override') {
    next.lastWindowEnd = window.end.toISOString();
    next.lastRunAt = new Date(runEnd ?? clock()).toISOString();
  }

  try {
    saveState(stateDir, next);
  } catch (error) {
    limitations.push(`${safeLine(error.message)}; cursor unchanged.`);
    return finish(1);
  }

  return finish(0, next);
}

function defaultStateDir(env) {
  if (env.SENTRY_REVIEW_STATE_DIR) {
    return env.SENTRY_REVIEW_STATE_DIR;
  }
  return join(
    env.XDG_STATE_HOME || join(homedir(), '.local', 'state'),
    'wishtogether',
    'sentry-review',
  );
}

export async function main(argv, options = {}) {
  const {
    env = process.env,
    stateDir: stateDirOption,
    writeOut = (value) => process.stdout.write(value),
    writeErr = (value) => process.stderr.write(value),
  } = options;

  let args;
  try {
    args = parseArgs(argv);
  } catch (error) {
    writeErr(`${error.message}\n`);
    return error.exitCode ?? 2;
  }

  if (args.help) {
    writeOut(USAGE);
    return 0;
  }

  const stateDir = args.stateDir ?? stateDirOption ?? defaultStateDir(env);

  try {
    if (args.command === 'review') {
      const result = await review({
        ...options,
        env,
        stateDir,
        since: args.since,
      });
      writeOut(result.report);
      return result.exitCode;
    }

    const state = loadState(stateDir);
    if (args.command === 'mark') {
      markProposal(state, args.shortId, args.issue);
      saveState(stateDir, state);
      writeOut(`marked ${args.shortId} handled\n`);
      return 0;
    }
    if (args.command === 'dismiss') {
      dismissProposal(state, args.shortId, args.reason);
      saveState(stateDir, state);
      writeOut(`dismissed ${args.shortId}\n`);
      return 0;
    }
    if (args.command === 'reopen') {
      reopenProposal(state, args.shortId);
      saveState(stateDir, state);
      writeOut(`reopened ${args.shortId}\n`);
      return 0;
    }
    if (args.command === 'status') {
      writeOut(formatStatus(state));
      return 0;
    }
  } catch (error) {
    if (error instanceof ReviewError) {
      writeErr(`${safeLine(error.message)}\n`);
      return error.exitCode ?? 1;
    }
    writeErr(`${safeLine(error.message) || 'unexpected error'}\n`);
    return 1;
  }
}

if (isEntryPoint(import.meta.url)) {
  main(process.argv.slice(2)).then((code) => {
    process.exitCode = code;
  });
}
