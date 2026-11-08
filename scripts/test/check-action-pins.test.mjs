import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import {
  mkdtempSync,
  readFileSync,
  readdirSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

import { unpinnedUses } from '../check-action-pins.mjs';

const CLI = fileURLToPath(new URL('../check-action-pins.mjs', import.meta.url));
const ROOT = fileURLToPath(new URL('../..', import.meta.url));
const WORKFLOWS = join(ROOT, '.github/workflows');
const SHA = '3d3c42e5aac5ba805825da76410c181273ba90b1';
const DIGEST = 'a'.repeat(64);

function runCli(directory) {
  return spawnSync(process.execPath, [CLI, directory], { encoding: 'utf8' });
}

function withWorkflows(contents, run) {
  const directory = mkdtempSync(join(tmpdir(), 'action-pins-'));
  try {
    writeFileSync(join(directory, 'ci.yml'), contents);
    return run(directory);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
}

test('rejects a tag on an inline-list step', () => {
  assert.deepEqual(unpinnedUses('      - uses: actions/checkout@v7\n'), [
    { line: 1, value: 'actions/checkout@v7' },
  ]);
});

test('rejects a tag when the colon is spaced', () => {
  assert.deepEqual(unpinnedUses('        uses : actions/checkout@v7\n'), [
    { line: 1, value: 'actions/checkout@v7' },
  ]);
});

test('rejects a tag under a quoted key', () => {
  assert.deepEqual(unpinnedUses('        "uses": actions/checkout@v7\n'), [
    { line: 1, value: 'actions/checkout@v7' },
  ]);
});

test('rejects a tag even when the comment contains a SHA', () => {
  assert.deepEqual(
    unpinnedUses(`        uses: actions/checkout@v7 # moved from @${SHA}\n`),
    [{ line: 1, value: 'actions/checkout@v7' }],
  );
});

test('accepts a SHA with a tag comment', () => {
  assert.deepEqual(unpinnedUses(`        uses: actions/checkout@${SHA} # v7\n`), []);
});

test('accepts a SHA without a comment', () => {
  assert.deepEqual(unpinnedUses(`        uses: actions/checkout@${SHA}\n`), []);
});

test('accepts a quoted SHA value', () => {
  assert.deepEqual(unpinnedUses(`        uses: "actions/checkout@${SHA}" # v7\n`), []);
});

test('accepts a local reusable workflow', () => {
  assert.deepEqual(unpinnedUses('        uses: ./.github/workflows/reuse.yml\n'), []);
});

test('rejects a remote reusable workflow on a branch', () => {
  assert.deepEqual(
    unpinnedUses('        uses: owner/repo/.github/workflows/reuse.yml@main\n'),
    [{ line: 1, value: 'owner/repo/.github/workflows/reuse.yml@main' }],
  );
});

test('rejects a mutable docker tag', () => {
  assert.deepEqual(unpinnedUses('        uses: docker://alpine:3.19\n'), [
    { line: 1, value: 'docker://alpine:3.19' },
  ]);
});

test('accepts a digest-pinned docker image', () => {
  assert.deepEqual(unpinnedUses(`        uses: docker://alpine@sha256:${DIGEST}\n`), []);
});

test('ignores text with no uses lines', () => {
  assert.deepEqual(unpinnedUses('name: CI\non: push\njobs: {}\n'), []);
});

test('ignores a commented-out uses line', () => {
  assert.deepEqual(unpinnedUses('        # uses: actions/checkout@v7\n'), []);
});

test('reports the 1-based line number of an unpinned ref', () => {
  assert.deepEqual(unpinnedUses(`name: CI\n\n        uses: actions/checkout@v7\n`), [
    { line: 3, value: 'actions/checkout@v7' },
  ]);
});

test('CLI exits 1 for a workflow with a tag', () => {
  withWorkflows('        uses: actions/checkout@v7\n', (directory) => {
    const result = runCli(directory);
    assert.equal(result.status, 1);
    assert.match(result.stderr, /ci\.yml:1: actions\/checkout@v7/);
  });
});

test('CLI exits 0 for a pinned workflow', () => {
  withWorkflows(`        uses: actions/checkout@${SHA} # v7\n`, (directory) => {
    const result = runCli(directory);
    assert.equal(result.status, 0);
    assert.equal(result.stderr, '');
  });
});

test('CLI exits 1 when the workflows directory is missing', () => {
  const root = mkdtempSync(join(tmpdir(), 'action-pins-'));
  try {
    const result = runCli(join(root, 'missing'));
    assert.equal(result.status, 1);
    assert.match(result.stderr, /not found/);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('CLI discovers .yaml files as well as .yml', () => {
  const directory = mkdtempSync(join(tmpdir(), 'action-pins-'));
  try {
    writeFileSync(join(directory, 'ci.yaml'), '        uses: actions/checkout@v7\n');
    const result = runCli(directory);
    assert.equal(result.status, 1);
    assert.match(result.stderr, /ci\.yaml:1: actions\/checkout@v7/);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test('CLI still checks when invoked through a symlink', () => {
  const directory = mkdtempSync(join(tmpdir(), 'action-pins-'));
  try {
    const link = join(directory, 'pins.mjs');
    symlinkSync(CLI, link);
    writeFileSync(join(directory, 'ci.yml'), '        uses: actions/checkout@v7\n');

    const result = spawnSync(process.execPath, [link, directory], { encoding: 'utf8' });

    assert.equal(result.status, 1);
    assert.match(result.stderr, /ci\.yml:1: actions\/checkout@v7/);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test('CLI defaults to .github/workflows from the repository root', () => {
  const result = spawnSync(process.execPath, [CLI], { cwd: ROOT, encoding: 'utf8' });
  assert.equal(result.status, 0);
  assert.equal(result.stderr, '');
});

test('every workflow action in this repository is pinned', () => {
  const files = readdirSync(WORKFLOWS).filter((file) => /\.ya?ml$/.test(file));

  for (const file of files) {
    const text = readFileSync(join(WORKFLOWS, file), 'utf8');
    assert.deepEqual(unpinnedUses(text), [], `${file} has an unpinned action`);
  }
});
