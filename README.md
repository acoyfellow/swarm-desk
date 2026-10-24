# swarm-desk

An experiment with one pattern: **fan out many small jobs, let a model decide with odds, let code act only when the odds are high, and send the rest to a person.** Built in Elixir with [Jido](https://github.com/agentjido/jido) agents and Cloudflare Workers AI.

This is an experiment, not a product. It has small built-in rate limits and no accounts. Anyone who can open your deployment spends your model budget.

## What is in it

| Path | What it is |
|---|---|
| `/` | **Support desk.** 100 or 1,000 synthetic tickets, one agent each. Clef (`@cf/cloudflare/clef`) picks an action and returns odds for each option. Code acts at 85% or more; the rest go to a person. 5% of tickets are prompt-injection attacks. "Try to fool it" sends your own ticket through the same path. |
| `/code` | **Coding swarm.** 16 tasks from the `tally` benchmark, one Claude agent each, in parallel. Each agent edits a copy of a small TypeScript repo with tools and runs the visible tests. A judge picks the result by the visible tests plus Clef. Hidden tests only grade the result afterwards; they never pick it. |
| `scripts/eval.exs` | **Eval harness.** Runs agent specs (`evals/agents/*.json`) over a suite, several times each, and writes pass rates, cost and Clef's ship decisions to `evals/results/`. |
| `gleam-eval/` | **Gleam vs JavaScript.** Opus writes 30 small scripts in each language against the same six-verb API. See `RECEIPTS-GLEAM.md`. |
| `cloud/` | A Worker that runs the same app in a [Cloudflare Container](https://developers.cloudflare.com/containers/) with no internet access. The container reaches Workers AI, the LLM and a KV run ledger only through the Worker. |

## Run it

You need Elixir 1.19 / OTP 28, Node 24, a Cloudflare account with Workers AI, and an Anthropic API key for `/code`.

```sh
mix deps.get
export CLOUDFLARE_ACCOUNT_ID=<your account id>
export CLOUDFLARE_API_TOKEN=<a token with Workers AI read>
export ANTHROPIC_API_KEY=<your key>
scripts/local-up.sh
```

Open `http://localhost:8820/` and `http://localhost:8820/code`.

### Settings

| Variable | Default | What it does |
|---|---|---|
| `CLOUDFLARE_ACCOUNT_ID`, `CLOUDFLARE_API_TOKEN` | none | Call Workers AI through the REST API |
| `AI_URL` | none | Call Workers AI through a relay instead, such as the cloud Worker's `/ai/run` |
| `ACCESS_TOKEN_FILE` | none | File with a Cloudflare Access token to send to `AI_URL` |
| `ANTHROPIC_API_KEY` | none | Key for Claude |
| `LLM_URL` | Anthropic Messages API | Send Claude calls through a relay that adds its own auth |
| `CODE_MODEL` | `claude-sonnet-5` | Model for the coding agents |
| `OPUS_MODEL` | `claude-opus-5-5` | Model for `SwarmDesk.Opus` |
| `PORT` | `8820` | HTTP port |

## Evals

```sh
./gate.sh
BENCH_SUITE=hard SPECS=sonnet5-full,haiku45-full REPEATS=3 mix run scripts/eval.exs
./gleam-eval.sh
```

- `gate.sh` runs 200 tickets and fails on any wrong action or on any attack that gets through.
- `bench/tally` has 16 tasks. `bench/hard` has 17 tasks. In `bench/hard`, a reference solution passes every hidden test and the seed fails every one.
- Results from earlier runs are in `evals/results/` and `gleam-eval/results.json`. They are records of single runs, not guarantees.

## Deploy to Cloudflare (optional)

1. Copy `cloud/wrangler.example.jsonc` to `cloud/wrangler.jsonc` and fill in the account ID, domain, KV namespace and Access application.
2. `cd cloud && npm install && npx wrangler secret put ANTHROPIC_API_KEY`
3. `scripts/ship-cloud.sh v1`

The Worker refuses every request without a valid Access token for the configured application. Set `ACCESS_EMAIL_DOMAIN` to also require an email domain.

## What it does not do

- Tickets are synthetic. Nothing here reads real support data.
- Clef's odds are not a guarantee. In the recorded `bench/hard` run, Clef shipped 9 wrong results, all from the Haiku specs.
- Coding agents edit copies of the seed repo on the host and run its tests with `node`. That is not a sandbox. Run it only where you accept that, or in the container.

## Credits

`bench/tally` is adapted from the tally benchmark in [fire_trident](https://github.com/roboruby/fire_trident), MIT. See `bench/tally/LICENSE-fire_trident`.

## License

MIT. See `LICENSE`.
