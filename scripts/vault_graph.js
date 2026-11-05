#!/usr/bin/env node
'use strict';
// Runs scripts/vault_graph.py with the Python that has graphify installed.
//
//   npm run vault:graph
//
// Looks at GRAPHIFY_PYTHON first, then the default virtual environment in the home folder.

const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const venvBin = process.platform === 'win32' ? path.join('Scripts', 'python.exe') : path.join('bin', 'python');
const python = process.env.GRAPHIFY_PYTHON || path.join(os.homedir(), '.venvs', 'graphify', venvBin);

if (!fs.existsSync(python)) {
  console.error(`[vault-graph] graphify is not installed at ${python}. One-time setup:
  python -m venv "${path.join(os.homedir(), '.venvs', 'graphify')}"
  "${python}" -m pip install graphifyy
Or point GRAPHIFY_PYTHON at a Python that already has it.`);
  process.exit(1);
}

const result = spawnSync(python, [path.join(__dirname, 'vault_graph.py')], {
  stdio: 'inherit',
  env: { ...process.env, PYTHONUTF8: '1', PYTHONIOENCODING: 'utf-8' },
});
process.exit(result.status === null ? 1 : result.status);
