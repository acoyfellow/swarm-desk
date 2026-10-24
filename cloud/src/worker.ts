import { Container, getContainer } from '@cloudflare/containers';
import { verifyAccess } from './access';

export { ContainerProxy } from '@cloudflare/containers';

type Env = {
  readonly SWARM: DurableObjectNamespace<SwarmContainer>;
  readonly AI: Ai;
  readonly LEDGER: KVNamespace;
  readonly ANTHROPIC_API_KEY: string;
  readonly ACCESS_TEAM?: string;
  readonly ACCESS_AUD?: string;
  readonly ACCESS_EMAIL_DOMAIN?: string;
};

const ALLOWED_MODELS = new Set(['@cf/cloudflare/clef', '@cf/cloudflare/clairic']);
const AI_RUN_PREFIX = '/ai/run/';

const runModel = async (request: Request, env: Env): Promise<Response> => {
  const { pathname } = new URL(request.url);
  const model = decodeURIComponent(pathname.slice(pathname.indexOf(AI_RUN_PREFIX) + AI_RUN_PREFIX.length));
  if (request.method !== 'POST') return Response.json({ success: false, error: 'POST only' }, { status: 405 });
  if (!ALLOWED_MODELS.has(model)) return Response.json({ success: false, error: `model not allowed: ${model}` }, { status: 400 });
  try {
    const result = await env.AI.run(model as Parameters<Ai['run']>[0], await request.json());
    return Response.json({ success: true, result });
  } catch (error) {
    return Response.json({ success: false, error: String(error) }, { status: 502 });
  }
};

const ANTHROPIC_MESSAGES = 'https://api.anthropic.com/v1/messages';
const LEDGER_KEY = 'code-runs';
const LEDGER_KEEP = 500;

const relayModel = async (request: Request, env: Env): Promise<Response> => {
  const { pathname } = new URL(request.url);
  if (request.method !== 'POST' || pathname !== '/anthropic/v1/messages') return new Response('not allowed', { status: 403 });
  const headers = new Headers({ 'content-type': 'application/json', 'anthropic-version': request.headers.get('anthropic-version') ?? '2023-06-01', 'x-api-key': env.ANTHROPIC_API_KEY });
  return fetch(ANTHROPIC_MESSAGES, { method: 'POST', headers, body: request.body });
};

type LedgerRun = Record<string, unknown>;

const ledger = async (request: Request, env: Env): Promise<Response> => {
  const { pathname } = new URL(request.url);
  const runs = ((await env.LEDGER.get(LEDGER_KEY, 'json')) as LedgerRun[] | null) ?? [];
  if (pathname === '/list') return Response.json(runs);
  if (pathname === '/record' && request.method === 'POST') {
    const entry = (await request.json()) as LedgerRun;
    await env.LEDGER.put(LEDGER_KEY, JSON.stringify([entry, ...runs].slice(0, LEDGER_KEEP)));
    return Response.json({ ok: true, runs: runs.length + 1 });
  }
  return new Response('not found', { status: 404 });
};

export class SwarmContainer extends Container<Env> {
  defaultPort = 8080;
  sleepAfter = '30m';
  enableInternet = false;
  envVars = { AI_URL: 'http://ai.internal/ai/run', LLM_URL: 'http://llm.internal/anthropic/v1/messages', LEDGER_URL: 'http://ledger.internal', PORT: '8080' };

  static {
    this.outboundByHost = {
      'ai.internal': (request: Request, env: Env) => runModel(request, env),
      'llm.internal': (request: Request, env: Env) => relayModel(request, env),
      'ledger.internal': (request: Request, env: Env) => ledger(request, env),
    };
  }
}

const signedIn = async (request: Request, env: Env): Promise<boolean> => {
  if (!env.ACCESS_AUD || !env.ACCESS_TEAM) return false;
  const email = await verifyAccess(request, { team: env.ACCESS_TEAM, aud: env.ACCESS_AUD, emailDomain: env.ACCESS_EMAIL_DOMAIN }).catch(() => null);
  return email !== null;
};

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (!(await signedIn(request, env))) return new Response('Sign in with Cloudflare Access.', { status: 403 });
    if (new URL(request.url).pathname.startsWith(AI_RUN_PREFIX)) return runModel(request, env);
    return getContainer(env.SWARM, 'swarm').fetch(request);
  },
};
