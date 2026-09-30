/**
 * 自動優化的問法：**不給方向，要模型自己判斷**。
 *
 * 2026-09-28 使用者裁決 A。在此之前自動優化接的是訓練前調整的同一條
 * 追問流程 —— 反過來問使用者要調哪個方向，而規格
 *（`01_Command清單.md`〈AI 自動優化訓練流程〉）把「優化訓練強度」的
 * Actor 寫成**系統**，流程裡沒有那一步。
 */
import {test} from "node:test";
import assert from "node:assert/strict";
import {buildAutoPrompt, type PlanExercise} from "../src/adjust.ts";

const plan: PlanExercise[] = [
  {name: "板凳臥推 · 槓鈴", sets: [{weight: 60, reps: 8}]},
];

test("不告訴模型方向 —— 那正是它要判斷的事", () => {
  const p = buildAutoPrompt(plan, {});
  assert.ok(p.includes("請**你自己判斷**"), "要明講由它判斷");
  assert.ok(!p.includes("調整方向："), "不該像 buildPrompt 那樣先給定方向");
});

test("四個方向都列出來，而且只有這四個", () => {
  const p = buildAutoPrompt(plan, {});
  for (const i of ["easier", "harder", "trim", "swap"]) {
    assert.ok(p.includes(i), i);
  }
});

test("有歷來成績時要求引用它", () => {
  const p = buildAutoPrompt(plan, {
    recent: {"板凳臥推 · 槓鈴": [{weight: 60, reps: 6}]},
  });
  assert.ok(p.includes("歷來成績"));
  assert.ok(p.includes("判斷依據"), "要給它判斷升降的準則");
  assert.ok(p.includes('"reps":6') || p.includes("\"reps\":6"),
    "成績本身要送進去");
});

// 沒有成績就看不出該升該降。**寧可不給建議，也不要憑空挑一個方向** ——
// 那是假裝成教練判斷的擲骰子。
test("沒有歷來成績時，明講要回 null", () => {
  const p = buildAutoPrompt(plan, {});
  assert.ok(p.includes("沒有歷來成績"));
  assert.ok(p.includes("不要憑空挑一個方向"));
});

test("課表原文有送進去", () => {
  const p = buildAutoPrompt(plan, {});
  assert.ok(p.includes("板凳臥推 · 槓鈴"));
  assert.ok(p.includes('"weight":60'));
});

test("輸出格式要求 intent 與 changes 一起回", () => {
  const p = buildAutoPrompt(plan, {});
  assert.ok(p.includes('"intent"'));
  assert.ok(p.includes('"changes"'));
  assert.ok(p.includes('"why"'), "要講得出為什麼是這個方向");
});

test("數值的界線與訓練前調整同一套", () => {
  const p = buildAutoPrompt(plan, {});
  assert.ok(p.includes("±50%"));
  assert.ok(p.includes("1 到 50"));
  assert.ok(p.includes("自體重動作維持 0"));
});

// 2026-09-28 使用者實測：一份 16 組的課表只完成 2 組（13%），
// 自動優化卻回「看不出該往哪個方向調」—— 因為送過去的只有每個動作的
// （重量, 次數），模型**完全不知道他做到一半就走了**。
test("最近幾場的完成度要送進去", () => {
  const p = buildAutoPrompt(plan, {
    sessions: [{plan: "無器材-背部", completion: 0.13, minutes: 8}],
  });
  assert.ok(p.includes("0.13"), "完成度本身要在 prompt 裡");
  assert.ok(p.includes("完成度是最重要的訊號"));
  assert.ok(!p.includes("沒有歷來成績"),
    "有完成度就不算「沒有成績」，不該叫它回 null");
});

test("只有完成度、沒有逐動作成績時也算有依據", () => {
  const p = buildAutoPrompt(plan, {
    sessions: [{plan: "無器材-背部", completion: 0.2, minutes: 10}],
  });
  assert.ok(p.includes("判斷依據"));
  assert.ok(!p.includes("歷來成績（舊→新"), "沒有逐動作成績就不要硬擺一個空的");
});

test("完成度低時，easier 與 trim 都是可選的答案", () => {
  const p = buildAutoPrompt(plan, {sessions: [{plan: "x", completion: 0.1, minutes: 5}]});
  assert.ok(p.includes("動作太重就 easier，組數太多就 trim"),
    "做不完可能是太重、也可能是太長，兩條路都要講");
});

test("兩者都沒有才叫它回 null", () => {
  const p = buildAutoPrompt(plan, {});
  assert.ok(p.includes("沒有歷來成績"));
});
