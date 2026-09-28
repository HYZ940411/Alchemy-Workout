/**
 * 每人每日的 Gemini 呼叫上限（2026-09-28 使用者裁決 A）。
 *
 * ## 為什麼不能靠 App 的 AI 點數擋
 *
 * 點數是在**成功產出建議**時才扣的（`AppState.spendAiCredit`），
 * 而 Gemini 早就被呼叫過了。三條路都會呼叫但不扣點：
 *
 * 1. 意圖判不出來 → 畫面寫「本次未扣點」→ 使用者再打一次 → 又一次呼叫
 * 2. 「沒有可調的空間」→ suggest 已經呼叫過了 → 未扣點
 * 3. 自動優化（會員每三次訓練）→ 本來就不扣點
 *
 * 也就是說**不花任何點數就能無限次呼叫**，而帳單算的是呼叫。
 *
 * ## 為什麼擋在 Worker 而不是 App
 *
 * App 的程式碼會原封不動送到每一位訪客的瀏覽器。擋在那裡等於把鎖
 * 掛在門外側。這裡認的是 Firebase uid（已經驗過的），繞不過。
 */

/** 每人每日的呼叫上限。一次完整調整是兩次呼叫（分類 ＋ 產生建議）。 */
export const DAILY_LIMIT = 30;

/**
 * 這個時間點屬於哪一個「訓練日」。
 *
 * **換日時點為當地 04:00**（`00_全域規範.md`，全專案通用），
 * 而本專案的「當地」是台北（UTC+8）。Worker 跑在 UTC，
 * 所以先 +8 小時再退 4 小時 —— 合併起來就是 +4。
 *
 * 用同一個日界的理由：使用者看到「今天還剩幾次」時，那個「今天」
 * 要跟他在 App 裡其他地方看到的「今天」是同一天。
 * Gemini 自己的配額在太平洋時間午夜重置，與這裡無關 ——
 * 那是上游的事，我們擋的是自己這一側的用量。
 */
export function usageDay(now: Date): string {
  const shifted = new Date(now.getTime() + 4 * 3600 * 1000);
  return shifted.toISOString().slice(0, 10);
}

/** KV 的鍵。uid 已經是驗過的 Firebase uid，不會有奇怪字元。 */
export const usageKey = (uid: string, day: string) => `ai:${uid}:${day}`;

/** [consume] 回傳的結果。 */
export interface UsageVerdict {
  allowed: boolean;
  used: number;
  remaining: number;
}

/**
 * 記一次呼叫，並回報還剩幾次。
 *
 * **先加再判。** 反過來的話兩個同時進來的請求會讀到同一個舊值，
 * 兩個都放行 —— 而這個計數器的用途是擋帳單，寧可嚴一次。
 *
 * KV 沒有原子遞增，所以這個計數在高併發下會少算。**那是可以接受的**：
 * 它防的是「一個人狂按」，不是「一萬個人同時按」，而前者是序列的。
 * 真要精確得用 Durable Object，那是另一個量級的複雜度。
 *
 * **KV 讀不到就放行。** 計數器壞掉不該讓所有人用不了 AI ——
 * 這是成本防護，不是安全邊界（安全邊界是 `verifyIdToken`）。
 */
export async function consume(
  kv: KVNamespace | undefined,
  uid: string,
  now: Date,
  limit: number = DAILY_LIMIT,
): Promise<UsageVerdict> {
  if (!kv) return {allowed: true, used: 0, remaining: limit};
  const key = usageKey(uid, usageDay(now));
  let used = 0;
  try {
    const raw = await kv.get(key);
    used = raw ? parseInt(raw, 10) : 0;
    if (!Number.isFinite(used) || used < 0) used = 0;
  } catch {
    return {allowed: true, used: 0, remaining: limit};
  }
  const next = used + 1;
  try {
    // 兩天後過期 —— 日界只往後推 4 小時，48 小時足夠涵蓋，
    // 而過期的鍵不必自己清。
    await kv.put(key, String(next), {expirationTtl: 172800});
  } catch {
    // 寫不進去就算了，見上面「計數器壞掉不該讓所有人用不了」。
  }
  return {
    allowed: next <= limit,
    used: next,
    remaining: Math.max(0, limit - next),
  };
}

/** 超過上限時對使用者講的話。**要講得出什麼時候會恢復。** */
export function limitMessage(limit: number): string {
  return `今天的 AI 使用次數已達上限（每日 ${limit} 次），` +
    "明天凌晨 4 點後重置。你仍然可以直接挑一個調整方向。";
}
