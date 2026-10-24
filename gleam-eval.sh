#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
fail=0
check() { if eval "$2"; then echo "✓ $1"; else echo "✗ $1"; fail=1; fi; }

check "gleam installed" 'gleam --version >/dev/null 2>&1'
check "gleam draft module builds and reports" '(cd gleam-eval/template && gleam run -m harness --no-print-progress 2>/dev/null | grep -q "^END$")'

if [ ! -s gleam-eval/results.json ] || [ "${RERUN:-0}" = 1 ]; then
  echo "running the eval (Opus, 30 tasks x 2 languages)…"
  (cd gleam-eval && rm -rf work && node run.mjs | tail -2)
fi

node gleam-eval/receipt.mjs

check "results cover 30 tasks in both languages" 'node -e "const r=require(\"./gleam-eval/results.json\"); const ok=[\"js\",\"gleam\"].every(l=>new Set(r.results.filter(x=>x.lang===l).map(x=>x.id)).size===30); process.exit(ok?0:1)"'
check "every task scored by the automatic check (no runner errors)" 'node -e "const r=require(\"./gleam-eval/results.json\"); process.exit(r.results.every(x=>!x.error && Array.isArray(x.tries) && x.tries.length>0) ? 0 : 1)"'
check "RECEIPTS-GLEAM.md has both languages and the four numbers" 'grep -q "^| | JS | Gleam |" RECEIPTS-GLEAM.md && grep -q "caught \*\*before\*\* running" RECEIPTS-GLEAM.md && grep -q "did \*\*harm\*\*" RECEIPTS-GLEAM.md && grep -q "^| Tries to pass" RECEIPTS-GLEAM.md && grep -q "^| Opus tokens in / out" RECEIPTS-GLEAM.md'
check "RECEIPTS-GLEAM.md lists all 30 tasks" '[ "$(grep -cE "^\| [nt][0-9]{2} \|" RECEIPTS-GLEAM.md)" -eq 30 ]'

if [ "$fail" = 0 ]; then echo "GLEAM EVAL PASS"; else echo "GLEAM EVAL FAIL"; fi
exit "$fail"
