/**
 * Firebase ID token 的驗證。
 *
 * ## 為什麼一定要驗
 *
 * Firebase 的 callable function 會免費幫你做這件事（`req.auth`），
 * 換到 Cloudflare 就得自己來。**不驗的後果很具體**：這個端點會變成
 * 一個誰都能打的免費 Gemini 中繼站，而金鑰是免費層 ——
 * 被別人拿去跑，你的配額當天就歸零，口試那天 AI 功能直接掛掉。
 *
 * ## 驗什麼
 *
 * Firebase 的 ID token 是 Google 用 RS256 簽的 JWT。四件事都要對：
 * 簽章、`aud`（＝專案 ID）、`iss`（＝securetoken.google.com/專案ID）、
 * 以及還沒過期。少驗任何一項，偽造的 token 就過得去。
 */

/** Google 公開金鑰。JWK 格式可以直接餵給 `crypto.subtle.importKey`。 */
const JWK_URL =
  "https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com";

interface Jwk { kid: string; n: string; e: string; kty: string; alg: string }

let cache: { keys: Map<string, CryptoKey>; until: number } | null = null;

async function keys(): Promise<Map<string, CryptoKey>> {
  // Google 會輪替金鑰，但不會每分鐘換。快取一小時，省掉每次請求一趟往返。
  if (cache && cache.until > Date.now()) return cache.keys;

  const res = await fetch(JWK_URL);
  if (!res.ok) throw new Error(`jwk ${res.status}`);
  const body = await res.json() as { keys: Jwk[] };

  const map = new Map<string, CryptoKey>();
  for (const jwk of body.keys) {
    map.set(
      jwk.kid,
      await crypto.subtle.importKey(
        "jwk",
        {kty: jwk.kty, n: jwk.n, e: jwk.e, alg: "RS256", ext: true},
        {name: "RSASSA-PKCS1-v1_5", hash: "SHA-256"},
        false,
        ["verify"],
      ),
    );
  }
  cache = {keys: map, until: Date.now() + 60 * 60 * 1000};
  return map;
}

/** base64url → bytes。JWT 用的是 url-safe 變體，不能直接丟給 atob。 */
function b64url(s: string): Uint8Array {
  const b64 = s.replace(/-/g, "+").replace(/_/g, "/")
    .padEnd(s.length + (4 - s.length % 4) % 4, "=");
  const bin = atob(b64);
  return Uint8Array.from(bin, (c) => c.charCodeAt(0));
}

/**
 * 驗過就回 uid，沒過就回 null。
 *
 * **只回 uid，不回整個 token 內容** —— 呼叫端需要知道的只有「是誰」，
 * 多給的每一個欄位都是多一個被誤用的機會。
 */
export async function verifyIdToken(
  token: string,
  projectId: string,
): Promise<string | null> {
  try {
    const [h, p, sig] = token.split(".");
    if (!h || !p || !sig) return null;

    const header = JSON.parse(new TextDecoder().decode(b64url(h)));
    if (header.alg !== "RS256" || typeof header.kid !== "string") return null;

    const key = (await keys()).get(header.kid);
    if (!key) return null;

    const ok = await crypto.subtle.verify(
      "RSASSA-PKCS1-v1_5",
      key,
      b64url(sig),
      new TextEncoder().encode(`${h}.${p}`),
    );
    if (!ok) return null;

    const claims = JSON.parse(new TextDecoder().decode(b64url(p)));
    const now = Math.floor(Date.now() / 1000);
    if (claims.aud !== projectId) return null;
    if (claims.iss !== `https://securetoken.google.com/${projectId}`) return null;
    if (typeof claims.exp !== "number" || claims.exp < now) return null;
    if (typeof claims.sub !== "string" || claims.sub.length === 0) return null;

    return claims.sub;
  } catch {
    // 格式壞掉、JSON 解不開、金鑰抓不到 —— 一律當作沒驗過。
    return null;
  }
}
