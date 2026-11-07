// The pipeline's independent reviewer: a fresh Claude process that has not seen the
// author's reasoning. It only gets the prompt, so it has to judge from the code.
'use strict';
const { runClaude } = require('./claudeAgent');

function runReviewer(prompt, opts = {}) {
  return runClaude(prompt, opts);
}

module.exports = { runReviewer };
