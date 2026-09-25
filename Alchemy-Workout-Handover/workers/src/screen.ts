/**
 * 教官申請的 AI 訓練品質評分（`[BE-13]` 周邊，2026-09-25）。
 *
 * ## 這裡只產出分數，不做判定
 *
 * 規格明文：「AI 僅產出評分與疑慮標記，**不直接裁決**；初審的通過與否
 * 由系統依門檻判定」（`教官申請流程.md`）。所以加權平均、通過門檻 60、
 * 折抵門檻 80、紀錄合理性一票否決 40 —— **全部留在 App 的 Dart 裡**。
 *
 * ## 這裡沒有 ruleFallback
 *
 * `adjust.ts` 在 Worker 裡另寫了一份規則當退路，而 Dart 那邊已經有一份
 * —— `PROGRESS.md` 記著那是違反「同一個決定只寫一個地方」的已知問題。
 *
 * 這支**刻意不重蹈覆轍**：失敗就回非 200，由 App 退回它自己那份
 * `scoreTrainingQuality()`。規則只有一份，在 Dart 裡，有測試釘著。
 */

const API = "https://generativelanguage.googleapis.com/v1beta";

/** 一場訓練的摘要。與 Dart 的 `SessionSummary` 對應。 */
export interface Session {
  date: string;
  sets: number;
  minutes: number;
  /** 攤平的 [重量, 次數]。 */
  reps: [number, number][];
}

export interface Quality {
  completion: number;
  consistency: number;
  sanity: number;
  concerns: string[];
}

/** 送進來的東西長得對不對。**外部輸入，先擋再說。** */
export function isSessions(v: unknown): v is Session[] {
  if (!Array.isArray(v) || v.length === 0) return false;
  // 一次申請最多看 200 場 —— 再多對評分沒有幫助，只會把 prompt 撐爆。
  if (v.length > 200) return false;
  return v.every((s) =>
    s && typeof s === "object" &&
    typeof (s as Session).date === "string" &&
    typeof (s as Session).sets === "number" &&
    typeof (s as Session).minutes === "number" &&
    Array.isArray((s as Session).reps));
}

/**
 * 驗模型回來的東西。**任何一項不合格就回 null。**
 *
 * 不「盡量用」——三維缺一個、或分數超出範圍的東西，
 * 拿去決定誰能當教官比沒有更糟。
 */
export function clampQuality(raw: unknown): Quality | null {
  if (!raw || typeof raw !== "object") return null;
  const o = raw as Record<string, unknown>;

  const num = (v: unknown): number | null => {
    if (typeof v !== "number" || !Number.isFinite(v)) return null;
    const n = Math.round(v);
    return n >= 0 && n <= 100 ? n : null;
  };

  const completion = num(o.completion);
  const consistency = num(o.consistency);
  const sanity = num(o.sanity);
  if (completion === null || consistency === null || sanity === null) {
    return null;
  }

  const concerns = Array.isArray(o.concerns) ?
    o.concerns
      .filter((c): c is string => typeof c === "string" && c.trim() !== "")
      // 疑慮標記會畫在管理員的待審佇列上，限長免得一則塞爆整頁。
      .map((c) => c.trim().slice(0, 60))
      .slice(0, 6) :
    [];

  return {completion, consistency, sanity, concerns};
}

function buildPrompt(sessions: Session[]): string {
  return [
    "你是健身平台的訓練品質評分系統。以下是一位教官申請者的訓練紀錄。",
    "請就三個維度各給 0–100 分，並列出疑慮項目。",
    "",
    "維度一「訓練完成率」——抓偷懶：每場的組數是否足夠、是否常常草草結束。",
    "維度二「訓練規律性」——抓是否長期在練：每週訓練次數的穩定度、",
    "訓練間隔的離散程度。集中衝量幾天後消失數月的，這一維應該低。",
    "維度三「紀錄合理性」——抓造假：每組耗時是否過短（一組含休息",
    "少於 30 秒不合理）、重量是否超出人體合理範圍或突然暴增、",
    "多次訓練的數字是否完全雷同（照抄預帶值的樣子）。",
    "",
    "**只評分，不要下「通過」或「不通過」的結論** ——那由系統依門檻判定。",
    "疑慮項目用繁體中文，每則 60 字以內，最多 6 則；沒有就給空陣列。",
    "",
    "只輸出 JSON：",
    '{"completion":0-100,"consistency":0-100,"sanity":0-100,"concerns":["…"]}',
    "",
    "訓練紀錄（date=日期, sets=總組數, minutes=時長, reps=[[重量,次數],…]）：",
    JSON.stringify(sessions),
  ].join("\n");
}

/**
 * 問 Gemini。失敗往上拋 —— 呼叫端回非 200，由 App 退回規則計算。
 *
 * [model] 由呼叫端傳入，沿用 `adjust.ts` 已經挑好的那一個，
 * 不重複做一次模型探測。
 */
export async function askQuality(
  sessions: Session[],
  apiKey: string,
  model: string,
): Promise<Quality> {
  const res = await fetch(
    `${API}/models/${model}:generateContent`,
    {
      method: "POST",
      headers: {"Content-Type": "application/json", "x-goog-api-key": apiKey},
      body: JSON.stringify({
        contents: [{parts: [{text: buildPrompt(sessions)}]}],
        generationConfig: {
          // 這個分數決定誰能當教官 —— 溫度壓到最低，同一份紀錄
          // 每次跑出來的結果要盡量一致。
          temperature: 0,
          responseMimeType: "application/json",
        },
      }),
      // 使用者按完申請就離開了（規格：本路徑使用者不在場），
      // 可以等久一點，但不能永遠等。
      signal: AbortSignal.timeout(25000),
    },
  );

  if (!res.ok) {
    const body = await res.text().catch(() => "");
    throw new Error(`gemini ${model} ${res.status}: ${body.slice(0, 300)}`);
  }

  const data = await res.json() as {
    candidates?: { content?: { parts?: { text?: string }[] } }[];
  };
  const text = data.candidates?.[0]?.content?.parts?.[0]?.text ?? "";
  const q = clampQuality(JSON.parse(text));
  if (!q) throw new Error("模型回傳的評分沒有通過驗證");
  return q;
}
