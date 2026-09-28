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

import {verifyIdToken} from "./auth.ts";
import {
  fill,
  askGemini, isIntent, ruleFallback,
  type AdjustContext, type PlanExercise,
} from "./adjust.ts";
import {askQuality, isSessions} from "./screen.ts";
import {askIntent, isSay} from "./classify.ts";
import {consume, limitMessage, DAILY_LIMIT} from "./limit.ts";

interface Env {
  GEMINI_API_KEY: string;
  ALLOWED_ORIGIN: string;
  FIREBASE_PROJECT_ID: string;
  /** 每人每日呼叫次數的計數器。**可有可無** —— 沒綁定就不擋（見 `limit.ts`）。 */
  AI_USAGE?: KVNamespace;
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
      say?: unknown;
    };
    try {
      body = await req.json();
    } catch {
      return fail(400, "請求不是合法的 JSON。", origin);
    }

    /**
     * 記一次用量並決定放不放行。**每個分支各自在驗完輸入之後才呼叫** ——
     * 擺在這裡之前的話，一個格式錯誤的請求也會吃掉一次額度，
     * 而它根本沒碰到 Gemini。
     *
     * 回傳非空值代表被擋下來了，直接把它回給前端。
     */
    const overLimit = async (): Promise<Response | null> => {
      const v = await consume(env.AI_USAGE, uid, new Date());
      if (v.allowed) return null;
      console.log(`用量上限：${uid} 今日第 ${v.used} 次`);
      // 429 —— 與 Gemini 自己的額度錯誤同一個狀態碼，但訊息完全不同：
      // 那個是上游的額度，這個是我們自己設的上限。
      return fail(429, limitMessage(DAILY_LIMIT), origin);
    };

    // --- 意圖分類（2026-09-27 使用者裁決：一律先給 AI 判斷）---
    //
    // 同一個端點、看有沒有 `say` 分流，理由同下面那一段。
    //
    // **這一段也沒有規則退路。** 失敗就回非 200，由 App 退回它自己那份
    // `parseIntent()` —— 端內那份關鍵字比對本來就在，而且是唯一一份。
    if (body.say !== undefined) {
      if (!isSay(body.say)) {
        return fail(400, "say 必須是 1–200 字的字串。", origin);
      }
      const blocked = await overLimit();
      if (blocked) return blocked;
      try {
        // 不先探測模型 —— `callGemini` 直接用偏好的那個，
        // 只有它 404 時才去問清單。原本每次都多一趟 `listModels`，
        // 冷啟動時會超過前端等待的上限（使用者回報「分析時間非常久」）。
        const intent = await askIntent(body.say, env.GEMINI_API_KEY);
        // `intent: null` 是**合法結果**，不是錯誤 ——
        // 模型判不出來時就該這樣回，由 App 再問一次。
        return new Response(JSON.stringify({intent, source: "gemini"}), {
          headers: {"Content-Type": "application/json", ...cors(origin)},
        });
      } catch (e) {
        const msg = e instanceof Error ? e.message : String(e);
        console.error("意圖分類失敗：", msg);
        return fail(502, `分類失敗：${msg}`, origin);
      }
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
      const blocked = await overLimit();
      if (blocked) return blocked;
      try {
        const q = await askQuality(body.sessions, env.GEMINI_API_KEY);
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

    const blocked = await overLimit();
    if (blocked) return blocked;

    let source = "rule";
    let error: string | undefined;
    let changes = ruleFallback(exercises, intent);
    try {
      const fromModel =
        await askGemini(exercises, intent, env.GEMINI_API_KEY, note, ctx);
      if (fromModel.length > 0) {
        source = "gemini";
        // **被丟掉的那幾項要補回來，而且要出聲。**
        //
        // `clamp()` 丟掉一筆，那個動作就整個不會出現在畫面的表格裡：
        // 使用者說「我沒有槓鈴」，四個動作的課表回來只剩三列，而那個
        // 槓鈴動作一聲不響地維持原樣 —— 他既看不到它，也不知道有東西
        // 被丟了。補成「維持原樣」才是實話：`applySuggestion()` 對
        // 缺席的索引本來就是不動它。
        changes = fill(exercises, fromModel);
        const dropped = exercises.length - fromModel.length;
        if (dropped > 0) {
          error = `模型有 ${dropped} 項沒有通過驗證，那幾項維持原設定`;
        }
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
