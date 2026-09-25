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
  askGemini, currentModel, isIntent, ruleFallback,
  type AdjustContext, type PlanExercise,
} from "./adjust";
import {askQuality, isSessions} from "./screen";

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

    let body: {
      intent?: unknown; exercises?: unknown;
      note?: unknown; context?: unknown; sessions?: unknown;
    };
    try {
      body = await req.json();
    } catch {
      return fail(400, "請求不是合法的 JSON。", origin);
    }

    // --- 教官申請的訓練品質評分（`[BE-13]` 周邊）---
    //
    // 用同一個端點、看有沒有 `sessions` 分流，而不是另開一條路徑：
    // 驗身分、CORS、錯誤格式三件事完全一樣，分兩條就是同一個決定
    // 寫在兩個地方。
    //
    // **這一段沒有規則退路。** 失敗就回非 200，由 App 退回它自己那份
    // `scoreTrainingQuality()` —— 規則只有一份，在 Dart 裡。
    // （`adjust.ts` 的 `ruleFallback()` 是第二份，`PROGRESS.md` 記著
    // 那是已知的重複實作，不重蹈覆轍。）
    if (body.sessions !== undefined) {
      if (!isSessions(body.sessions)) {
        return fail(400, "訓練紀錄的格式不合法，或筆數超過上限。", origin);
      }
      try {
        const model = await currentModel(env.GEMINI_API_KEY);
        const q = await askQuality(body.sessions, env.GEMINI_API_KEY, model);
        return new Response(JSON.stringify(q), {
          headers: {"Content-Type": "application/json", ...cors(origin)},
        });
      } catch (e) {
        const msg = e instanceof Error ? e.message : String(e);
        console.error("品質評分失敗：", msg);
        // 502 而不是 500：失敗的是上游的模型，不是這個 Worker。
        return fail(502, `評分失敗：${msg}`, origin);
      }
    }

    const intent = body.intent;
    const exercises = body.exercises as PlanExercise[] | undefined;
    // 使用者自己打的話。非字串一律當作沒有 —— 這是外部輸入，
    // 型別都不對的東西沒必要送進 prompt。
    const note = typeof body.note === "string" ? body.note : undefined;
    const ctx = body.context && typeof body.context === "object" ?
      body.context as AdjustContext :
      undefined;
    if (!isIntent(intent)) return fail(400, "intent 不合法。", origin);
    if (!Array.isArray(exercises) || exercises.length === 0) {
      return fail(400, "課表是空的。", origin);
    }

    let source = "rule";
    let error: string | undefined;
    let changes = ruleFallback(exercises, intent);
    try {
      const fromModel =
        await askGemini(exercises, intent, env.GEMINI_API_KEY, note, ctx);
      if (fromModel.length > 0) {
        source = "gemini";
        changes = fromModel;
      } else {
        // 模型回了東西但整份都沒通過驗證 —— 不讓使用者空手而回，
        // 但這件事要講出來，不然看起來跟「模型正常」一模一樣。
        error = "模型的建議沒有通過驗證";
      }
    } catch (e) {
      error = e instanceof Error ? e.message : String(e);
      console.error("gemini 呼叫失敗，改用規則：", error);
    }

    // **把失敗原因回給前端。** 只寫進 log 的話，使用者看到的是一份
    // 「看起來正常、其實是規則產的」建議 —— 靜默退回比失敗更難查。
    return new Response(JSON.stringify({source, changes, error}), {
      headers: {"Content-Type": "application/json", ...cors(origin)},
    });
  },
};
