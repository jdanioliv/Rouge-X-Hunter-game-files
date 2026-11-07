#!/usr/bin/env node
// Dual-Agent (now three-engineer) Co-Optimization Pipeline
// Coordinates Claude (claude -p, author), a fresh Claude process as the Reviewer
// (independent verifier), and Gemini (Google Generative Language API, planner
// + second reviewer) in a multi-stage adversarial review loop. See
// templates/REVIEW_RUBRIC.md for the shared standard all three are graded
// against.
//
// Design notes (grounded in multi-agent collaboration research - see
// templates/REVIEW_RUBRIC.md "External Evidence & Independent Verification"):
//   1. The proposer never certifies its own "done". Claude's Stage 3 self-
//      report is logged for transparency but Reviewer - the reviewer, not the
//      author - independently re-counts critical issues, and THAT count
//      gates whether anything gets written. ("LLMs Cannot Self-Correct
//      Reasoning Yet", Huang et al., ICLR 2024.)
//   2. Every review is grounded in real linter/compiler output when one is
//      available (scripts/lib/luauLint.js), not just re-reading the code as
//      text - text-only self-review is weak signal; deterministic tool
//      output is new information the author didn't have. (CRITIC, ICLR 2024.)
//   3. Gemini adds a second, independently-formed voice at the plan stage
//      (before code exists to anchor on) and the review stage (alongside
//      Reviewer) - but does NOT get a second vote on the write-gate. Reviewer
//      alone stays authoritative for REMAINING_CRITICAL_ISSUES, on purpose:
//      a two-verifier consensus/veto scheme adds deadlock risk and cost for
//      a solo-dev tool, without a clear correctness win over "one dedicated,
//      independent, evidence-grounded verifier". See README "Design notes".
'use strict';
require('dotenv').config();
const fs = require('fs');
const path = require('path');
const { runClaude } = require('./lib/claudeAgent');
const { runReviewer } = require('./lib/reviewerAgent');
const { runGemini } = require('./lib/geminiAgent');
const { loadRubric } = require('./lib/rubric');
const { lintLuau } = require('./lib/luauLint');
const { ReviewLogger } = require('./lib/reviewLogger');
const { syncRouters } = require('./lib/routerSync');

const REPO_ROOT = path.join(__dirname, '..');
const MAX_REFINEMENT_ROUNDS = 3;
const DEFAULT_ROUTERS = ['CLAUDE.md', 'GEMINI.md'];

/**
 * Gemini calls are additive, never load-bearing: if GEMINI_API_KEY isn't set
 * or the call fails, the pipeline degrades to the original Claude/Reviewer
 * behavior rather than failing the run. Every call site checks `.ok`.
 */
function formatGeminiBlock(label, result) {
  if (!result.ok) return `\n--- ${label} ---\n(unavailable: ${result.text})`;
  return `\n--- ${label} ---\n${result.text}`;
}

function parseArgs(argv) {
  const args = { dryRun: false, mode: 'dual-code', apply: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--dry-run') args.dryRun = true;
    else if (a === '--apply') args.apply = true;
    else if (a === '--mode') args.mode = argv[++i];
    else if (a === '--prompt') args.prompt = argv[++i];
    else if (a === '--target') args.target = argv[++i];
    else if (a === '--trace') args.trace = argv[++i];
  }
  return args;
}

function readTargetIfExists(relPath) {
  if (!relPath) return null;
  const full = path.join(REPO_ROOT, relPath);
  if (!fs.existsSync(full)) return null;
  return fs.readFileSync(full, 'utf8');
}

function extractCriticalCount(text) {
  const m = text.match(/REMAINING_CRITICAL_ISSUES:\s*(\d+)/i);
  return m ? parseInt(m[1], 10) : null; // null = agent didn't comply with format
}

function extractFinalFile(text) {
  const marker = text.indexOf('FINAL_FILE:');
  if (marker === -1) return null;
  const fence = text.indexOf('```', marker);
  if (fence === -1) return null;
  const fenceEnd = text.indexOf('\n', fence);
  const closeFence = text.indexOf('```', fenceEnd + 1);
  if (closeFence === -1) return null;
  return text.slice(fenceEnd + 1, closeFence).trim();
}

function formatLintBlock(lint) {
  if (!lint.ran) return `\n--- DETERMINISTIC LINT EVIDENCE ---\n(none available: ${lint.output})`;
  return `\n--- DETERMINISTIC LINT EVIDENCE (${lint.tool}, exit ${lint.ok ? 'clean' : 'non-zero'}) ---\n${lint.output}`;
}

/**
 * The authoritative "are we done" check. Reviewer is the reviewer, not the
 * author of `code` - its count is what gates Stage 4, never the proposer's
 * own self-report (which is still logged separately for transparency/drift
 * detection, but never trusted as the stop condition).
 */
async function verifyIndependently(rubric, code, opts, contextLabel) {
  const lint = lintLuau(code);
  const prompt = [
    `You are the Reviewer, acting as the INDEPENDENT VERIFIER - not the`,
    `author of this code. Re-review it from scratch against the rubric and the`,
    `real lint evidence below. Do not assume the author's own claims about`,
    `what they fixed are correct; verify against the evidence.`,
    `\n--- REVIEW RUBRIC ---\n${rubric}`,
    `\n--- CODE (${contextLabel}) ---\n${code}`,
    formatLintBlock(lint),
    `\nEnd your response with exactly one line: REMAINING_CRITICAL_ISSUES: <integer>`,
  ].join('\n');
  const result = await runReviewer(prompt, opts);
  return { criticalCount: extractCriticalCount(result.text), text: result.text, lint };
}

// ---------------------------------------------------------------------------
// Mode: dual-code - net-new feature/system, 3-stage loop from a prompt.
// ---------------------------------------------------------------------------
async function runDualCode(args, logger, opts) {
  const rubric = loadRubric();
  const targetContext = readTargetIfExists(args.target);

  const planPrompt = [
    `You are Gemini, acting as PLANNER (you plan; Claude implements; Reviewer`,
    `independently verifies). Before any code is written, produce a short`,
    `implementation plan for the feature request below: approach, which`,
    `files/systems it touches, state/API surface it needs, and edge cases or`,
    `risks to watch for. Do not write the implementation itself.`,
    `\n--- REVIEW RUBRIC ---\n${rubric}`,
    args.target ? `\n--- TARGET FILE (${args.target}) CURRENT CONTENTS ---\n${targetContext || '(new file)'}` : '',
    `\n--- FEATURE REQUEST ---\n${args.prompt}`,
  ].join('\n');

  const geminiPlan = await runGemini(planPrompt, opts);
  logger.writeStage('stage0_gemini_plan', 'stage0_gemini_plan.md', geminiPlan.text);

  const stage1Prompt = [
    `You are Claude Opus 5, Principal Roblox Engineer on RougeXHunter.`,
    `Implement the following feature request. Follow the shared rubric strictly.`,
    `\n--- REVIEW RUBRIC ---\n${rubric}`,
    args.target ? `\n--- TARGET FILE (${args.target}) CURRENT CONTENTS ---\n${targetContext || '(new file)'}` : '',
    `\n--- FEATURE REQUEST ---\n${args.prompt}`,
    formatGeminiBlock("GEMINI'S PLAN (reference - deviate if it's wrong, but note why)", geminiPlan),
    `\nOutput the full Luau implementation. State any state machines and API/remote contracts explicitly.`,
  ].join('\n');

  const stage1 = await runClaude(stage1Prompt, opts);
  logger.writeStage('stage1_implementation', 'stage1_implementation.md', stage1.text);

  let currentCode = stage1.text;
  let round = 0;
  let verifiedCriticalCount = null;

  while (round < MAX_REFINEMENT_ROUNDS) {
    round += 1;
    const lintBefore = lintLuau(currentCode);

    const stage2Prompt = [
      `You are the Reviewer, an adversarial senior reviewer on RougeXHunter.`,
      `Audit the code below against the rubric. Focus on race conditions, listener`,
      `leaks, state sync, GC/perf hotspots, edge cases, null/bounds checks.`,
      `Give concrete diff-style patches, not vague advice. Tag every finding`,
      `CRITICAL/MAJOR/MINOR/NIT per the rubric's severity scale. Treat the lint`,
      `evidence below as ground truth - do not argue it away in prose.`,
      `\n--- REVIEW RUBRIC ---\n${rubric}`,
      `\n--- CODE UNDER REVIEW (round ${round}) ---\n${currentCode}`,
      formatLintBlock(lintBefore),
    ].join('\n');

    const stage2bPrompt = [
      `You are Gemini, the SECOND reviewer alongside Reviewer on RougeXHunter`,
      `(you don't gate the write - Reviewer's independent recheck does - but`,
      `your findings must be addressed in the next revision same as Reviewer's).`,
      `Audit the code below against the rubric, independently of any other`,
      `review. Tag every finding CRITICAL/MAJOR/MINOR/NIT.`,
      `\n--- REVIEW RUBRIC ---\n${rubric}`,
      `\n--- CODE UNDER REVIEW (round ${round}) ---\n${currentCode}`,
      formatLintBlock(lintBefore),
    ].join('\n');

    const [stage2, stage2b] = await Promise.all([
      runReviewer(stage2Prompt, opts),
      runGemini(stage2bPrompt, opts),
    ]);
    logger.writeStage('stage2_critique', `stage2_critique_round${round}.md`, stage2.text);
    logger.writeStage('stage2b_gemini_critique', `stage2b_gemini_critique_round${round}.md`, stage2b.text);

    const stage3Prompt = [
      `You are Claude Opus 5. Resolve every CRITICAL and MAJOR finding below,`,
      `merge the valid performance optimizations, and verify structural`,
      `compatibility with the existing project (Types.luau/Constants.luau/`,
      `Remotes.luau conventions). Reject any suggestion that is factually wrong`,
      `or violates the rubric and say why - for either reviewer.`,
      `\n--- REVIEW RUBRIC ---\n${rubric}`,
      `\n--- YOUR PREVIOUS CODE ---\n${currentCode}`,
      `\n--- REVIEWER CRITIQUE ---\n${stage2.text}`,
      formatGeminiBlock('GEMINI CRITIQUE', stage2b),
      `\nEnd your response with a line: REMAINING_CRITICAL_ISSUES: <integer> (your own`,
      `estimate - note this is informational only; Reviewer independently re-verifies next).`,
      `Then output the complete final file as:\nFINAL_FILE:\n\`\`\`luau\n<code>\n\`\`\``,
    ].join('\n');

    const stage3 = await runClaude(stage3Prompt, opts);
    logger.writeStage('stage3_refinement', `stage3_refinement_round${round}.md`, stage3.text);
    currentCode = extractFinalFile(stage3.text) || currentCode;
    const selfReportedCount = extractCriticalCount(stage3.text);

    const verification = await verifyIndependently(rubric, currentCode, opts, `dual-code round ${round}, post-refinement`);
    logger.writeStage('stage3b_independent_verification', `stage3b_independent_verification_round${round}.md`,
      `Claude self-reported: ${selfReportedCount ?? 'N/A'}\nReviewer independently verified: ${verification.criticalCount ?? 'N/A'} (authoritative)\n\n${verification.text}`);
    verifiedCriticalCount = verification.criticalCount;

    if (selfReportedCount !== null && verification.criticalCount !== null && selfReportedCount !== verification.criticalCount) {
      logger.appendRunsLog(`[${logger.runId}] NOTE: self-report/independent-verification mismatch (Claude said ${selfReportedCount}, Reviewer says ${verification.criticalCount}) - trusting Reviewer.`);
    }

    if (verifiedCriticalCount === 0) break;
    if (verifiedCriticalCount === null) break; // Reviewer didn't comply with format - fail closed below, don't loop blind
  }

  const finalCriticalCount = verifiedCriticalCount === null ? -1 : verifiedCriticalCount;
  logger.finish(finalCriticalCount);

  if (finalCriticalCount !== 0) {
    logger.appendRunsLog(
      `[${logger.runId}] SANITY CHECK FAILED - ${finalCriticalCount < 0 ? "Reviewer's verification was not machine-parseable" : finalCriticalCount + ' critical issue(s) independently confirmed'}. NOT writing to codebase/artifacts.`
    );
    return { ok: false, runId: logger.runId, criticalRemaining: finalCriticalCount };
  }

  const artifactPath = logger.writeFinalArtifact(args.target || 'untitled.luau', currentCode);

  let writtenToRepo = null;
  if (args.apply && args.target) {
    const full = path.join(REPO_ROOT, args.target);
    fs.mkdirSync(path.dirname(full), { recursive: true });
    fs.writeFileSync(full, currentCode, 'utf8');
    writtenToRepo = args.target;
  }

  await syncRouters(
    { runId: logger.runId, action: writtenToRepo ? 'wrote' : 'proposed', file: writtenToRepo || artifactPath.replace(REPO_ROOT + path.sep, ''), note: `dual-code, ${round} round(s), Gemini-planned, 0 critical issues (Reviewer-verified)` },
    DEFAULT_ROUTERS
  );

  return { ok: true, runId: logger.runId, criticalRemaining: 0, artifactPath, writtenToRepo };
}

// ---------------------------------------------------------------------------
// Mode: dual-refactor - Reviewer profiles an existing file first, then Claude
// synthesizes the refactor. Reviewer's recheck (not Claude's self-report) gates
// the loop, per the same independent-verification principle as dual-code.
// ---------------------------------------------------------------------------
async function runDualRefactor(args, logger, opts) {
  if (!args.target) throw new Error('dual-refactor requires --target <relative path to existing file>');
  const rubric = loadRubric();
  const original = readTargetIfExists(args.target);
  if (original === null) throw new Error(`Target file not found: ${args.target}`);

  const lintOriginal = lintLuau(original);
  const profilePromptFor = (agentName) => [
    `You are ${agentName}. Profile and benchmark the following Luau file`,
    `for performance bottlenecks, GC pressure, race conditions, and bugs.`,
    `Rank findings by severity per the rubric. Be specific about which lines.`,
    `\n--- REVIEW RUBRIC ---\n${rubric}`,
    `\n--- FILE: ${args.target} ---\n${original}`,
    formatLintBlock(lintOriginal),
  ].join('\n');

  const [profile, geminiProfile] = await Promise.all([
    runReviewer(profilePromptFor('Reviewer'), opts),
    runGemini(profilePromptFor('Gemini, planning the priorities for this refactor'), opts),
  ]);
  logger.writeStage('stage1_profile', 'stage1_profile.md', profile.text);
  logger.writeStage('stage1b_gemini_profile', 'stage1b_gemini_profile.md', geminiProfile.text);

  let currentCode = original;
  let round = 0;
  let reviewerVerifiedCount = null;
  // Round 1 synthesizes from both independent profiles; from round 2 on,
  // Reviewer's fresh recheck (verifyIndependently) is the only feed - Gemini
  // doesn't re-profile every round, it informed the initial plan.
  let findingsForNextRound = `REVIEWER FINDINGS:\n${profile.text}` +
    formatGeminiBlock('GEMINI FINDINGS', geminiProfile);

  while (round < MAX_REFINEMENT_ROUNDS) {
    round += 1;
    const synthPrompt = [
      `You are Claude Opus 5. Synthesize a refactored, production-ready version`,
      `of the file below that resolves the findings without changing its`,
      `public API/Remote contract unless the findings require it (call that out).`,
      `\n--- REVIEW RUBRIC ---\n${rubric}`,
      `\n--- ORIGINAL FILE (${args.target}) ---\n${round === 1 ? original : currentCode}`,
      `\n--- FINDINGS TO ADDRESS ---\n${findingsForNextRound}`,
      `\nEnd with: REMAINING_CRITICAL_ISSUES: <integer> (informational - Reviewer`,
      `independently re-verifies next; that count is authoritative, not this one).`,
      `Then: FINAL_FILE:\n\`\`\`luau\n<code>\n\`\`\``,
    ].join('\n');

    const synth = await runClaude(synthPrompt, opts);
    logger.writeStage('stage2_synthesis', `stage2_synthesis_round${round}.md`, synth.text);
    currentCode = extractFinalFile(synth.text) || currentCode;
    const selfReportedCount = extractCriticalCount(synth.text);

    const verification = await verifyIndependently(rubric, currentCode, opts, `dual-refactor round ${round} of ${args.target}`);
    logger.writeStage('recheck', `recheck_round${round}.md`,
      `Claude self-reported: ${selfReportedCount ?? 'N/A'}\nReviewer independently verified: ${verification.criticalCount ?? 'N/A'} (authoritative)\n\n${verification.text}`);
    reviewerVerifiedCount = verification.criticalCount;
    findingsForNextRound = verification.text; // feed Reviewer's fresh findings forward, not Claude's own claim

    if (reviewerVerifiedCount === 0) break;
    if (reviewerVerifiedCount === null) break;
  }

  const finalCriticalCount = reviewerVerifiedCount === null ? -1 : reviewerVerifiedCount;
  logger.finish(finalCriticalCount);

  if (finalCriticalCount !== 0) {
    logger.appendRunsLog(`[${logger.runId}] SANITY CHECK FAILED on refactor of ${args.target} (Reviewer-verified). NOT applying.`);
    return { ok: false, runId: logger.runId, criticalRemaining: finalCriticalCount };
  }

  const artifactPath = logger.writeFinalArtifact(args.target, currentCode);
  let writtenToRepo = null;
  if (args.apply) {
    fs.writeFileSync(path.join(REPO_ROOT, args.target), currentCode, 'utf8');
    writtenToRepo = args.target;
  }

  await syncRouters(
    { runId: logger.runId, action: writtenToRepo ? 'refactored' : 'proposed refactor of', file: writtenToRepo || args.target, note: `${round} round(s), Reviewer+Gemini profiled, 0 critical issues (Reviewer-verified)` },
    DEFAULT_ROUTERS
  );

  return { ok: true, runId: logger.runId, criticalRemaining: 0, artifactPath, writtenToRepo };
}

// ---------------------------------------------------------------------------
// Mode: dual-debug - independent hypotheses -> cross-evaluation -> verified
// fix -> Reviewer independently re-verifies the fix before it's accepted.
// ---------------------------------------------------------------------------
async function runDualDebug(args, logger, opts) {
  if (!args.trace) throw new Error('dual-debug requires --trace "<error text or file path>"');
  const rubric = loadRubric();
  const traceText = fs.existsSync(path.join(REPO_ROOT, args.trace))
    ? fs.readFileSync(path.join(REPO_ROOT, args.trace), 'utf8')
    : args.trace;
  const targetContext = readTargetIfExists(args.target);

  const hypothesisPromptFor = (agentName) => [
    `You are ${agentName}, independently diagnosing a RougeXHunter bug.`,
    `Do NOT assume another engineer's opinion - give YOUR own root-cause hypothesis.`,
    `\n--- REVIEW RUBRIC ---\n${rubric}`,
    args.target ? `\n--- RELEVANT FILE (${args.target}) ---\n${targetContext || '(not found)'}` : '',
    `\n--- ERROR TRACE ---\n${traceText}`,
    `\nGive: root cause hypothesis, confidence (0-100%), and a proposed fix.`,
  ].join('\n');

  const [claudeHyp, reviewerHyp, geminiHyp] = await Promise.all([
    runClaude(hypothesisPromptFor('Claude Opus 5'), opts),
    runReviewer(hypothesisPromptFor('Reviewer'), opts),
    runGemini(hypothesisPromptFor('Gemini'), opts),
  ]);
  logger.writeStage('stage1a_claude_hypothesis', 'stage1a_claude_hypothesis.md', claudeHyp.text);
  logger.writeStage('stage1b_reviewer_hypothesis', 'stage1b_reviewer_hypothesis.md', reviewerHyp.text);
  logger.writeStage('stage1c_gemini_hypothesis', 'stage1c_gemini_hypothesis.md', geminiHyp.text);

  // Each engineer cross-evaluates the OTHER TWO, not just one - three
  // independent hypotheses need three cross-checks, not a single pairing.
  const crossEvalPrompt = (reviewerName, ownHyp, others) => [
    `You are ${reviewerName}. Cross-evaluate the OTHER engineers' diagnoses`,
    `below against your own. For each one, say which parts are correct,`,
    `which are wrong, and why.`,
    `\n--- YOUR OWN HYPOTHESIS ---\n${ownHyp}`,
    ...others.map(([name, text]) => `\n--- ${name}'S HYPOTHESIS ---\n${text}`),
  ].join('\n');

  const [claudeEval, reviewerEval, geminiEval] = await Promise.all([
    runClaude(crossEvalPrompt('Claude Opus 5', claudeHyp.text, [['Reviewer', reviewerHyp.text], ['Gemini', geminiHyp.text]]), opts),
    runReviewer(crossEvalPrompt('Reviewer', reviewerHyp.text, [['Claude', claudeHyp.text], ['Gemini', geminiHyp.text]]), opts),
    runGemini(crossEvalPrompt('Gemini', geminiHyp.text, [['Claude', claudeHyp.text], ['Reviewer', reviewerHyp.text]]), opts),
  ]);
  logger.writeStage('stage2a_claude_cross_eval', 'stage2a_claude_cross_eval.md', claudeEval.text);
  logger.writeStage('stage2b_reviewer_cross_eval', 'stage2b_reviewer_cross_eval.md', reviewerEval.text);
  logger.writeStage('stage2c_gemini_cross_eval', 'stage2c_gemini_cross_eval.md', geminiEval.text);

  const synthPrompt = [
    `You are Claude Opus 5. Three independent diagnoses and three cross-`,
    `evaluations follow. Produce ONE verified fix: state the confirmed root`,
    `cause (explicitly reject whichever hypothesis/hypotheses the cross-`,
    `evaluations disproved), then the patch.`,
    `\n--- REVIEW RUBRIC ---\n${rubric}`,
    `\n--- CLAUDE HYPOTHESIS ---\n${claudeHyp.text}`,
    `\n--- REVIEWER HYPOTHESIS ---\n${reviewerHyp.text}`,
    formatGeminiBlock('GEMINI HYPOTHESIS', geminiHyp),
    `\n--- CLAUDE CROSS-EVAL ---\n${claudeEval.text}`,
    `\n--- REVIEWER CROSS-EVAL ---\n${reviewerEval.text}`,
    formatGeminiBlock('GEMINI CROSS-EVAL', geminiEval),
    `\nEnd with: REMAINING_CRITICAL_ISSUES: <integer> (informational - if a fix`,
    `file is produced, Reviewer independently re-verifies it next).`,
    args.target ? `Then: FINAL_FILE:\n\`\`\`luau\n<full corrected file>\n\`\`\`` : '',
  ].join('\n');

  const synth = await runClaude(synthPrompt, opts);
  logger.writeStage('stage3_verified_fix', 'stage3_verified_fix.md', synth.text);

  const finalCode = extractFinalFile(synth.text);
  let finalCriticalCount;

  if (finalCode) {
    const verification = await verifyIndependently(rubric, finalCode, opts, `dual-debug fix for ${args.target || '(no target file)'}`);
    logger.writeStage('stage4_independent_verification', 'stage4_independent_verification.md', verification.text);
    finalCriticalCount = verification.criticalCount === null ? -1 : verification.criticalCount;
  } else {
    // No file to independently verify (diagnosis-only run, no --target) -
    // fall back to the synthesis's own report since there's nothing else to check.
    const selfReported = extractCriticalCount(synth.text);
    finalCriticalCount = selfReported === null ? -1 : selfReported;
  }

  logger.finish(finalCriticalCount);

  let artifactPath = null;
  let writtenToRepo = null;
  if (finalCode && finalCriticalCount === 0) {
    artifactPath = logger.writeFinalArtifact(args.target || 'debug_fix.luau', finalCode);
    if (args.apply && args.target) {
      fs.writeFileSync(path.join(REPO_ROOT, args.target), finalCode, 'utf8');
      writtenToRepo = args.target;
    }
    await syncRouters(
      { runId: logger.runId, action: writtenToRepo ? 'fixed' : 'proposed fix for', file: writtenToRepo || (args.target || 'debug_fix.luau'), note: 'dual-debug, 3-way hypothesis (Claude/Reviewer/Gemini), verified via independent Reviewer recheck' },
      DEFAULT_ROUTERS
    );
  }

  return { ok: finalCriticalCount === 0, runId: logger.runId, criticalRemaining: finalCriticalCount, artifactPath, writtenToRepo, diagnosis: synth.text };
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (!['dual-code', 'dual-refactor', 'dual-debug'].includes(args.mode)) {
    console.error(`Unknown --mode "${args.mode}". Use dual-code | dual-refactor | dual-debug.`);
    process.exit(2);
  }

  const seedMs = Date.now();
  const logger = new ReviewLogger(args.mode, seedMs);
  const opts = { dryRun: args.dryRun };

  let result;
  try {
    if (args.mode === 'dual-code') result = await runDualCode(args, logger, opts);
    else if (args.mode === 'dual-refactor') result = await runDualRefactor(args, logger, opts);
    else result = await runDualDebug(args, logger, opts);
  } catch (err) {
    logger.appendRunsLog(`[${logger.runId}] FATAL ERROR: ${err.message}`);
    logger.finish(-1);
    console.error(JSON.stringify({ ok: false, error: err.message, runId: logger.runId }, null, 2));
    process.exit(1);
  }

  console.log(JSON.stringify(result, null, 2));
  process.exit(result.ok ? 0 : 1);
}

if (require.main === module) {
  main();
}

module.exports = { runDualCode, runDualRefactor, runDualDebug, parseArgs, verifyIndependently };
