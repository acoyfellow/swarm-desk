import { execFile } from "node:child_process";
import { cpSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { promisify } from "node:util";
import vm from "node:vm";
import { TASKS, judge, parseReport } from "./tasks.mjs";
import { systemPrompt, userPrompt } from "./prompts.mjs";

const run = promisify(execFile);
const ROOT = new URL(".", import.meta.url).pathname;
const WORK = join(ROOT, "work");
const MAX_TRIES = Number(process.env.TRIES ?? 3);
const OPUS_URL = process.env.LLM_URL ?? "https://api.anthropic.com/v1/messages";
const MODEL = "claude-opus-5-5";
const PRICE = { inPerM: 15, outPerM: 75 };
const GLEAM_IMPORTS = new Set(["draft", "gleam/string", "gleam/list", "gleam/int", "gleam/result", "gleam/option", "gleam/dict", "gleam/bool", "gleam/order"]);

const apiKey = process.env.ANTHROPIC_API_KEY;
if (!apiKey && !process.env.LLM_URL) throw new Error("Set ANTHROPIC_API_KEY");
const authHeaders = apiKey ? { "x-api-key": apiKey } : {};

const limiter = (n) => {
  let active = 0;
  const queue = [];
  const next = () => { if (active < n && queue.length) { active++; const { fn, resolve, reject } = queue.shift(); fn().then(resolve, reject).finally(() => { active--; next(); }); } };
  return (fn) => new Promise((resolve, reject) => { queue.push({ fn, resolve, reject }); next(); });
};
const opusSlot = limiter(Number(process.env.OPUS_CONCURRENCY ?? 12));
const gleamSlot = limiter(Number(process.env.GLEAM_CONCURRENCY ?? 6));

const askOpus = (lang, task, feedback) => opusSlot(async () => {
  for (let attempt = 1; attempt <= 4; attempt++) {
    const started = Date.now();
    const response = await fetch(OPUS_URL, {
      method: "POST",
      headers: { "content-type": "application/json", "anthropic-version": "2023-06-01", ...authHeaders },
      body: JSON.stringify({ model: MODEL, max_tokens: 2500, system: systemPrompt(lang), messages: [{ role: "user", content: userPrompt(task, feedback) }] }),
    });
    const body = await response.json().catch(() => ({}));
    if (response.ok) {
      const text = (body.content ?? []).filter((c) => c.type === "text").map((c) => c.text).join("").replace(/^```[a-z]*\n?|```\s*$/gm, "").trim();
      const usage = { in: body.usage?.input_tokens ?? 0, out: body.usage?.output_tokens ?? 0 };
      if (body.stop_reason === "refusal") return { text: "", refused: true, usage, ms: Date.now() - started };
      if (text) return { text, usage, ms: Date.now() - started, stop: body.stop_reason };
    }
    await new Promise((r) => setTimeout(r, 1500 * attempt));
  }
  throw new Error(`opus failed for ${task.id}/${lang}`);
});

const jsPrecheck = (code) => {
  try { new vm.Script(`(async () => {\n${code}\n})()`); return null; } catch (error) { return `SyntaxError: ${error.message}`; }
};

const jsExecute = async (task, code, dir) => {
  writeFileSync(join(dir, "attempt.js"), code);
  writeFileSync(join(dir, "seed.json"), JSON.stringify(task.files));
  const out = await run("node", [join(ROOT, "template-js/run.mjs"), join(dir, "attempt.js"), join(dir, "seed.json")], { timeout: 15000 }).then((r) => r.stdout, (e) => e.stdout ?? "");
  return parseReport(out);
};

const gleamImportsOk = (code) => {
  if (/@external|@target/.test(code)) return "banned attribute (@external/@target)";
  const bad = [...code.matchAll(/^\s*import\s+([a-z_/]+)/gm)].map((m) => m[1]).filter((name) => !GLEAM_IMPORTS.has(name));
  return bad.length ? `import not allowed: ${bad.join(", ")}` : null;
};

const gleamLiteral = (s) => JSON.stringify(s);
const gleamHarness = (task) => {
  const entries = task.files.map((f) => (f.slot ? `draft.slot(${gleamLiteral(f.path)})` : `draft.seed(${gleamLiteral(f.path)}, ${gleamLiteral(f.content)}, ${f.readable ? "True" : "False"}, ${f.writable ? "True" : "False"})`));
  return `import attempt\nimport draft\n\npub fn main() {\n  draft.new([${entries.join(", ")}])\n  |> attempt.run\n  |> draft.report\n}\n`;
};

const gleamPrepare = (task, code, dir) => {
  rmSync(dir, { recursive: true, force: true });
  cpSync(join(ROOT, "template"), dir, { recursive: true });
  writeFileSync(join(dir, "src/attempt.gleam"), code);
  writeFileSync(join(dir, "src/harness.gleam"), gleamHarness(task));
};

const gleamPrecheck = (task, code, dir) => gleamSlot(async () => {
  const banned = gleamImportsOk(code);
  if (banned) return banned;
  gleamPrepare(task, code, dir);
  return run("gleam", ["build"], { cwd: dir, timeout: 120000 }).then(() => null, (e) => (e.stderr || e.stdout || String(e)).replace(/\x1b\[[0-9;]*m/g, "").slice(0, 1500));
});

const gleamExecute = (task, dir) => gleamSlot(async () => {
  const out = await run("gleam", ["run", "-m", "harness", "--no-print-progress"], { cwd: dir, timeout: 30000 }).then((r) => r.stdout, (e) => `${e.stdout ?? ""}\nTHROW\t${JSON.stringify(((e.stderr || "") + "").replace(/\x1b\[[0-9;]*m/g, "").slice(0, 300) || "crash")}`);
  const parsed = parseReport(out);
  if (!parsed.ended) {
    const untouched = parseReport(task.files.map((f) => `F\t${JSON.stringify(f.path)}\t${JSON.stringify(f.slot ? "" : f.content)}\t${f.slot ? 0 : 1}\t0\t0`).join("\n"));
    return { ...untouched, ended: false, threw: parsed.threw ?? "crash before done" };
  }
  return parsed;
});

const REFUSAL_RETRIES = Number(process.env.REFUSAL_RETRIES ?? 4);

const attemptTask = async (lang, task) => {
  const tries = [];
  const refusalLog = [];
  let feedback = null;
  for (let n = 1; n <= MAX_TRIES; n++) {
    const dir = join(WORK, lang, `${task.id}-${n}`);
    mkdirSync(dir, { recursive: true });
    let opus = await askOpus(lang, task, feedback);
    for (let again = 0; opus.refused && again < REFUSAL_RETRIES; again++) {
      refusalLog.push({ n, usage: opus.usage });
      opus = await askOpus(lang, task, feedback);
    }
    if (opus.refused) {
      refusalLog.push({ n, usage: opus.usage });
      tries.push({ n, usage: { in: 0, out: 0 }, opus_ms: opus.ms, refused: true, caught_before_run: false });
      break;
    }
    const precheck = lang === "js" ? jsPrecheck(opus.text) : await gleamPrecheck(task, opus.text, dir);
    const record = { n, usage: opus.usage, opus_ms: opus.ms, code: opus.text, precheck };
    if (precheck) {
      tries.push({ ...record, caught_before_run: true });
      feedback = precheck;
      continue;
    }
    const state = lang === "js" ? await jsExecute(task, opus.text, dir) : await gleamExecute(task, dir);
    const verdict = judge(task, state);
    tries.push({ ...record, caught_before_run: false, ran: true, pass: verdict.pass, harm: verdict.harm, reasons: verdict.reasons, threw: state.threw });
    if (state.threw && !verdict.pass) { feedback = `runtime error: ${state.threw}`; continue; }
    break;
  }
  const passIndex = tries.findIndex((t) => t.pass);
  return {
    id: task.id,
    trap: task.trap,
    lang,
    pass: passIndex >= 0,
    tries_to_pass: passIndex >= 0 ? passIndex + 1 : null,
    attempts: tries.length,
    caught_before_run: tries.filter((t) => t.caught_before_run).length,
    refusals: refusalLog.length,
    gave_up_refused: tries.some((t) => t.refused),
    bad_runs: tries.filter((t) => t.ran && !t.pass).length,
    harmful_runs: tries.filter((t) => t.harm).length,
    tokens_in: tries.reduce((s, t) => s + t.usage.in, 0) + refusalLog.reduce((s, r) => s + r.usage.in, 0),
    tokens_out: tries.reduce((s, t) => s + t.usage.out, 0) + refusalLog.reduce((s, r) => s + r.usage.out, 0),
    tries,
  };
};

const only = process.env.ONLY ? new Set(process.env.ONLY.split(",")) : null;
const langs = (process.env.LANGS ?? "js,gleam").split(",");
const tasks = TASKS.filter((t) => !only || only.has(t.id));
const started = Date.now();
const results = await Promise.all(langs.flatMap((lang) => tasks.map((task) => attemptTask(lang, task).catch((error) => ({ id: task.id, trap: task.trap, lang, error: String(error), pass: false, tries: [] })))));

const summarize = (lang) => {
  const rows = results.filter((r) => r.lang === lang);
  const tin = rows.reduce((s, r) => s + (r.tokens_in ?? 0), 0);
  const tout = rows.reduce((s, r) => s + (r.tokens_out ?? 0), 0);
  const passed = rows.filter((r) => r.pass);
  return {
    lang,
    tasks: rows.length,
    passed: passed.length,
    passed_traps: rows.filter((r) => r.trap && r.pass).length,
    traps: rows.filter((r) => r.trap).length,
    caught_before_run: rows.reduce((s, r) => s + (r.caught_before_run ?? 0), 0),
    refusals: rows.reduce((s, r) => s + (r.refusals ?? 0), 0),
    tasks_lost_to_refusal: rows.filter((r) => r.gave_up_refused).length,
    bad_runs: rows.reduce((s, r) => s + (r.bad_runs ?? 0), 0),
    harmful_runs: rows.reduce((s, r) => s + (r.harmful_runs ?? 0), 0),
    tasks_with_harm: rows.filter((r) => (r.harmful_runs ?? 0) > 0).length,
    first_try_pass: rows.filter((r) => r.tries_to_pass === 1).length,
    mean_tries_to_pass: passed.length ? Number((passed.reduce((s, r) => s + r.tries_to_pass, 0) / passed.length).toFixed(2)) : null,
    opus_calls: rows.reduce((s, r) => s + (r.attempts ?? 0) + (r.refusals ?? 0), 0),
    tokens_in: tin,
    tokens_out: tout,
    usd_list_price: Number((tin * PRICE.inPerM / 1e6 + tout * PRICE.outPerM / 1e6).toFixed(4)),
    errors: rows.filter((r) => r.error).length,
  };
};

const out = { model: MODEL, max_tries: MAX_TRIES, price_assumption: `$${PRICE.inPerM}/M in, $${PRICE.outPerM}/M out (list price; OpenCode gateway billing not visible)`, wall_ms: Date.now() - started, summary: langs.map(summarize), results };
writeFileSync(process.env.OUT ?? join(ROOT, "results.json"), JSON.stringify(out, null, 2));
for (const s of out.summary) console.log(JSON.stringify(s));
