type Jwk = JsonWebKey & { readonly kid: string };

const keyCache = new Map<string, { readonly keys: ReadonlyArray<Jwk>; readonly at: number }>();
const KEY_TTL_MS = 3_600_000;

const decodePart = (part: string): Uint8Array => Uint8Array.from(atob(part.replace(/-/g, '+').replace(/_/g, '/')), (c) => c.charCodeAt(0));

const keysFor = async (team: string): Promise<ReadonlyArray<Jwk>> => {
  const cached = keyCache.get(team);
  if (cached && Date.now() - cached.at < KEY_TTL_MS) return cached.keys;
  const body = (await (await fetch(`${team}/cdn-cgi/access/certs`)).json()) as { readonly keys: ReadonlyArray<Jwk> };
  keyCache.set(team, { keys: body.keys, at: Date.now() });
  return body.keys;
};

export type AccessConfig = { readonly team: string; readonly aud: string; readonly emailDomain?: string };

export const verifyAccess = async (request: Request, config: AccessConfig): Promise<string | null> => {
  const token = request.headers.get('cf-access-jwt-assertion');
  if (!token) return null;
  const [header, payload, signature] = token.split('.');
  if (!header || !payload || !signature) return null;
  const { kid } = JSON.parse(new TextDecoder().decode(decodePart(header))) as { readonly kid?: string };
  const jwk = (await keysFor(config.team)).find((key) => key.kid === kid);
  if (!jwk) return null;
  const key = await crypto.subtle.importKey('jwk', jwk, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['verify']);
  const valid = await crypto.subtle.verify('RSASSA-PKCS1-v1_5', key, decodePart(signature), new TextEncoder().encode(`${header}.${payload}`));
  if (!valid) return null;
  const claims = JSON.parse(new TextDecoder().decode(decodePart(payload))) as { readonly aud?: string | ReadonlyArray<string>; readonly exp?: number; readonly email?: string };
  const audiences = Array.isArray(claims.aud) ? claims.aud : [claims.aud];
  if (!audiences.includes(config.aud)) return null;
  if (!claims.exp || claims.exp * 1000 < Date.now()) return null;
  if (!claims.email) return null;
  if (config.emailDomain && !claims.email.toLowerCase().endsWith(`@${config.emailDomain}`)) return null;
  return claims.email;
};
