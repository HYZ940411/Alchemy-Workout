/**
 * 健金術的雲端函式（`[BE-08]`）。
 *
 * ## 這個檔案存在的唯一理由是「金鑰不能放在前端」
 *
 * App 是純前端。Flutter Web 建置出來的 `main.dart.js` 會原封不動送到
 * 每一位訪客的瀏覽器，Android APK 解包也一樣 —— 金鑰寫在裡面等同公開。
 * 所以 Gemini 的呼叫必須發生在伺服器端，App 只呼叫自己的端點。
 *
 * ## 模型產出的東西一律不信
 *
 * 規格把 LLM 放在軟體邊界之外，而邊界之內的不變條件要由我們守：
 * 模型可能回傳課表裡不存在的動作、負的重量、或是 0 組。
 * 所以 [clamp] 會拿模型的輸出去對**使用者送上來的那份課表**逐項驗證，
 * 任何對不上的項目一律丟棄；整份都不合格時退回 [ruleFallback]，
 * 也就是 App 內那組規則的同一份邏輯。
 *
 * **使用者永遠拿得到一份可用的建議**，差別只在它來自模型還是規則。
 */

import {onCall, HttpsError} from "firebase-functions/v2/https";
import {defineSecret} from "firebase-functions/params";
import {setGlobalOptions} from "firebase-functions/v2";

/** 金鑰放 Secret Manager，不進版控、不進環境變數檔。 */
const GEMINI_API_KEY = defineSecret("GEMINI_API_KEY");

// 與 Firestore 同區（asia-east1），少一趟跨區往返。
setGlobalOptions({region: "asia-east1", maxInstances: 10});

type Intent = "easier" | "harder" | "trim";

interface PlannedSet { weight: number; reps: number }
interface PlanExercise { name: string; sets: PlannedSet[] }
interface Change { index: number; name: string; after: PlannedSet[] }

const INTENT_TEXT: Record<Intent, string> = {
  easier: "整體降低強度：降低單組負荷，但盡量維持總訓練量",
  harder: "整體提高強度：提高負荷，組數與次數維持",
  trim: "減少訓練量：減少組數，重量與次數維持",
};

/** 場館槓片以 2.5kg 為級距，推到小數點沒有意義。 */
const round2p5 = (kg: number) => Math.round(kg / 2.5) * 2.5;

/**
 * App 內那組規則的同一份邏輯。
 *
 * **刻意重複實作一次。** 這是整個專案最想避免的事（見 `PROGRESS.md`
 * 第 6 節第 3 條「務必保持只有一份實作」），但這裡沒有別的選擇：
 * 模型失敗時使用者得拿到東西，而 Dart 那一份跑不到這裡。
 * 兩份要一起改 —— 改動時請同步 `lib/domain/ai_adjust.dart`。
 */
function ruleFallback(exercises: PlanExercise[], intent: Intent): Change[] {
  return exercises.map((e, index) => {
    let after: PlannedSet[];
    switch (intent) {
    case "easier":
      after = e.sets.map((s) => ({
        weight: s.weight === 0 ? 0 : Math.max(2.5, round2p5(s.weight * 0.9)),
        reps: s.reps + 2,
      }));
      break;
    case "harder":
      after = e.sets.map((s) => ({
        weight: s.weight === 0 ? 0 : round2p5(s.weight * 1.05),
        reps: s.reps,
      }));
      break;
    case "trim":
      // 砍到 0 組等於刪掉這個動作，那是「移除動作」不是「減量」。
      after = e.sets.length > 1 ? e.sets.slice(0, -1) : e.sets;
      break;
    }
    return {index, name: e.name, after};
  });
}

/**
 * 拿模型的輸出對使用者送上來的課表逐項驗證。
 *
 * 丟棄的條件：索引超出範圍、動作名稱對不上、組數為 0 或超過原本 ＋2、
 * 重量為負或超出原重量的 ±50%、次數不在 1–50。
 * 這些界線不是品味問題 —— 模型算錯一個數字，使用者照著做會受傷。
 */
function clamp(exercises: PlanExercise[], raw: unknown): Change[] {
  if (!Array.isArray(raw)) return [];
  const out: Change[] = [];

  for (const item of raw) {
    if (typeof item !== "object" || item === null) continue;
    const c = item as Record<string, unknown>;
    const index = typeof c.index === "number" ? c.index : -1;
    if (index < 0 || index >= exercises.length) continue;

    const src = exercises[index];
    if (c.name !== src.name) continue;
    if (!Array.isArray(c.after) || c.after.length === 0) continue;
    if (c.after.length > src.sets.length + 2) continue;

    const after: PlannedSet[] = [];
    let ok = true;
    for (let i = 0; i < c.after.length; i++) {
      const s = c.after[i] as Record<string, unknown>;
      const ref = src.sets[Math.min(i, src.sets.length - 1)];
      const w = typeof s?.weight === "number" ? s.weight : NaN;
      const r = typeof s?.reps === "number" ? Math.round(s.reps) : NaN;
      if (!Number.isFinite(w) || w < 0) { ok = false; break; }
      if (!Number.isFinite(r) || r < 1 || r > 50) { ok = false; break; }
      // 自體重動作維持 0；有重量的動作不得偏離原值 ±50%。
      if (ref.weight === 0 ? w !== 0 : (w < ref.weight * 0.5 || w > ref.weight * 1.5)) {
        ok = false;
        break;
      }
      after.push({weight: w === 0 ? 0 : round2p5(w), reps: r});
    }
    if (ok) out.push({index, name: src.name, after});
  }
  return out;
}

/** 只讓模型回 JSON，並且把「不准發明課表以外的動作」寫進指令。 */
function buildPrompt(exercises: PlanExercise[], intent: Intent): string {
  return [
    "你是重量訓練的課表調整助手。只依照下列這份課表作答，",
    "不得新增、刪除或替換任何動作，不得引用課表以外的動作。",
    "",
    `調整方向：${INTENT_TEXT[intent]}`,
    "",
    "課表（JSON）：",
    JSON.stringify(exercises),
    "",
    "請只輸出 JSON 陣列，不要有任何說明文字或程式碼框，格式為：",
    "[{\"index\":0,\"name\":\"動作名稱\",\"after\":[{\"weight\":60,\"reps\":8}]}]",
    "",
    "限制：index 與 name 必須與上方課表一致；weight 為公斤，",
    "自體重動作維持 0，其餘不得偏離原重量的 ±50%；reps 介於 1 到 50。",
  ].join("\n");
}

async function askGemini(
  exercises: PlanExercise[],
  intent: Intent,
  apiKey: string,
): Promise<Change[]> {
  const url =
    "https://generativelanguage.googleapis.com/v1beta/models/" +
    "gemini-2.0-flash:generateContent";

  const res = await fetch(url, {
    method: "POST",
    headers: {"Content-Type": "application/json", "x-goog-api-key": apiKey},
    body: JSON.stringify({
      contents: [{parts: [{text: buildPrompt(exercises, intent)}]}],
      generationConfig: {temperature: 0.2, responseMimeType: "application/json"},
    }),
    // 使用者在等，超過這個時間不如讓它走失敗退點的既有流程。
    signal: AbortSignal.timeout(20000),
  });
  if (!res.ok) throw new Error(`gemini ${res.status}`);

  const data = await res.json() as {
    candidates?: { content?: { parts?: { text?: string }[] } }[];
  };
  const text = data.candidates?.[0]?.content?.parts?.[0]?.text ?? "";
  return clamp(exercises, JSON.parse(text));
}

/**
 * App 呼叫的唯一端點。
 *
 * 回傳的 `source` 讓前端與後台看得出這一次是模型產的還是規則產的 ——
 * 兩者都是合法結果，但分不出來的話就查不出模型什麼時候開始失常。
 */
export const adjustPlan = onCall(
  {secrets: [GEMINI_API_KEY], timeoutSeconds: 30},
  async (req) => {
    if (!req.auth) {
      throw new HttpsError("unauthenticated", "請先登入。");
    }
    const intent = req.data?.intent as Intent;
    const exercises = req.data?.exercises as PlanExercise[];
    if (!["easier", "harder", "trim"].includes(intent)) {
      throw new HttpsError("invalid-argument", "intent 不合法。");
    }
    if (!Array.isArray(exercises) || exercises.length === 0) {
      throw new HttpsError("invalid-argument", "課表是空的。");
    }

    try {
      const changes = await askGemini(exercises, intent, GEMINI_API_KEY.value());
      // 模型全軍覆沒（整份都沒通過驗證）時不讓使用者空手而回。
      if (changes.length > 0) return {source: "gemini", changes};
    } catch (e) {
      console.error("gemini 呼叫失敗，改用規則", e);
    }
    return {source: "rule", changes: ruleFallback(exercises, intent)};
  },
);
