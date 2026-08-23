# 釐清問題

一個 Command 同時改動好幾個 Aggregate 時（例如「結算訓練」一次改動 6 個以上），決議 7 說要放在「發起端」的 Aggregate 資料夾——「發起端」用什麼規則判定？

# 定位

翻譯單元：全部跨 Aggregate 的 Command（訓練結算、訓練獎勵發放、階級提升、排行榜結算、商品購買、團隊任務等）。
Gherkin 位置：檔案路徑的資料夾層。
對應樣板空格：不對應句子，對應決議 7 註記「跨 Aggregate 的 Command 放在發起端的 Aggregate 資料夾（此處易起爭議）」。
相關既有共識：`.es-clarify/resolved/aggregate/使用者_使用者Aggregate的欄位與邊界尚未定義.md`（Aggregate 邊界的來源）。

# 白話說明

以模型中最極端的一個為例。已查證 `訓練結算流程.md` 的內容，Command「結算訓練」一次改動：

| 被改動的 Aggregate | 改了什麼 |
|---|---|
| 訓練紀錄 | 寫入消耗大卡、凍結不再修改 |
| 連續訓練 | 連續天數續計 |
| 使用者 | 累積訓練次數 +1、經驗值 +30 |
| 虛擬貨幣 | 金幣 +30～39 |
| 能力值 | 六維其中一維的點數提升 |
| 個人排行榜分數 | 分數增加 |
| 使用者成就解鎖紀錄 | 可能解鎖成就 |

這個 `結算訓練.feature` 該放進哪個資料夾？下面三種規則會給出三個不同答案：

- 選 A（**Command 的目標 Aggregate**，也就是「這個動作是對誰下的」）→ `features/訓練紀錄/`
- 選 B（**Actor 所屬的 Aggregate**）→ Actor 是「系統」，系統不是 Aggregate，此例無法判定
- 選 C（**最先被改動的 Aggregate**）→ `features/訓練紀錄/`，但「最先」在模型中並無定義，
  訓練結算流程的 Postcondition 並未標示先後順序

再看一個結論不同的例子：「使用補簽券」改動補簽券（張數 −1）與連續簽到（天數回復）兩個 Aggregate。

選 A（依 Command 的目標 Aggregate）：

```
features/訓練紀錄/結算訓練.feature
features/補簽券/使用補簽券.feature
```

選 C（依第一個 Event 所關聯的 Aggregate，且把「主要結果」當第一個）：

```
features/訓練紀錄/結算訓練.feature
features/連續簽到/使用補簽券.feature      ← 與選 A 不同
```

選 B（依 Actor 所屬 Aggregate）：

```
features/使用者/使用補簽券.feature
features/???/結算訓練.feature            ← Actor 是「系統」，系統不是 Aggregate，無處可放
```

# 多選題

| 選項 | 描述 | 推薦 |
|------|------|------|
| A | 依 **Command 的目標 Aggregate ID**（即 `01_Command清單.md`〈輸入參數推導規則〉中作為輸入的那個 Aggregate ID）判定 | ★ |
| B | 依 **Actor 所屬的 Aggregate** 判定（使用者 Command 放使用者資料夾，管理員 Command 放管理員資料夾） |  |
| C | 依 **該 Command 導致的第一個 Event 所關聯的 Aggregate** 判定 |  |
| D | 依 **業務上最重要的結果** 判定，逐案裁決，不訂通則 |  |
| Short | 提供其他簡短答案（<=5 字） |  |

# 推薦選項與理由

**推薦 A（依 Command 的目標 Aggregate ID）。**

理由一（模型裡已經有這個欄位，不需新增任何資訊）：已查證
`Event-Storming_事件風暴/01_Command清單.md`〈Command 輸入參數的推導規則〉明文寫著

> **Command 的輸入參數 ＝ 其導致的 Event 之專屬攜帶欄位 ＋ 目標 Aggregate ID ＋ 請求識別碼**

也就是說，**每一個 Command 都已經有一個「目標 Aggregate ID」**，這是模型既有的定義，
不是為了分資料夾而新造的概念。選 A 等於直接讀這個欄位，是四個選項中唯一「零新增資訊、零主觀判斷」的。

理由二（與 DDD 的既有語義一致）：Command 送達的那個 Aggregate 就是這次交易的一致性邊界，
其餘 Aggregate 的變動一律經由 Policy 串聯而來——這在模型裡看得很清楚：
訓練結算流程中「能力值已提升」「個人排行榜分數已增加」等都掛在各自的 Postcondition 與 Policy 之下，
而不是「訓練已結算」這個 Event 本身。

理由三（決議 7 的字面）：決議 7 說的是「發起端」，選 C 說的是「最先被改動」——
兩者在有 Policy 串聯的模型裡經常不一樣，而模型從未定義過 Postcondition 的先後順序，
選 C 在本模型中實際上不可判定。

不推薦 B：`00_全域規範.md`〈Actor 清單〉已查證只有五種 Actor
（使用者、管理員、系統、AI、外部系統），其中**系統、AI、外部系統都不是 Aggregate**。
而模型中大量 Command 的 Actor 正是「系統」（結算訓練、發放註冊獎勵、指派新手任務、
產生能力值日快照…），選 B 對這些一律無解。

不推薦 D：逐案裁決會使 283 個 Command 中的每一個跨 Aggregate 者各成一題，
與本階段「機械式翻譯、不需主觀判斷」的目標直接衝突。

# 各選項的翻譯後果

| 選項 | Feature 檔數 | Scenario 條數 | 維護成本 |
|------|-------------|--------------|----------|
| A | 318（分佈確定，可機械算出） | 不受本題影響 | 最低。讀模型既有欄位即可 |
| B | 318（但系統 / AI / 外部系統 Actor 的約 60 個 Command 無處可放） | 不受本題影響 | 高，且有無解案例 |
| C | 318（分佈不確定，模型未定義 Event 先後順序） | 不受本題影響 | 高。需先為每個流程訂 Event 順序 |
| D | 318（分佈需逐案裁決） | 不受本題影響 | 最高。約 40+ 個跨 Aggregate Command 各需一題 |

# 影響範圍

影響所有跨 Aggregate Command 的檔案路徑（初步盤點至少涉及訓練結算、訓練獎勵發放、
階級提升、排行榜週期結算、實體／虛擬商品購買、會員訂閱、團隊任務、師徒任務等流程）。
本題與 `.gh-clarify/organization/全域_資料夾依Aggregate切分時是否每個Aggregate各建一個資料夾.md`
必須一起定案，否則資料夾規則不完整。

# 優先級

High

---

# 解決結果

**A** —— 依 Command 的「目標 Aggregate ID」（`01_Command清單.md`〈輸入參數推導規則〉
的既有欄位）判定發起端；其餘 Aggregate 的變動視為 Policy 串聯，不影響歸檔。
不採 Actor 所屬 Aggregate、不採第一個 Event、不採逐案裁決。

# 回寫位置

`Gherkin_行為規格/00_翻譯規約.md` §1.6 跨 Aggregate Command 的歸屬

# 產出的 Gherkin 片段

本題不產生句子，產生的是路徑判定：

```
features/訓練紀錄/結算訓練.feature
```

（`結算訓練` 一次改動訓練紀錄、連續訓練、使用者、虛擬貨幣、能力值、
個人排行榜分數、使用者成就解鎖紀錄共 7 個 Aggregate，仍只放目標 Aggregate 一處。）

# 連帶影響

- 與第 5 題（資料夾切分）共同構成完整歸檔規則：
  「資料夾 ＝ Aggregate，一層；跨 Aggregate 取目標 Aggregate ID」。
  兩條合起來使 318 個檔案的路徑**完全可機械算出**，後續批次不再需要歸檔類個案題。
- 本條**不決定** GH4.5（連帶產生的 Event 要不要在 `Then` 一併斷言）——
  那是斷言範圍問題，與檔案位置無關，留待個案掃描。

# 解決日期

2026-08-23
