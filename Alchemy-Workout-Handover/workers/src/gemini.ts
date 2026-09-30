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

/**
 * 把 429 回應裡**真正有用的那兩個欄位挑到最前面**。
 *
 * Gemini 的 429 長這樣：
 * ```
 * { "error": { "code": 429, "message": "You exceeded your current quota…",
 *   "details": [
 *     { "@type": "…QuotaFailure", "violations": [
 *         { "quotaId": "GenerateRequestsPerDayPerProjectPerModel-FreeTier" } ] },
 *     { "@type": "…RetryInfo", "retryDelay": "27s" } ] } }
 * ```
 *
 * **`quotaId` 是「每分鐘還是每日」的唯一線索**，而它排在那段很長的
 * message 後面 —— 呼叫端把訊息截在 300 字，正好把它切掉。
 * 使用者問「到底是不是額度用完了」，而我們答不出是哪一種。
 *
 * 挑到最前面，截斷就切不到它。
 */
function quotaHint(body: string): string {
  if (!body.includes("429")) return "";
  try {
    const j = JSON.parse(body) as {
      error?: { details?: Array<Record<string, unknown>> };
    };
    const bits: string[] = [];
    for (const d of j.error?.details ?? []) {
      const vs = d.violations as Array<{ quotaId?: string }> | undefined;
      for (const v of vs ?? []) {
        if (v.quotaId) bits.push(v.quotaId);
      }
      if (typeof d.retryDelay === "string") bits.push(`retry ${d.retryDelay}`);
    }
    return bits.length > 0 ? `[${bits.join(" / ")}] ` : "";
  } catch {
    return "";
  }
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
    throw new Error(
      `gemini ${model} ${res.status}: ${quotaHint(body)}${body.slice(0, 300)}`,
    );
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
/**
 * 暫時性的失敗 —— **重試就可能好**。
 *
 * 2026-09-27 使用者實測拿到的是：
 *   `gemini-3.6-flash 503: "This model is currently experiencing high
 *    demand. Spikes in demand are usually temporary."`
 *
 * 那是 Google 那側的忙線，不是設定錯。而在此之前 [callGemini] **只對
 * 404 重試** —— 一次 503 就整個放棄，使用者看到的是「被擋」。
 *
 * **429 不在這裡面**，見 [isQuota]。
 * 4xx 的其餘（400 參數錯、401/403 金鑰問題）重試一百次也一樣，不收。
 */
const TRANSIENT = [500, 502, 503, 504];

const isTransient = (msg: string) =>
  TRANSIENT.some((code) => msg.includes(` ${code}:`));

/**
 * 額度用完 —— **重試只是再燒一次額度**。
 *
 * 第一版把 429 當成暫時性失敗，退避 400ms／1200ms 各試一次。
 * 那個假設只對「每分鐘上限」成立，而免費層還有**每日上限**；
 * 更重要的是，使用者實測拿到的訊息是
 * 「You exceeded your current quota, please check your plan and
 *   billing details」—— 那不是等一秒就會過的東西。
 *
 * 處置：**換一個模型試一次**（免費層的額度多半是逐模型計的），
 * 不成就放棄，並讓錯誤訊息說得出是額度問題 ——
 * 它與「忙線」對使用者的意義完全不同：忙線等一下再試就好，
 * 額度用完是今天不必再試了。
 */
const isQuota = (msg: string) => msg.includes(" 429:");

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

/**
 * 呼叫 Gemini，回傳它輸出的那段文字（呼叫端自己 parse）。
 *
 * [timeoutMs] 是**單次嘗試**的上限，由呼叫端決定 ——
 * 使用者在場等著的（意圖分類）與不在場的（品質評分）差很多。
 * 最多重試兩次，所以呼叫端的總預算要抓 `timeoutMs × 3 ＋ 約 2 秒`。
 */
export async function callGemini(
  prompt: string,
  apiKey: string,
  {temperature = 0, timeoutMs = 15000}: {
    temperature?: number; timeoutMs?: number;
  } = {},
): Promise<string> {
  let model = currentModel();
  // 退避：第一次等 400ms，第二次 1200ms。忙線多半是短暫的尖峰，
  // 但使用者在等 —— 不能等太久。
  const backoff = [400, 1200];
  // 額度用完時只換一次模型 —— 一路換下去會把每個模型的額度都燒掉。
  let switchedForQuota = false;
  let last: unknown;

  for (let attempt = 0; attempt <= backoff.length; attempt++) {
    try {
      const out = await once(model, prompt, apiKey, temperature, timeoutMs);
      resolved = model; // 這個能用，記起來
      return out;
    } catch (e) {
      last = e;
      const msg = e instanceof Error ? e.message : String(e);

      // 一、模型不對 —— 換一個，不必等。
      if (msg.includes("404")) {
        // 錯誤訊息裡直接講了該用哪一個，那是最權威的答案；
        // 沒講的話才去問清單。
        const next = suggestedModel(msg) ?? await discoverModel(apiKey);
        if (next === model) throw e; // 換了跟沒換一樣，不要無限重試
        model = next;
        continue;
      }

      // 二、額度用完 —— 換一個模型試一次，不退避（等一秒不會變出額度）。
      if (isQuota(msg) && !switchedForQuota) {
        switchedForQuota = true;
        const next = await discoverModel(apiKey).catch(() => model);
        if (next === model) throw e;
        model = next;
        continue;
      }

      // 三、暫時性的 —— 等一下再試同一個模型。
      if (isTransient(msg) && attempt < backoff.length) {
        await sleep(backoff[attempt]);
        continue;
      }

      // 四、其餘（參數錯、金鑰問題）重試一百次也一樣。
      throw e;
    }
  }
  throw last;
}
