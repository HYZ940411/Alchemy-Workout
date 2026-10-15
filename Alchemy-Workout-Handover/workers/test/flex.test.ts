/**
 * AI 調整更有彈性（2026-10-04 使用者裁決）—— Worker 這一側。
 *
 * 使用者在訓練中說「請幫我根據這個課表目標增加動作（增加整體強度）」，
 * 分類器一看到「增加動作」就整句判不出來。現在：
 *   - 一句話可以有多個方向；加動作／加組就是加強度
 *   - 分類順便讀出他講的分鐘數
 *   - 新動作只能從 App 給的候選挑，組數要對上安排
 */
import {test} from "node:test";
import assert from "node:assert/strict";

import {parseClassified, parseIntent} from "../src/classify.ts";
import {buildPrompt, clampAdded, ruleFallback} from "../src/adjust.ts";

test("分類：多個方向照收、去重", () => {
  const r = parseClassified({intents: ["easier", "trim", "trim"], minutes: 20});
  assert.deepEqual(r, {intents: ["easier", "trim"], minutes: 20});
});

test("分類：同時要降又要升是矛盾 → 判不出來", () => {
  assert.deepEqual(parseClassified({intents: ["easier", "harder"]}).intents, []);
});

test("分類：四個以外的值與離譜的分鐘數一律不收", () => {
  const r = parseClassified({intents: ["fly", "harder"], minutes: 9999});
  assert.deepEqual(r, {intents: ["harder"], minutes: null});
});

test("分類：舊格式（單一 intent）也收", () => {
  assert.equal(parseIntent({intent: "swap"}), "swap");
});

test("分類 prompt：加動作算加強度，而且要讀時間", () => {
  const p = buildPromptClassify("請幫我增加動作");
  assert.ok(p.includes("加動作、加組、加量都是 harder"));
  assert.ok(p.includes("minutes"));
});

import {buildPrompt as buildPromptClassify} from "../src/classify.ts";

const plan = [
  {name: "臥推", sets: [{weight: 60, reps: 8}, {weight: 60, reps: 8}]},
  {name: "伏地挺身", sets: [{weight: 0, reps: 10}]},
];

test("調整 prompt：組數安排是指令，寫得出每個動作從幾組變幾組", () => {
  const p = buildPrompt(plan, "harder", undefined, undefined, {
    volume: {minutes: 30, add: {"0": 1}, newSets: 0},
  });
  assert.ok(p.includes("組數必須照下列安排"));
  assert.ok(p.includes("臥推）：2 組 → 3 組"));
});

test("調整 prompt：要加新動作時給候選、要求物件格式", () => {
  const p = buildPrompt(plan, "harder", undefined, undefined, {
    volume: {minutes: 60, newSets: 3},
    addCandidates: ["啞鈴飛鳥"],
  });
  assert.ok(p.includes("啞鈴飛鳥"));
  assert.ok(p.includes("\"added\""));
});

test("調整 prompt：多個方向都寫進去", () => {
  const p = buildPrompt(plan, "easier", undefined, undefined, {
    intents: ["easier", "trim"],
  });
  assert.ok(p.includes("降低強度") && p.includes("減少訓練量"));
});

test("新動作：候選以外的不收", () => {
  const got = clampAdded(
    [{name: "憑空發明", after: [{weight: 10, reps: 10}]}], ["啞鈴飛鳥"], 1);
  assert.deepEqual(got, []);
});

test("新動作：組數對不上安排不收", () => {
  const got = clampAdded(
    [{name: "啞鈴飛鳥", after: [{weight: 10, reps: 10}]}], ["啞鈴飛鳥"], 3);
  assert.deepEqual(got, []);
});

test("新動作：重量超過體重三倍不收", () => {
  const got = clampAdded(
    [{name: "啞鈴飛鳥", after: [{weight: 500, reps: 10}]}], ["啞鈴飛鳥"], 1, 70);
  assert.deepEqual(got, []);
});

test("新動作：合格的收一個", () => {
  const got = clampAdded(
    [{name: "啞鈴飛鳥", after: [{weight: 11, reps: 12}], reason: "補量"}],
    ["啞鈴飛鳥"], 1);
  assert.deepEqual(got, [{name: "啞鈴飛鳥", after: [{weight: 10, reps: 12}], reason: "補量"}]);
});

test("規則：自體重動作降強度要減次數、加強度要加次數", () => {
  const bw = [{name: "伏地挺身", sets: [{weight: 0, reps: 10}]}];
  assert.ok(ruleFallback(bw, "easier")[0].after[0].reps < 10);
  assert.ok(ruleFallback(bw, "harder")[0].after[0].reps > 10);
});
