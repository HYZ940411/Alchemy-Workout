/**
 * 健金術的 Gemini 代理（`[BE-08]`）。
 *
 * ## 這個 Worker 存在的唯一理由
 *
 * App 是純前端。Flutter Web 建置出來的 `main.dart.js` 會原封不動送到
 * 每一位訪客的瀏覽器，Android APK 解包也一樣 —— 金鑰寫在裡面等同公開。
 * 所以呼叫 Gemini 這件事必須發生在使用者裝置以外的地方。
 *
 * 原本的設計是 Firebase Cloud Functions，但那需要 Blaze 方案（綁信用卡）。
 * Cloudflare Workers 的免費方案不需要，是同一個問題的另一種解法。
 * 代價是 callable function 免費附送的身分驗證要自己做（見 `auth.ts`）。
 */

import {verifyIdToken} from "./auth";
import {
  askGemini, isIntent, ruleFallback,
  type PlanExercise,
} from "./adjust";

interface Env {
  GEMINI_API_KEY: string;
  ALLOWED_ORIGIN: string;
  FIREBASE_PROJECT_ID: string;
}

const cors = (origin: string) => ({
  "Access-Control-Allow-Origin": origin,
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
  "Access-Control-Max-Age": "86400",
});

const fail = (status: number, msg: string, origin: string) =>
  new Response(JSON.stringify({error: msg}), {
    status,
    headers: {"Content-Type": "application/json", ...cors(origin)},
  });

export default {
  async fetch(req: Request, env: Env): Promise<Response> {
    const origin = env.ALLOWED_ORIGIN;

    if (req.method === "OPTIONS") {
      return new Response(null, {status: 204, headers: cors(origin)});
    }
    if (req.method !== "POST") {
      return fail(405, "只接受 POST。", origin);
    }

    // 沒有這一關，這個端點就是一個誰都能打的免費 Gemini 中繼站，
    // 配額會被別人燒光。
    const auth = req.headers.get("Authorization") ?? "";
    const token = auth.startsWith("Bearer ") ? auth.slice(7) : "";
    const uid = token
      ? await verifyIdToken(token, env.FIREBASE_PROJECT_ID)
      : null;
    if (!uid) return fail(401, "請先登入。", origin);

    let body: {intent?: unknown; exercises?: unknown};
    try {
      body = await req.json();
    } catch {
      return fail(400, "請求不是合法的 JSON。", origin);
    }

    const intent = body.intent;
    const exercises = body.exercises as PlanExercise[] | undefined;
    if (!isIntent(intent)) return fail(400, "intent 不合法。", origin);
    if (!Array.isArray(exercises) || exercises.length === 0) {
      return fail(400, "課表是空的。", origin);
    }

    let source = "rule";
    let changes = ruleFallback(exercises, intent);
    try {
      const fromModel = await askGemini(exercises, intent, env.GEMINI_API_KEY);
      // 模型全軍覆沒（整份都沒通過驗證）時不讓使用者空手而回。
      if (fromModel.length > 0) {
        source = "gemini";
        changes = fromModel;
      }
    } catch (e) {
      console.error("gemini 呼叫失敗，改用規則", e);
    }

    return new Response(JSON.stringify({source, changes}), {
      headers: {"Content-Type": "application/json", ...cors(origin)},
    });
  },
};
