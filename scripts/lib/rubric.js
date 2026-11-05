// Loads the shared review rubric so both agents are graded against the
// identical standard. Single source of truth: templates/REVIEW_RUBRIC.md
'use strict';
const fs = require('fs');
const path = require('path');

const RUBRIC_PATH = path.join(__dirname, '..', '..', 'templates', 'REVIEW_RUBRIC.md');

function loadRubric() {
  try {
    return fs.readFileSync(RUBRIC_PATH, 'utf8');
  } catch (err) {
    throw new Error(
      `Could not read REVIEW_RUBRIC.md at ${RUBRIC_PATH}. ` +
      `The co-optimizer refuses to run without a shared rubric (both agents ` +
      `must be graded identically). Original error: ${err.message}`
    );
  }
}

module.exports = { loadRubric, RUBRIC_PATH };
