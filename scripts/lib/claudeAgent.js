// Adapter for Claude Opus 5 via the Claude Code CLI headless mode (`claude -p`).
// Uses spawn() with an argv array (shell:false) so quoting behaves identically
// on Windows and POSIX - no manual shell-escaping needed.
'use strict';
const { spawn } = require('child_process');

const DEFAULT_TIMEOUT_MS = 5 * 60 * 1000;

/**
 * @param {string} prompt - Full prompt text (already includes rubric + context).
 * @param {object} opts
 * @param {boolean} [opts.dryRun] - Skip the real CLI call, return a stub.
 * @param {number} [opts.timeoutMs]
 * @returns {Promise<{ok: boolean, text: string, raw: object}>}
 */
function runClaude(prompt, opts = {}) {
  const bin = process.env.CLAUDE_BIN || 'claude';
  const model = process.env.CLAUDE_MODEL;
  const timeoutMs = opts.timeoutMs || DEFAULT_TIMEOUT_MS;

  if (opts.dryRun) {
    return Promise.resolve({
      ok: true,
      text: '[DRY RUN] Claude Opus 5 stub response - no real call made.\n\nPrompt received:\n' + prompt.slice(0, 400) + (prompt.length > 400 ? '...' : ''),
      raw: { dryRun: true },
    });
  }

  const args = ['-p', prompt];
  if (model) args.push('--model', model);

  return new Promise((resolve) => {
    // stdin: 'ignore' - without it, `claude -p` waits ~3s for piped stdin
    // that will never arrive when spawned headlessly, adding needless latency.
    const child = spawn(bin, args, { shell: false, stdio: ['ignore', 'pipe', 'pipe'] });
    let stdout = '';
    let stderr = '';
    let settled = false;

    const timer = setTimeout(() => {
      if (settled) return;
      settled = true;
      child.kill();
      resolve({
        ok: false,
        text: `Claude call timed out after ${timeoutMs}ms.`,
        raw: { stdout, stderr, timedOut: true },
      });
    }, timeoutMs);

    child.stdout.on('data', (d) => { stdout += d.toString(); });
    child.stderr.on('data', (d) => { stderr += d.toString(); });

    child.on('error', (err) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      resolve({
        ok: false,
        text: `Failed to spawn '${bin}'. Is the Claude Code CLI installed and on PATH? ` +
              `Set CLAUDE_BIN in .env to an absolute path if not. Error: ${err.message}`,
        raw: { spawnError: err.message },
      });
    });

    child.on('close', (code) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      resolve({
        ok: code === 0,
        text: code === 0 ? stdout.trim() : `Claude exited with code ${code}.\nstderr: ${stderr}`,
        raw: { code, stdout, stderr },
      });
    });
  });
}

module.exports = { runClaude };
