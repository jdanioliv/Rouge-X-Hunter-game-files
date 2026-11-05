// Adapter for Gemini via Google's Generative Language API (generateContent).
// NOTE: a Gemini Advanced / Google AI Pro *subscription* does NOT include API
// access - it's a separate consumer product with its own billing. This needs
// a real API key from Google AI Studio (https://aistudio.google.com/apikey),
// which has a free tier (rate-limited, no card required) - but since an
// April 2026 policy change, that free tier is Flash-only. Pro-tier models
// (gemini-2.5-pro, any gemini-3.x-pro) now return HTTP 429 "limit: 0" on a
// free-tier key regardless of how little you've used - that's a billing
// wall, not a usage cap. Set GEMINI_API_KEY in .env to use it.
//
// Model IDs (and which ones are still free) change often - if this starts
// 429ing with "limit: 0" or 404ing, check the current list/pricing at
// https://ai.google.dev/gemini-api/docs/models and update GEMINI_MODEL in
// .env (no code change needed).
'use strict';

const DEFAULT_TIMEOUT_MS = 5 * 60 * 1000;

/**
 * @param {string} prompt - Full prompt text (already includes rubric + context).
 * @param {object} opts
 * @param {boolean} [opts.dryRun] - Return a canned response without calling the API.
 * @param {number} [opts.timeoutMs]
 * @returns {Promise<{ok: boolean, text: string, raw: object}>}
 */
// Strips common hand-edited-.env mistakes: wrapping quotes, stray
// whitespace, and a redundant leading "models/" (the base URL already ends
// in /models, so GEMINI_MODEL should be just the bare model id).
function cleanEnvValue(v) {
  if (!v) return v;
  let out = v.trim();
  if ((out.startsWith('"') && out.endsWith('"')) || (out.startsWith("'") && out.endsWith("'"))) {
    out = out.slice(1, -1).trim();
  }
  return out;
}

async function runGemini(prompt, opts = {}) {
  const apiKey = cleanEnvValue(process.env.GEMINI_API_KEY);
  // Pro-tier models (gemini-2.5-pro and anything gemini-3.x-pro) lost free-
  // tier quota in an April 2026 policy change - they now 429 with
  // limit: 0 on a free-tier key regardless of usage, not because you've hit
  // a cap. Flash models are the ones that still actually work for free.
  let model = cleanEnvValue(process.env.GEMINI_MODEL) || 'gemini-2.5-flash';
  model = model.replace(/^models\//, ''); // baseUrl already ends in /models
  const baseUrl = (cleanEnvValue(process.env.GEMINI_BASE_URL) || 'https://generativelanguage.googleapis.com/v1beta/models').replace(/\/+$/, '');
  const timeoutMs = opts.timeoutMs || DEFAULT_TIMEOUT_MS;

  if (/[^a-zA-Z0-9._-]/.test(model)) {
    return {
      ok: false,
      text: `GEMINI_MODEL ("${model}") contains characters that aren't valid in a model id ` +
            `(letters, digits, dots, dashes, underscores only) - check .env for a stray quote, ` +
            `trailing comment, or space. This is a config problem, not an API error.`,
      raw: { invalidModelFormat: true, model },
    };
  }

  if (opts.dryRun) {
    return {
      ok: true,
      text: '[DRY RUN] Gemini stub plan/review - no real API call made.\n\n' +
            'PLAN (stub): implement as requested, no special risks identified.\n' +
            'This is a placeholder so the pipeline can be exercised end-to-end.',
      raw: { dryRun: true },
    };
  }

  if (!apiKey) {
    return {
      ok: false,
      text: 'GEMINI_API_KEY is not set. A Gemini Advanced/Google AI Pro subscription ' +
            'does not include API access - get a separate (free-tier available) key at ' +
            'https://aistudio.google.com/apikey and put it in .env.',
      raw: { missingKey: true },
    };
  }

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);

  try {
    const res = await fetch(`${baseUrl}/${model}:generateContent`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-goog-api-key': apiKey,
      },
      body: JSON.stringify({
        systemInstruction: {
          parts: [{
            text: 'You are Gemini, acting as planner and second reviewer alongside Claude ' +
                  '(author) and Hermes (independent verifier) on RougeXHunter. Be concrete: ' +
                  'concrete file/API-level plans when planning, line-level findings tagged ' +
                  'CRITICAL/MAJOR/MINOR/NIT when reviewing - never vague advice.',
          }],
        },
        contents: [{ role: 'user', parts: [{ text: prompt }] }],
      }),
      signal: controller.signal,
    });

    clearTimeout(timer);
    const bodyText = await res.text();
    let json;
    try { json = JSON.parse(bodyText); } catch { json = null; }

    if (!res.ok) {
      const rawMsg = json?.error?.message || bodyText.slice(0, 500);
      const isZeroQuota = res.status === 429 && /limit:\s*0\b/.test(rawMsg);
      const hint = isZeroQuota
        ? ` (this is a free-tier billing wall for "${model}", not a usage cap you've hit - ` +
          `Pro-tier models require paid billing since April 2026; switch GEMINI_MODEL to a ` +
          `Flash model like gemini-2.5-flash instead of adding a card)`
        : '';
      return {
        ok: false,
        text: `Gemini API returned HTTP ${res.status}: ${rawMsg}${hint}`,
        raw: { status: res.status, body: json || bodyText },
      };
    }

    const candidate = json?.candidates?.[0];
    const text = candidate?.content?.parts?.map((p) => p.text).filter(Boolean).join('');
    if (!text) {
      // A common non-error case: the model stopped early for safety/recitation
      // reasons - surface finishReason rather than a bare "no content" message.
      const reason = candidate?.finishReason || 'unknown';
      return { ok: false, text: `Gemini response had no text content (finishReason: ${reason}).`, raw: json };
    }
    return { ok: true, text, raw: json };
  } catch (err) {
    clearTimeout(timer);
    const timedOut = err.name === 'AbortError';
    return {
      ok: false,
      text: timedOut
        ? `Gemini call timed out after ${timeoutMs}ms.`
        : `Gemini call failed: ${err.message}`,
      raw: { error: err.message, timedOut },
    };
  }
}

module.exports = { runGemini };
