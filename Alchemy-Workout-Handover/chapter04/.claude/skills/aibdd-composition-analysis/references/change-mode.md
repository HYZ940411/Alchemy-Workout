# CHANGE 模式分析流程

當模式為 CHANGE 時，使用者帶入的是「對既有規格的變更描述」而非全新 Idea。分析目標從「拆解 Idea 全貌」轉為「精確識別變更意圖與影響邊界」。

## 輸入

| 參數 | 說明 |
|------|------|
| Change Idea | 使用者的變更描述（raw text、截圖、或口頭說明） |
| 既有規格 | 當前 `${SPECS_ROOT_DIR}` 下的所有 artifact（由 discovery Step 3 負責讀取，此處只做變更意圖拆解） |

## Step 1：變更意圖拆句

逐句掃描使用者的 Change Idea，萃取每一句的**變更意圖類別**（Δ-* 分類）：

### Δ-* 變更意圖類別

| 類別 | 定義 | 範例 |
|------|------|------|
| **Δ-Flow** | 新增、修改、刪除流程步驟或步驟順序 | 「取消訂單後要多一個退款步驟」「把 STEP:3 和 STEP:4 交換」 |
| **Δ-Rule** | 新增、修改、刪除業務規則或分支條件 | 「取消訂單後需要通知用戶」「把折扣上限從 30% 改為 50%」 |
| **Δ-Actor** | 新增、修改、刪除參與者 | 「新增一個助教角色」「原本客服做的，改成系統自動做」 |
| **Δ-Data** | 新增、修改、刪除欄位或資料格式 | 「Lead 要多一個 LINE ID 欄位」「把 phone 改成非必填」 |
| **Δ-Delete** | 明確刪除某個功能或流程 | 「不做付款功能了」「移除批次匯入」 |
| **Δ-Constraint** | 新增、修改、刪除約束條件（含 API / Entity / 非功能） | 「匯入上限從 1000 改為 5000」「API 回應時間要 < 100ms」 |

### 拆句標註規則

每個變更意圖必須標註：

| 欄位 | 說明 |
|------|------|
| **ID** | 唯一識別碼（Δ-Flow-1, Δ-Rule-1, ...） |
| **操作** | `ADD`（新增）/ `MODIFY`（修改）/ `DELETE`（刪除） |
| **原文引用** | 使用者原文中的對應字句 |
| **影響預估** | 初步推測可能影響哪些 artifact 類型（Activity / Feature / API / ERM） |

## Step 2：Change Composition Report

將拆句結果彙整為 Change Composition Report：

```
【Change Composition Report】

━━ 變更摘要 ━━

  變更描述：<一句話總結>
  變更類型：<新增 | 修改 | 刪除 | 混合>

━━ 變更意圖盤點 ━━

■ Δ-Flow（流程變更）：
  - [Δ-Flow-1] ADD: 取消訂單後新增退款步驟（原文：「取消訂單後要能退款」）
    影響預估：Activity（新增 STEP）→ Feature（新增 .feature）→ API（新增 endpoint）→ ERM（可能新增 table）

■ Δ-Rule（規則變更）：
  - [Δ-Rule-1] MODIFY: 取消訂單後需通知用戶（原文：「取消後要寄通知」）
    影響預估：Feature（修改 Rule）→ API（修改 response / 新增 webhook）

■ Δ-Actor（角色變更）：
  （使用者未提及）

■ Δ-Data（資料變更）：
  - [Δ-Data-1] ADD: 退款金額欄位（原文：「要記錄退了多少錢」）
    影響預估：Feature（DataTable 新增欄位）→ ERM（column 新增）→ API（schema 新增）

■ Δ-Delete（刪除）：
  （使用者未提及）

■ Δ-Constraint（約束變更）：
  （使用者未提及）

━━ 跨意圖 ━━

■ AI 推論但未確認的（ASM）：
  - [ASM-1] 退款步驟的 Actor 是原訂單的付款者（推論依據：原文說「取消訂單後」，暗示同一操作者）

■ 完全缺失的（GAP）：
  - [GAP-1] 退款的觸發條件（自動退款？手動退款？）
  - [GAP-2] 部分退款 vs. 全額退款

■ 邊界待定的（BDY）：
  - [BDY-1] 退款失敗時的處理方式
```

## Step 3：變更影響預估矩陣

對每個 Δ-* 意圖，預估其影響深度：

```
■ 變更影響預估矩陣：

| Δ-* ID | 操作 | Activity | Feature | API | ERM | 影響深度 |
|--------|------|----------|---------|-----|-----|---------|
| Δ-Flow-1 | ADD | 新增 STEP | 新增 .feature | 新增 endpoint | 可能新增 table | 深（全鏈路） |
| Δ-Rule-1 | MODIFY | 不影響 | 修改 Rule | 可能修改 | 不影響 | 中（Feature→API） |
| Δ-Data-1 | ADD | 不影響 | 修改 DataTable | 修改 schema | 新增 column | 中（Feature→API→ERM） |

影響深度定義：
  淺 = 只影響單一 artifact 類型
  中 = 影響 2-3 個 artifact 類型
  深 = 影響全鏈路（Activity → Feature → API → ERM）
```

此矩陣回傳 discovery，供 Step 3（Structural Read）聚焦掃描範圍、Step 4（Impact Analysis）作為推算起點。

## CHANGE 模式對 Discovery 的約束

Change Composition Report 回傳 discovery 後，約束後續步驟的行為：

| Discovery Step | 消費方式 |
|---------------|---------|
| Step 3（Structural Read） | 以 Δ-* 意圖的影響預估決定掃描優先序（但仍掃描全量） |
| Step 4（Impact Analysis） | 以每個 Δ-* 意圖作為推算起點，計算 create/modify/delete |
| Step 6（Clarify Loop） | ASM / GAP / BDY 項目轉為 CiC 問題，驅動互動循環 |

**關鍵原則**：Change Composition Report 只做「意圖拆解」和「初步預估」。精確的影響範圍由 discovery Step 3 + Step 4 負責推算。此處的影響預估是粗粒度的方向指引，不是最終結論。
