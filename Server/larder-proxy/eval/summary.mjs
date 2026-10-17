#!/usr/bin/env node
// Prints per-route results for one variant from .claude/hillclimb/<route>/<variant>/: every metric
// with a 95% interval, per-case worst-rep rates, route outcomes, failed attempts, tokens and cost.
//
//   node eval/summary.mjs [--variant baseline]
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

const ROUTES = ['explain', 'parse-pantry', 'parse-recipe', 'adjust'];
const variantFlag = process.argv.indexOf('--variant');
const variant = variantFlag === -1 ? 'baseline' : process.argv[variantFlag + 1];

const readJsonl = (path) => (existsSync(path) ? readFileSync(path, 'utf8').split('\n').filter((line) => line.trim()).map((line) => JSON.parse(line)) : []);

/** Wilson score interval for k successes out of n. */
function wilson(k, n) {
  if (n === 0) return [NaN, NaN];
  const z = 1.96, p = k / n, d = 1 + (z * z) / n;
  const centre = (p + (z * z) / (2 * n)) / d;
  const half = (z * Math.sqrt((p * (1 - p)) / n + (z * z) / (4 * n * n))) / d;
  return [centre - half, centre + half];
}

/** Dollars for one call: base input, cache writes at 1.25x and cache reads at 0.1x of the input rate. */
function cost(usage, price) {
  if (!usage || !price) return 0;
  const input = (usage.input_tokens ?? 0) + 1.25 * (usage.cache_creation_input_tokens ?? 0) + 0.1 * (usage.cache_read_input_tokens ?? 0);
  return (input * price.in + (usage.output_tokens ?? 0) * price.out) / 1e6;
}

const pct = (x) => (Number.isFinite(x) ? `${(100 * x).toFixed(1)}%` : '-');
const quantiles = (xs) => {
  const s = [...xs].sort((a, b) => a - b);
  return s.length ? [s[0], s[Math.floor(s.length / 2)], s[s.length - 1]] : [0, 0, 0];
};

let grand = 0;
for (const route of ROUTES) {
  const flow = join('.claude', 'hillclimb', route);
  const dir = join(flow, variant);
  const rows = readJsonl(join(dir, 'results.jsonl'));
  const errors = readJsonl(join(dir, 'errors.jsonl'));
  if (!rows.length && !errors.length) continue;
  const state = JSON.parse(readFileSync(join(flow, '_state.json'), 'utf8'));
  const ok = rows.filter((row) => row.status === 'ok');
  const truncated = rows.length - ok.length;
  const cases = new Set(rows.map((row) => row.prompt_id)).size;

  console.log(`\n## ${route}  (${variant}; ${cases} cases, ${rows.length} rows, ${truncated} truncated, ${errors.length} failed attempts)`);
  const outcomes = {};
  for (const row of rows) outcomes[row.outcome] = (outcomes[row.outcome] ?? 0) + 1;
  console.log(`route outcomes: ${Object.entries(outcomes).map(([key, n]) => `${key} ${n}`).join(', ')}`);

  for (const metric of state.metrics) {
    const values = ok.map((row) => row.grade?.[metric.id]).filter((value) => typeof value === 'number');
    if (!values.length) continue;
    const mean = values.reduce((sum, value) => sum + value, 0) / values.length;
    if (metric.kind === 'binary') {
      const [lo, hi] = wilson(values.filter((value) => value === 1).length, values.length);
      // A case counts as failing when any of its reps failed (for lower-is-better, when any rep hit).
      const byCase = new Map();
      for (const row of ok) {
        const value = row.grade?.[metric.id];
        if (typeof value !== 'number') continue;
        const bad = metric.better === 'lower' ? value === 1 : value === 0;
        byCase.set(row.prompt_id, (byCase.get(row.prompt_id) ?? false) || bad);
      }
      const badCases = [...byCase].filter(([, bad]) => bad).map(([id]) => id);
      console.log(`  ${metric.id.padEnd(14)} ${pct(mean).padStart(6)}  [${pct(lo)}, ${pct(hi)}]  n=${values.length}  cases with a ${metric.better === 'lower' ? 'hit' : 'failing rep'}: ${badCases.length}/${byCase.size}${badCases.length ? `  (${badCases.join(', ')})` : ''}`);
    } else {
      console.log(`  ${metric.id.padEnd(14)} ${mean.toFixed(3).padStart(6)}  mean over n=${values.length}`);
    }
  }

  const calls = [...rows, ...errors.filter((error) => error.usage)];
  const dollars = calls.reduce((sum, call) => sum + cost(call.usage, state.prices?.[call.model]), 0);
  grand += dollars;
  const [inLo, inMed, inHi] = quantiles(calls.map((call) => (call.usage?.input_tokens ?? 0) + (call.usage?.cache_read_input_tokens ?? 0) + (call.usage?.cache_creation_input_tokens ?? 0)));
  const [outLo, outMed, outHi] = quantiles(calls.map((call) => call.usage?.output_tokens ?? 0));
  const [latLo, latMed, latHi] = quantiles(rows.map((row) => row.latency_s ?? 0));
  const models = [...new Set(calls.map((call) => call.model))].join(', ');
  console.log(`  model ${models}; tokens in ${inLo}/${inMed}/${inHi}, out ${outLo}/${outMed}/${outHi} (min/median/max); latency ${latLo}/${latMed}/${latHi}s; cost $${dollars.toFixed(4)}`);
  for (const error of errors) console.log(`  failed: ${error.prompt_id} rep${error.rep} ${error.failure_class}: ${error.error}`);
}
console.log(`\ntotal cost $${grand.toFixed(4)}`);
