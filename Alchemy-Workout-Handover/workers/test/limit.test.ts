/**
 * 每人每日的 Gemini 呼叫上限。
 *
 * 這一層存在的理由寫在 `src/limit.ts`：App 的 AI 點數**擋不住呼叫**，
 * 因為點數在成功產出建議時才扣，而 Gemini 早就被呼叫過了。
 */
import {test} from "node:test";
import assert from "node:assert/strict";
import {consume, usageDay, usageKey, limitMessage, DAILY_LIMIT}
  from "../src/limit.ts";

/** 記憶體版的 KV，只實作用得到的兩個方法。 */
function fakeKv(seed: Record<string, string> = {}) {
  const map = new Map(Object.entries(seed));
  return {
    store: map,
    get: async (k: string) => map.get(k) ?? null,
    put: async (k: string, v: string) => { map.set(k, v); },
  } as unknown as KVNamespace;
}

const at = (iso: string) => new Date(iso);

test("換日時點是台北時間凌晨 4 點", () => {
  // 台北 03:59 ＝ UTC 前一天 19:59，仍算前一天。
  assert.equal(usageDay(at("2026-09-28T19:59:00Z")), "2026-09-28");
  // 台北 04:00 ＝ UTC 20:00，換日。
  assert.equal(usageDay(at("2026-09-28T20:00:00Z")), "2026-09-29");
});

test("同一天的呼叫累加，跨日歸零", async () => {
  const kv = fakeKv();
  const day1 = at("2026-09-28T10:00:00Z");
  assert.equal((await consume(kv, "u1", day1)).used, 1);
  assert.equal((await consume(kv, "u1", day1)).used, 2);
  const day2 = at("2026-09-29T10:00:00Z");
  assert.equal((await consume(kv, "u1", day2)).used, 1, "跨日要重新算");
});

test("不同人各算各的", async () => {
  const kv = fakeKv();
  const now = at("2026-09-28T10:00:00Z");
  await consume(kv, "u1", now);
  await consume(kv, "u1", now);
  assert.equal((await consume(kv, "u2", now)).used, 1);
});

test("到達上限才擋，第 N 次仍放行", async () => {
  const kv = fakeKv();
  const now = at("2026-09-28T10:00:00Z");
  for (let i = 1; i < 3; i++) {
    const v = await consume(kv, "u1", now, 3);
    assert.equal(v.allowed, true, `第 ${i} 次該放行`);
  }
  const third = await consume(kv, "u1", now, 3);
  assert.equal(third.allowed, true, "第 3 次是上限本身，仍放行");
  assert.equal(third.remaining, 0);
  const fourth = await consume(kv, "u1", now, 3);
  assert.equal(fourth.allowed, false, "第 4 次才擋");
});

test("先加再判 —— 被擋下的那一次也算進去", async () => {
  const kv = fakeKv();
  const now = at("2026-09-28T10:00:00Z");
  await consume(kv, "u1", now, 1);
  const blocked = await consume(kv, "u1", now, 1);
  assert.equal(blocked.allowed, false);
  assert.equal(blocked.used, 2, "擋下來的那次也計數，不給重試的空間");
});

test("沒有 KV 綁定時一律放行 —— 這是成本防護，不是安全邊界", async () => {
  const v = await consume(undefined, "u1", at("2026-09-28T10:00:00Z"));
  assert.equal(v.allowed, true);
});

test("KV 讀壞了也放行，不讓計數器壞掉害所有人用不了", async () => {
  const broken = {
    get: async () => { throw new Error("KV down"); },
    put: async () => {},
  } as unknown as KVNamespace;
  const v = await consume(broken, "u1", at("2026-09-28T10:00:00Z"));
  assert.equal(v.allowed, true);
});

test("壞掉的計數值當成 0，不當成無限大", async () => {
  const now = at("2026-09-28T10:00:00Z");
  const kv = fakeKv({[usageKey("u1", usageDay(now))]: "不是數字"});
  assert.equal((await consume(kv, "u1", now)).used, 1);
});

test("擋下來時要講得出什麼時候恢復", () => {
  const msg = limitMessage(DAILY_LIMIT);
  assert.ok(msg.includes("4 點"), "要說幾點重置");
  assert.ok(msg.includes(String(DAILY_LIMIT)), "要說上限是多少");
  assert.ok(msg.includes("直接挑"), "要給他一條還走得通的路");
});
