/**
 * 唯一一支 Gemini 呼叫器。
 *
 * ## 為什麼要有這一支
 *
 * 2026-09-27 我為了意圖分類寫了第三支呼叫 Gemini 的程式（`classify.ts`），
 * 而它**沒有** `adjust.ts` 那個「404 時照錯誤訊息改模型重試」的機制 ——
 * 那是前一輪花了一整個下午才查出來的（模型退役，症狀與金鑰壞掉一模一樣）。
 *
 * 同一個決定寫在三個地方，只有一處是對的。這一支把它收成一份。
 *
 * ## 為什麼熱路徑上不打 `listModels`
 *
 * 原本每次呼叫都先問「有哪些模型可用」。那是一趟額外的往返（逾時 10 秒），
 * 加上 generateContent 本身，冷啟動時會超過前端等待的上限 ——
 * 使用者回報「分析時間非常久，得不到答案」。
 *
 * 改成**先直接用偏好的模型**，只有在它 404 時才去探測。
 * 正常情況下一趟就結束；模型退役那一天才會多花兩趟，而那是一次性的
 * （挑到的結果會留在這個 isolate 的記憶體裡）。
 */

const API = "https://generativelanguage.googleapis.com/v1beta";

const PREFERRED = "gemini-3.6-flash";

/**
 * 這個 isolate 目前用哪一個模型。
 *
 * Worker 的 isolate 會被回收，所以它不是持久快取 ——
 * 只是「同一個 isolate 內不重複探測」。
 */
let resolved: string | null = null;

/** 給 `screen.ts` 那種需要先知道模型名稱的呼叫端。 */
export function currentModel(): string {
  return resolved ?? PREFERRED;
}

/**
 * Google 在 404 訊息裡會直接說該改用哪一個：
 *   「This model models/X is no longer available to new users.
 *     Please update your code to use models/Y」
 *
 * **把 Y 挖出來直接重試。** `listModels` 回報的可用清單與這把金鑰
 * 實際能呼叫的並不一致（清單有 2.5-flash，呼叫卻說新使用者不能用），
 * 所以光靠挑清單不夠 —— 真正權威的答案在錯誤訊息裡。
 */
function suggestedModel(body: string): string | null {
  const m = body.match(/use\s+models\/([\w.-]+)/);
  return m ? m[1] : null;
}

/** 問 API 有哪些模型可用，挑一個。**只在偏好的那個 404 之後才走。** */
export async function discoverModel(apiKey: string): Promise<string> {
  const res = await fetch(`${API}/models`, {
    headers: {"x-goog-api-key": apiKey},
    signal: AbortSignal.timeout(8000),
  });
  if (!res.ok) {
    const body = await res.text().catch(() => "");
    throw new Error(`listModels ${res.status}: ${body.slice(0, 200)}`);
  }
  const data = await res.json() as {
    models?: { name?: string; supportedGenerationMethods?: string[] }[];
  };
  const all = (data.models ?? [])
    .filter((m) =>
      (m.supportedGenerationMethods ?? []).includes("generateContent"))
    .map((m) => (m.name ?? "").replace(/^models\//, ""))
    .filter((n) => n.length > 0);

  // **先濾掉不能拿來做這件事的。** 清單裡混著 TTS、圖像、實驗版與
  // 其他家族（gemma）—— 挑到 `gemini-2.5-flash-preview-tts` 的話
  // 每次呼叫都會失敗，而症狀跟「金鑰壞了」一模一樣。
  const usable = all.filter((n) =>
    n.startsWith("gemini-") &&
    !n.includes("tts") &&
    !n.includes("image") &&
    !n.includes("audio") &&
    !n.includes("vision") &&
    !n.includes("embedding") &&
    !n.includes("preview") &&
    !n.includes("exp"));

  const pick = usable.find((n) => n === PREFERRED) ??
    usable.find((n) => n.includes("flash")) ??
    usable[0] ??
    all[0];
  if (!pick) throw new Error("listModels: 沒有任何支援 generateContent 的模型");
  return pick;
}

async function once(
  model: string,
  prompt: string,
  apiKey: string,
  temperature: number,
  timeoutMs: number,
): Promise<string> {
  const res = await fetch(
    `${API}/models/${model}:generateContent`,
    {
      method: "POST",
      headers: {"Content-Type": "application/json", "x-goog-api-key": apiKey},
      body: JSON.stringify({
        contents: [{parts: [{text: prompt}]}],
        generationConfig: {temperature, responseMimeType: "application/json"},
      }),
      signal: AbortSignal.timeout(timeoutMs),
    },
  );
  if (!res.ok) {
    // **把回應內容一起丟出去。** 只給狀態碼的話看到的是「gemini 404」——
    // 那可能是模型名稱過期、金鑰沒權限、或配額用盡，三者的處置完全不同。
    const body = await res.text().catch(() => "");
    throw new Error(`gemini ${model} ${res.status}: ${body.slice(0, 300)}`);
  }
  const data = await res.json() as {
    candidates?: { content?: { parts?: { text?: string }[] } }[];
  };
  return data.candidates?.[0]?.content?.parts?.[0]?.text ?? "";
}

/**
 * 呼叫 Gemini，回傳它輸出的那段文字（呼叫端自己 parse）。
 *
 * [timeoutMs] 由呼叫端決定 —— 使用者在場等著的（意圖分類）與
 * 不在場的（品質評分）可以等的時間差很多。
 */
export async function callGemini(
  prompt: string,
  apiKey: string,
  {temperature = 0, timeoutMs = 15000}: {
    temperature?: number; timeoutMs?: number;
  } = {},
): Promise<string> {
  const first = currentModel();
  try {
    const out = await once(first, prompt, apiKey, temperature, timeoutMs);
    resolved = first; // 這個能用，記起來
    return out;
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    if (!msg.includes("404")) throw e; // 不是「換個模型就能好」，照常往上丟

    // 一、錯誤訊息裡直接講了該用哪一個 —— 那是最權威的答案。
    let next = suggestedModel(msg);
    // 二、沒講的話才去問清單。
    next ??= await discoverModel(apiKey);
    if (next === first) throw e; // 換了跟沒換一樣，不要無限重試

    const out = await once(next, prompt, apiKey, temperature, timeoutMs);
    resolved = next;
    return out;
  }
}
