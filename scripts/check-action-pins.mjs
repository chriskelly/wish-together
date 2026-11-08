import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

// A step is either `- uses: ...` or `uses: ...`; accept a spaced colon and a
// quoted key because YAML allows all of them.
const USES_KEY = /^[ \t]*(?:-[ \t]+)?["']?uses["']?[ \t]*:[ \t]*(.*)$/;
const COMMENT = /[ \t]+#.*$/;
const SHA = /^[0-9a-f]{40}$/;
const DOCKER_DIGEST = /^docker:\/\/.+@sha256:[0-9a-f]{64}$/;

/**
 * Return every `uses:` entry whose ref is not a full commit SHA.
 *
 * @param {string} text workflow YAML
 * @returns {{ line: number, value: string }[]} 1-based line and the action value
 */
export function unpinnedUses(text) {
  const unpinned = [];

  text.split(/\r?\n/).forEach((line, index) => {
    const match = USES_KEY.exec(line);
    if (!match) return;

    // Strip a YAML comment before judging the value: a SHA in the comment must
    // never stand in for a mutable ref in the value.
    let value = match[1].replace(COMMENT, '').trim();
    if (!value) return;

    const quote = value[0];
    if ((quote === '"' || quote === "'") && value.endsWith(quote)) {
      value = value.slice(1, -1).trim();
    }

    // A local composite or reusable workflow is not third-party code.
    if (value.startsWith('./')) return;

    if (value.startsWith('docker://')) {
      if (!DOCKER_DIGEST.test(value)) unpinned.push({ line: index + 1, value });
      return;
    }

    // Third-party and remote reusable workflow refs: whatever follows the last
    // `@` must be a commit SHA.
    const at = value.lastIndexOf('@');
    const ref = at === -1 ? '' : value.slice(at + 1).trim();
    if (!SHA.test(ref)) unpinned.push({ line: index + 1, value });
  });

  return unpinned;
}

function main(argv) {
  const directory = argv[2] ?? '.github/workflows';
  let files;

  try {
    files = readdirSync(directory)
      .filter((file) => /\.ya?ml$/.test(file))
      .sort();
  } catch {
    console.error(`error: workflows directory not found: ${directory}`);
    process.exitCode = 1;
    return;
  }

  let found = 0;
  for (const file of files) {
    const path = join(directory, file);
    for (const entry of unpinnedUses(readFileSync(path, 'utf8'))) {
      console.error(`${path}:${entry.line}: ${entry.value}`);
      found += 1;
    }
  }

  if (found > 0) {
    console.error(
      'error: pin every action to a full commit SHA, with the ref in a trailing comment',
    );
    process.exitCode = 1;
  }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main(process.argv);
}
