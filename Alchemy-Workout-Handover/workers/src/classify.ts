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

import {callGemini} from "./gemini";

export type Intent = "easier" | "harder" | "trim" | "swap";

const INTENTS: readonly string[] = ["easier", "harder", "trim", "swap"];

export const isSay = (v: unknown): v is string =>
  typeof v === "string" && v.trim().length > 0 && v.length <= 200;

export function buildPrompt(say: string): string {
  return [
    "你是健身 App 的意圖分類器。使用者被問「這份課表要怎麼調？」，",
    "他的回答如下。請判斷他想往哪一個方向調。",
    "",
    "四個方向：",
    "- easier：整體降強度（太重、吃力、狀況不好、想保守一點）",
    "- harder：整體升強度（太輕、想加重、狀態很好、想挑戰）",
    "- trim：減少組數（時間不夠、想早點結束、想少做幾組）",
    "- swap：替換做不了的動作（沒有某項器材、器材壞了或被占用、",
    "  這個動作做不了）",
    "",
    "**規則（很重要）**：",
    "1. 只在他的話**明確指向唯一一個方向**時才回答那個方向。",
    "2. 同時指向兩個方向、或指向以上四者以外的事情（例如「想多練上胸」",
    "   「想換成練背」這種改變訓練部位的要求），一律回 null。",
    "3. 寧可回 null 讓系統再問一次，也不要猜 —— 猜錯方向會讓他照著",
    "   一份他沒要求的課表去練。",
    "",
    "只輸出 JSON：{\"intent\": \"easier\"} 或 {\"intent\": null}。",
    "",
    `使用者的回答：${say}`,
  ].join("\n");
}

/** 模型回什麼都不信，只認四個值之一，其餘一律 null。 */
export function parseIntent(raw: unknown): Intent | null {
  if (!raw || typeof raw !== "object") return null;
  const v = (raw as {intent?: unknown}).intent;
  return typeof v === "string" && INTENTS.includes(v) ? v as Intent : null;
}

export async function askIntent(
  say: string,
  apiKey: string,
): Promise<Intent | null> {
  // **走共用的 `callGemini`。**
  //
  // 第一版這裡自己 fetch，於是少了 `adjust.ts` 那個「404 時照錯誤訊息
  // 改模型重試」的機制 —— 而那是前一輪花了一整個下午才查出來的
  // （模型退役，症狀與金鑰壞掉一模一樣）。同一個決定寫在三個地方，
  // 只有一處是對的。
  //
  // **逾時 12 秒**：使用者在場等著。前端等 20 秒，留 8 秒給
  // Worker 自己的往返與可能的一次重試。
  const text = await callGemini(buildPrompt(say), apiKey, {timeoutMs: 12000});
  try {
    return parseIntent(JSON.parse(text));
  } catch {
    return null;
  }
}
