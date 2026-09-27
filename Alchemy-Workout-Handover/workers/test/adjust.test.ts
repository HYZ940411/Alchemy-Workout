/**
 * `clamp()` —— 模型與使用者身體之間唯一的那道關卡。
 *
 * 在此之前這支 Worker **一個測試都沒有**，而這個函式的工作是
 * 「模型算錯一個數字，使用者照著做會受傷」的最後防線。
 *
 * 2026-09-27 使用者第一次真的測到「替換動作」（在那之前模型一直失敗，
 * 每次都靜默退回規則，而規則根本不換動作），截圖四項全過 —— 但那是
 * 運氣：換過去的重量剛好都落在原重量的 ±50% 內。
 */
import {test} from "node:test";
import assert from "node:assert/strict";
import {clamp, fill, type PlanExercise} from "../src/adjust.ts";

const bench: PlanExercise = {
  name: "板凳臥推・槓鈴",
  sets: [{weight: 60, reps: 8}],
};
const pushup: PlanExercise = {
  name: "伏地挺身",
  sets: [{weight: 0, reps: 15}],
};

const ctx = {
  bodyweightKg: 70,
  candidates: {
    "板凳臥推・槓鈴": ["伏地挺身", "板凳臥推・啞鈴"],
    "伏地挺身": ["板凳臥推・啞鈴"],
  },
};

const one = (over: Record<string, unknown>) => [{
  index: 0,
  name: bench.name,
  after: [{weight: 60, reps: 8}],
  ...over,
}];

test("沒有替換時，重量不得偏離原值 ±50%", () => {
  assert.equal(clamp([bench], one({after: [{weight: 100, reps: 8}]}), ctx).length, 0);
  assert.equal(clamp([bench], one({after: [{weight: 20, reps: 8}]}), ctx).length, 0);
  assert.equal(clamp([bench], one({after: [{weight: 50, reps: 8}]}), ctx).length, 1);
});

test("替換成徒手動作 —— 重量 0 不該被丟掉", () => {
  const out = clamp([bench], one({
    replacement: "伏地挺身",
    after: [{weight: 0, reps: 15}],
  }), ctx);
  assert.equal(out.length, 1, "使用者說沒有槓鈴，換成徒手是正解，不能整筆丟掉");
  assert.equal(out[0].replacement, "伏地挺身");
  assert.equal(out[0].after[0].weight, 0);
});

test("徒手動作替換成有重量的 —— 也不該被丟掉", () => {
  const out = clamp([pushup], [{
    index: 0,
    name: pushup.name,
    replacement: "板凳臥推・啞鈴",
    after: [{weight: 20, reps: 10}],
  }], ctx);
  assert.equal(out.length, 1);
  assert.equal(out[0].after[0].weight, 20);
});

test("替換後的重量仍有上界 —— 體重三倍", () => {
  const ok = clamp([bench], one({
    replacement: "板凳臥推・啞鈴",
    after: [{weight: 200, reps: 5}],
  }), ctx);
  assert.equal(ok.length, 1, "200 公斤在 70 公斤體重的三倍之內");

  const no = clamp([bench], one({
    replacement: "板凳臥推・啞鈴",
    after: [{weight: 400, reps: 5}],
  }), ctx);
  assert.equal(no.length, 0, "體重三倍以上是世界紀錄等級，必然是模型算錯");
});

test("沒有體重資料時退回絕對上限 300 公斤", () => {
  const c = {candidates: ctx.candidates};
  assert.equal(clamp([bench], one({
    replacement: "板凳臥推・啞鈴",
    after: [{weight: 250, reps: 5}],
  }), c).length, 1);
  assert.equal(clamp([bench], one({
    replacement: "板凳臥推・啞鈴",
    after: [{weight: 350, reps: 5}],
  }), c).length, 0);
});

test("替換成候選清單以外的動作 —— 整筆丟棄", () => {
  const out = clamp([bench], one({
    replacement: "臥推機",
    after: [{weight: 0, reps: 15}],
  }), ctx);
  assert.equal(out.length, 0, "模型可能憑空發明一個不存在的動作");
});

test("次數與負重的基本界線不因替換而放寬", () => {
  const swap = {replacement: "伏地挺身"};
  assert.equal(clamp([bench], one({...swap, after: [{weight: 0, reps: 99}]}), ctx).length, 0);
  assert.equal(clamp([bench], one({...swap, after: [{weight: 0, reps: 0}]}), ctx).length, 0);
  assert.equal(clamp([bench], one({...swap, after: [{weight: -5, reps: 8}]}), ctx).length, 0);
});

test("被丟掉的那幾項補成「維持原樣」，不是整列消失", () => {
  const plan = [bench, pushup];
  const out = fill(plan, clamp(plan, [
    {index: 0, name: bench.name, after: [{weight: 999, reps: 8}]}, // 會被丟掉
    {index: 1, name: pushup.name, after: [{weight: 0, reps: 20}]},
  ], ctx));
  assert.equal(out.length, 2, "四個動作的課表不該回來只剩三列");
  assert.deepEqual(out[0].after, bench.sets, "被丟掉的維持原設定");
  assert.equal(out[1].after[0].reps, 20);
});
