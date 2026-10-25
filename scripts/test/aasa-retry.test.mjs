import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const AASA = JSON.stringify({
  applinks: {
    apps: [],
    details: [{ appIDs: ["CD8XP2U645.gift.wishtogether"], components: [{ "/": "/join" }] }],
  },
});
const OTHER_AASA = JSON.stringify({ applinks: { apps: [], details: [] } });

/**
 * Pull the `run: |` body out of a named step. Keeps the test pointed at the
 * real workflow text instead of a copy that can drift from it.
 */
function stepScript(workflow, stepName) {
  const file = join(ROOT, ".github", "workflows", workflow);
  const lines = readFileSync(file, "utf8").split("\n");
  const step = lines.findIndex((l) => l.trim() === `- name: ${stepName}`);
  assert.notEqual(step, -1, `step not found in ${workflow}: ${stepName}`);
  const run = lines.findIndex((l, n) => n > step && l.trim() === "run: |");
  assert.notEqual(run, -1, `run block not found for ${stepName}`);
  const indent = lines[run].length - lines[run].trimStart().length;
  const body = [];
  for (const line of lines.slice(run + 1)) {
    if (line.trim() && line.length - line.trimStart().length <= indent) break;
    body.push(line.trim() ? line.slice(indent + 2) : "");
  }
  return body.join("\n");
}

/**
 * Run one workflow block against a scripted sequence of curl attempts.
 * scenario: [{ rc, status, contentType, body }], consumed one per curl call.
 * sleep: stub that records its delay instead of waiting.
 */
function runBlock({ workflow, stepName, scenario, expected = AASA, expectedPath, env = {} }) {
  const dir = mkdtempSync(join(tmpdir(), "aasa-retry-"));
  const bin = join(dir, "bin");
  mkdirSync(bin);
  const expectedFile = join(dir, expectedPath);
  mkdirSync(dirname(expectedFile), { recursive: true });
  writeFileSync(expectedFile, expected);

  const scenarioFile = join(dir, "scenario");
  writeFileSync(
    scenarioFile,
    scenario
      .map((s) => [s.rc ?? 0, s.status ?? 200, s.contentType ?? "application/json", s.body ?? ""].join("|"))
      .join("\n") + "\n",
  );
  const counter = join(dir, "counter");
  const sleeps = join(dir, "sleeps");

  writeFileSync(
    join(bin, "curl"),
    `#!/usr/bin/env bash
set -u
n=$(( $(cat "$STUB_COUNTER" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$STUB_COUNTER"
line=$(sed -n "\${n}p" "$STUB_SCENARIO")
if [ -z "$line" ]; then echo "stub: scenario exhausted" >&2; exit 99; fi
IFS='|' read -r rc status ctype body <<< "$line"
headers=""; bodypath=""
while [ $# -gt 0 ]; do
  case "$1" in
    -D) headers="$2"; shift 2 ;;
    -o) bodypath="$2"; shift 2 ;;
    -w|-H) shift 2 ;;
    --connect-timeout|--max-time) shift 2 ;;
    *) shift ;;
  esac
done
: > "$headers"; : > "$bodypath"
if [ "$rc" != "0" ]; then
  echo "curl: ($rc) scripted transport failure" >&2
  exit "$rc"
fi
printf 'HTTP/2 200\\r\\ncontent-type: %s\\r\\n\\r\\n' "$ctype" > "$headers"
printf '%s' "$body" > "$bodypath"
printf '%s' "$status"
`,
  );
  writeFileSync(join(bin, "sleep"), `#!/usr/bin/env bash\necho "$1" >> "$STUB_SLEEPS"\n`);
  chmodSync(join(bin, "curl"), 0o755);
  chmodSync(join(bin, "sleep"), 0o755);

  const result = spawnSync("bash", ["--noprofile", "--norc", "-eo", "pipefail", "-c", stepScript(workflow, stepName)], {
    cwd: dir,
    encoding: "utf8",
    env: {
      ...process.env,
      PATH: `${bin}:${process.env.PATH}`,
      RUNNER_TEMP: dir,
      STUB_SCENARIO: scenarioFile,
      STUB_COUNTER: counter,
      STUB_SLEEPS: sleeps,
      ...env,
    },
  });

  const countLines = (file) => {
    try {
      return readFileSync(file, "utf8").trim().split("\n").filter(Boolean).length;
    } catch {
      return 0;
    }
  };
  const counterValue = () => {
    try {
      return Number(readFileSync(counter, "utf8").trim() || 0);
    } catch {
      return 0;
    }
  };
  return {
    status: result.status,
    output: `${result.stdout ?? ""}${result.stderr ?? ""}`,
    requests: counterValue(),
    sleeps: countLines(sleeps),
  };
}

const ci = (scenario, extra = {}) =>
  runBlock({
    workflow: "ci-web.yml",
    stepName: "Verify the AASA on the preview",
    scenario,
    expectedPath: "web/.well-known/apple-app-site-association",
    env: { PREVIEW_URL: "https://preview.example" },
    ...extra,
  });
const staging = (scenario, extra = {}) =>
  runBlock({
    workflow: "deploy-staging.yml",
    stepName: "Verify the staging AASA is served",
    scenario,
    expectedPath: "staging/build/web/.well-known/apple-app-site-association",
    env: { STAGING_URL: "https://staging.example" },
    ...extra,
  });

const ok = { status: 200, body: AASA };

test("a 404 that clears is retried and the step passes", () => {
  const r = ci([{ status: 404, contentType: "text/html", body: "not here" }, ok]);
  assert.equal(r.status, 0, r.output);
  assert.equal(r.requests, 2);
  assert.equal(r.sleeps, 1);
});

test("a persistent 404 still fails after the full budget", () => {
  const r = ci(Array.from({ length: 6 }, () => ({ status: 404, contentType: "text/html", body: "no" })));
  assert.equal(r.status, 1);
  assert.equal(r.requests, 6);
  assert.equal(r.sleeps, 5);
  assert.match(r.output, /returned HTTP 404 after 6 attempts/);
});

test("a stalled connection that clears is retried (the transport regression)", () => {
  const r = ci([{ rc: 7, body: "" }, ok]);
  assert.equal(r.status, 0, r.output);
  assert.equal(r.requests, 2);
  assert.equal(r.sleeps, 1);
});

test("a persistent transport failure fails with the curl cause, not a fake HTTP code", () => {
  const r = ci(Array.from({ length: 6 }, () => ({ rc: 7, body: "" })));
  assert.equal(r.status, 1);
  assert.equal(r.requests, 6);
  assert.equal(r.sleeps, 5);
  assert.match(r.output, /request failed on all 6 attempts \(curl exit 7\)/);
  assert.doesNotMatch(r.output, /HTTP curl/);
});

test("a stale body is retried until it matches", () => {
  const r = ci([{ status: 200, body: OTHER_AASA }, ok]);
  assert.equal(r.status, 0, r.output);
  assert.equal(r.requests, 2);
  assert.equal(r.sleeps, 1);
});

test("a wrong content type still fails, even with a matching body", () => {
  const r = ci(Array.from({ length: 6 }, () => ({ status: 200, contentType: "text/html", body: AASA })));
  assert.equal(r.status, 1);
  assert.equal(r.requests, 6);
  assert.match(r.output, /not served as application\/json/);
});

test("a corrupt committed file fails fast instead of comparing empty to empty", () => {
  const r = ci([ok], { expected: "{not json" });
  assert.equal(r.status, 1);
  assert.equal(r.requests, 0);
  assert.match(r.output, /is not valid JSON/);
});

test("staging retries a transport failure and does not sleep after its last attempt", () => {
  const r = staging(Array.from({ length: 5 }, () => ({ rc: 7, body: "" })));
  assert.equal(r.status, 1);
  assert.equal(r.requests, 5);
  assert.equal(r.sleeps, 4);
  assert.match(r.output, /Staging AASA request failed on all 5 attempts \(curl exit 7\)/);
});
