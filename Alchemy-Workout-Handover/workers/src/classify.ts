/**
 * 把使用者自己打的那句話分類成四個調整方向之一。
 *
 * ## 為什麼交給模型
 *
 * 原本是端內的關鍵字比對（`AppState.parseIntent`）。它很保守 ——
 * 曖昧的詞一律不收，認不出來就再問一次，理由是「猜錯方向讓人照著練
 * 才是問題」。那個理由沒有錯，但代價是使用者打一句再自然不過的話
 * （「今天時間不夠」「我想多練上胸」）常常換來一段「我看不出你想往
 * 哪個方向調」。
 *
 * 2026-09-27 使用者裁決：**一律先給 AI 判斷，端內規則只當 AI 掛掉時的備援。**
 *
 * ## 保守的原則沒有變
 *
 * 模型被要求：**只在明確指向唯一方向時才回答，否則回 null。**
 * 判不出來仍然是再問一次 —— 交給模型是為了聽懂更多說法，
 * 不是為了「無論如何給個答案」。
 */

import {callGemini} from "./gemini.ts";

export type Intent = "easier" | "harder" | "trim" | "swap";

const INTENTS: readonly string[] = ["easier", "harder", "trim", "swap"];

export const isSay = (v: unknown): v is string =>
  typeof v === "string" && v.trim().length > 0 && v.length <= 200;

export function buildPrompt(say: string): string {
  return [
    "你是健身 App 的意圖分類器。使用者被問「這份課表要怎麼調？」，",
    "他的回答如下。請判斷他想往哪些方向調，以及他有沒有講還剩多少時間。",
    "",
    "四個方向：",
    "- easier：整體降強度 —— 他覺得太吃力、狀況不好、想練得輕一點",
    "- harder：整體升強度 —— 他覺得太輕鬆、狀態好、想加重或挑戰，",
    "  **或想多練一些量：加動作、加組、加量都是 harder**",
    "- trim：減少組數 —— **他今天能練的時間變少了**",
    "- swap：替換做不了的動作 —— 某個器材或動作他今天用不了",
    "",
    "**時間那一類要特別注意：說法多半是間接的。**",
    "使用者不會說「請減少組數」，他會說他等一下有別的事。",
    "任何「我待會要去做別的事」「只剩多久」「得早點走」的意思，",
    "都是 trim。",
    "",
    "**一句話可以有兩個方向**，例如「累了而且只剩 20 分鐘」是 easier 與 trim，",
    "「增加動作（增加整體強度）」只是 harder（加動作就是加強度）。",
    "",
    "判斷範例：",
    "- 「我等一下要趕去接小孩」→ [\"trim\"]",
    "- 「只有半小時」→ [\"trim\"]，minutes 30",
    "- 「今天有點累」→ [\"easier\"]",
    "- 「昨天睡得很好，想拼一下」→ [\"harder\"]",
    "- 「請幫我根據這個課表目標增加動作」→ [\"harder\"]",
    "- 「再加兩組」→ [\"harder\"]",
    "- 「臥推架被占走了，其他的加重一點」→ [\"swap\",\"harder\"]",
    "- 「有點累，而且只剩 20 分鐘」→ [\"easier\",\"trim\"]，minutes 20",
    "- 「我想多練上胸」→ []（改變訓練部位，不是這四個方向）",
    "- 「今天這個太難」→ []（可能想降強度，也可能想換動作）",
    "- 「早安」→ []",
    "",
    "**規則（很重要）**：",
    "1. 只列出他的話**明確指向**的方向；不確定的那個就不要列。",
    "2. 指向以上四者以外的事情（例如改變訓練部位、改變動作順序），",
    "   那一部分不列；全部都不明確就回空陣列。",
    "3. 同時要降又要升是矛盾的，回空陣列。",
    "4. minutes 是他**明講**還剩幾分鐘（「半小時」＝30、「一小時」＝60）；",
    "   沒講就是 null，不要自己估。",
    "",
    "只輸出 JSON：{\"intents\": [\"harder\"], \"minutes\": null}。",
    "",
    `使用者的回答：${say}`,
  ].join("\n");
}

/** 分類結果。`intents` 為空代表判不出來。 */
export interface Classified {
  intents: Intent[];
  minutes: number | null;
}

/** 模型回什麼都不信：只認四個值、去重、擋掉矛盾、分鐘限在 1–600。 */
export function parseClassified(raw: unknown): Classified {
  const none: Classified = {intents: [], minutes: null};
  if (!raw || typeof raw !== "object") return none;
  const r = raw as {intents?: unknown; intent?: unknown; minutes?: unknown};
  // 舊格式（單一 intent）也收 —— 模型偶爾不照新格式回。
  const list = Array.isArray(r.intents) ? r.intents : [r.intent];
  const intents: Intent[] = [];
  for (const v of list) {
    if (typeof v === "string" && INTENTS.includes(v) &&
        !intents.includes(v as Intent)) {
      intents.push(v as Intent);
    }
  }
  const m = r.minutes;
  const minutes = typeof m === "number" && m >= 1 && m <= 600 ?
    Math.round(m) :
    null;
  if (intents.includes("easier") && intents.includes("harder")) {
    return {intents: [], minutes};
  }
  return {intents, minutes};
}

/** 舊介面：只取第一個方向。 */
export function parseIntent(raw: unknown): Intent | null {
  return parseClassified(raw).intents[0] ?? null;
}

export async function askIntent(
  say: string,
  apiKey: string,
): Promise<Classified> {
  // **走共用的 `callGemini`。**
  //
  // 第一版這裡自己 fetch，於是少了 `adjust.ts` 那個「404 時照錯誤訊息
  // 改模型重試」的機制 —— 而那是前一輪花了一整個下午才查出來的
  // （模型退役，症狀與金鑰壞掉一模一樣）。同一個決定寫在三個地方，
  // 只有一處是對的。
  //
  // **單次 5 秒**：使用者在場等著，而 `callGemini` 最多試三次
  // （忙線時退避 400ms、1200ms）。5 × 3 ＋ 1.6 ≈ 17 秒，
  // 放得進前端的 20 秒預算。單次拉長的話，一次忙線就會直接吃掉整個預算。
  const text = await callGemini(buildPrompt(say), apiKey, {timeoutMs: 5000});
  try {
    return parseClassified(JSON.parse(text));
  } catch {
    return {intents: [], minutes: null};
  }
}
