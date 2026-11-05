// Adapter for Hermes via OpenRouter's OpenAI-compatible chat API. "Hermes" is
// a persona, not a fixed model - the actual model is whatever OX_ALPHA_MODEL
// points at in .env, see .env.example for the current recommendation and why.
// (History: originally the stealth model `stealth/ox-alpha`, which OpenRouter
// revealed on 2026-08-26 to be Z.ai's GLM-5.3-Flash and moved to paid pricing
// - a reminder that OpenRouter's free-tier listings, this one included, can
// change without notice. Swap models via the env var, never a code change.)
'use strict';

const DEFAULT_TIMEOUT_MS = 5 * 60 * 1000;

// Strips common hand-edited-.env mistakes: wrapping quotes and stray
// whitespace (a trailing inline comment on the same line would also get
// caught here as part of the value - OpenRouter will just reject it clearly).
function cleanEnvValue(v) {
  if (!v) return v;
  let out = v.trim();
  if ((out.startsWith('"') && out.endsWith('"')) || (out.startsWith("'") && out.endsWith("'"))) {
    out = out.slice(1, -1).trim();
  }
  return out;
}

/**
 * @param {string} prompt - Full adversarial-review prompt (includes rubric + Claude's code).
 * @param {object} opts
 * @param {boolean} [opts.dryRun] - Return a canned critique without calling the API.
 * @param {number} [opts.timeoutMs]
 * @returns {Promise<{ok: boolean, text: string, raw: object}>}
 */
async function runHermes(prompt, opts = {}) {
  const apiKey = cleanEnvValue(process.env.OPENROUTER_API_KEY);
  const model = cleanEnvValue(process.env.OX_ALPHA_MODEL) || 'poolside/laguna-s-2.1:free';
  const baseUrl = cleanEnvValue(process.env.OPENROUTER_BASE_URL) || 'https://openrouter.ai/api/v1/chat/completions';
  const timeoutMs = opts.timeoutMs || DEFAULT_TIMEOUT_MS;

  if (opts.dryRun) {
    return {
      ok: true,
      text: '[DRY RUN] Hermes/Ox Alpha stub critique - no real API call made.\n\n' +
            'CRITICAL: none found (stub)\nMAJOR: none found (stub)\n' +
            'This is a placeholder so the Stage 3 synthesis pipeline can be exercised end-to-end.',
      raw: { dryRun: true },
    };
  }

  if (!apiKey) {
    return {
      ok: false,
      text: 'OPENROUTER_API_KEY is not set. Copy .env.example to .env and add your real key.',
      raw: { missingKey: true },
    };
  }

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);

  try {
    const res = await fetch(baseUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${apiKey}`,
        'HTTP-Referer': process.env.OPENROUTER_SITE_URL || 'http://127.0.0.1:4004',
        'X-Title': process.env.OPENROUTER_APP_NAME || 'RougeXHunter-Agentic-OS',
      },
      body: JSON.stringify({
        model,
        temperature: 0.2,
        messages: [
          {
            role: 'system',
            content: 'You are Hermes (Ox Alpha), an adversarial senior game engine reviewer. ' +
                     'Be concrete: cite line-level issues and give diff-style patches, not vague advice.',
          },
          { role: 'user', content: prompt },
        ],
      }),
      signal: controller.signal,
    });

    clearTimeout(timer);
    const bodyText = await res.text();
    let json;
    try { json = JSON.parse(bodyText); } catch { json = null; }

    if (!res.ok) {
      return {
        ok: false,
        text: `OpenRouter returned HTTP ${res.status}: ${json?.error?.message || bodyText.slice(0, 500)}`,
        raw: { status: res.status, body: json || bodyText },
      };
    }

    const text = json?.choices?.[0]?.message?.content;
    if (!text) {
      return { ok: false, text: 'OpenRouter response had no message content.', raw: json };
    }
    return { ok: true, text, raw: json };
  } catch (err) {
    clearTimeout(timer);
    const timedOut = err.name === 'AbortError';
    return {
      ok: false,
      text: timedOut
        ? `Hermes/Ox Alpha call timed out after ${timeoutMs}ms.`
        : `Hermes/Ox Alpha call failed: ${err.message}`,
      raw: { error: err.message, timedOut },
    };
  }
}

module.exports = { runHermes };
