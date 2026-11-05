// Deterministic external evidence for the review loop. Per the research on
// multi-agent code review (Huang et al., ICLR 2024 "LLMs Cannot Self-Correct
// Reasoning Yet"; CRITIC, ICLR 2024): an LLM re-reading its own/another's
// code produces weak signal. A compiler/linter produces facts the model
// couldn't have had at generation time. This never blocks a run if no
// linter is installed - it degrades to "no external evidence available"
// rather than failing closed, since not every dev machine has one.
'use strict';
const { spawnSync } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const CANDIDATES = [
  { tool: 'selene', args: (file) => [file] },
  { tool: 'luau-analyze', args: (file) => [file] },
];

/**
 * @param {string} code - Luau source to check.
 * @returns {{ran: boolean, tool: string|null, ok: boolean, output: string}}
 */
function lintLuau(code) {
  const tmpFile = path.join(os.tmpdir(), `agentic-os-lint-${Date.now()}-${Math.floor(Math.random() * 1e6)}.luau`);
  fs.writeFileSync(tmpFile, code, 'utf8');

  try {
    for (const candidate of CANDIDATES) {
      const result = spawnSync(candidate.tool, candidate.args(tmpFile), { encoding: 'utf8', shell: false });
      if (result.error && result.error.code === 'ENOENT') continue; // tool not installed, try next
      if (result.error) {
        return { ran: false, tool: candidate.tool, ok: false, output: `Lint tool errored: ${result.error.message}` };
      }
      const output = `${result.stdout || ''}${result.stderr || ''}`.trim();
      return { ran: true, tool: candidate.tool, ok: result.status === 0, output: output || '(no output, clean)' };
    }
    return { ran: false, tool: null, ok: false, output: 'No Luau linter found on PATH (tried: selene, luau-analyze). Install one via Aftman/Rokit for real compiler-level evidence instead of text-only review.' };
  } finally {
    fs.unlink(tmpFile, () => {}); // best-effort cleanup, don't block on it
  }
}

module.exports = { lintLuau };
