---
description: 掃描已釐清完成的事件風暴模型，找出「還不足以機械式翻譯成 Gherkin」的缺口（Feature 切分、When 觸發源、Given 前提、Then 斷言與失敗分類、Scenario Outline、Query 最終一致性、檔案組織），將釐清項目以結構化格式記錄於 .gh-clarify/ 資料夾，供後續 gh-formulation 階段使用。
---

目標：把事件風暴模型推進到「拿起樣板就能逐句翻成 Gherkin、不需再做主觀判斷」的狀態。偵測翻譯過程中**無法機械決定**的決策點，記錄到 `.gh-clarify/` 資料夾，並產生 `overview.md` 說明釐清優先順序策略。

# 前置：確認掃描標的

1. 讀取事件風暴模型檔：`Event-Storming_事件風暴/` 下的全部流程檔與核心五檔（`00_全域規範.md`、`01_Command清單.md`、`02_Aggregate定義.md`、`03_能力值.md`、`04_ReadModel清單.md`）。
2. 讀取 `.es-clarify/resolved/` 下全部已解決項目，作為**既有共識**。這是本階段最重要的前置：模型的業務決策已經釐清過 392 項以上，凡是能在 resolved 中查到答案的，一律不得再問。
3. 讀取 `.gh-clarify/resolved/`（若存在），避免重複本階段自己問過的題目。
4. 讀取已產出的 `Gherkin_行為規格/features/**/*.feature`（若存在），比對哪些 Command / Query 已翻譯、哪些尚未。
5. 若 `Event-Storming_事件風暴/` 下找不到流程檔，**停止並回報**，不得自行臆造。

# 與 /es-discovery 的分工（本檔的核心約束）

`/es-discovery` 問的是「**業務上是什麼**」，`/gh-discovery` 問的是「**這件事怎麼寫成 Gherkin 句子**」。

以下主題**已由 `/es-discovery` 掃描並釐清完畢，本指令一律不得重新建立釐清項目**：

| 已完成主題（es-discovery 檢查項） | 本階段的態度 |
|-----------------------------------|--------------|
| A. Event 是否成立、命名、時序、軟體邊界 | 直接採用，不再質疑 Event 清單 |
| B. Command 識別、輸入參數、Actor 與權限內容 | 直接採用，不再質疑誰能做什麼 |
| C. Precondition / Postcondition 的內容與邊界條件 | 直接採用規則內容，只問「怎麼分組成 Rule 區塊」 |
| D. Aggregate 欄位、型別、狀態機、Read Model 欄位 | 直接採用，不再質疑欄位定義 |
| E. 串聯一致性、F. 統一語言與術語 | 直接採用 |
| G1. 每個 Event 是否有 Precondition / Postcondition | 已掃過，不重掃；若翻譯時才發現缺漏，見〈遇到模型缺口時的處理〉 |
| G2. `[Rule]` 的角色標記是否正確 | 已掃過，屬文件訂正，不建釐清項目 |
| G3. 參數是否有具體數值可代入 | 已掃過；本階段只問「這些數值要排成幾列 Examples」 |
| G4. 值域是否完整 | 已掃過；本階段只問「值域要不要每一值各寫一列」 |
| G5. 補標作業的正確性 | 已掃過，不重掃 |

**判斷準則**：若一個問題的答案會改變「系統該做什麼」，它屬於 `/es-discovery`，不屬於本階段。若答案只改變「同一件事寫成幾個 Scenario、句子長什麼樣、檔案放哪裡」，才屬於本階段。

## 遇到模型缺口時的處理

掃描中若發現模型本身真的缺了業務決策（例如某 Command 完全沒有 Precondition、某參數仍為「尚未給定」），**不得在本階段補問業務內容**。改為：

- 在 `.gh-clarify/overview.md` 的〈退回 es-discovery 清單〉列出該缺口與所屬檔案。
- 不建立 `.gh-clarify/` 釐清項目。
- 完成報告中明確提示使用者先跑 `/es-discovery`。

---

# 翻譯樣板（判準基礎，來源：WaterBall 事件風暴翻譯 Gherkin ＋ SOP 補強決議）

掃描的每一項檢查，都是在問「這個樣板的某個空格，模型有沒有給出唯一答案」。

## 起始點與切分

- 翻譯從 **Read Model** 或 **Command** 開始，分為兩大分支：**查詢型（Query）** 與 **修改型（Command）**。
- **每一個 Command / Query 各自是一個獨立的 Feature File**（Event 不是檔案單位）。
- 先分好 Rules，按前置 / 後置條件分開翻譯。
- 括號中的 Key 代表 Actor / Aggregate 的識別碼。

## 查詢型（Query）

```
Rule：前置條件（Precondition）
  Given：Aggregate、Command、Event（含 Actor 的 Key）
  When ：Query（含 Actor 的 Key）
  Then ：操作失敗

Rule：後置條件（Postcondition）
  Given：Aggregate、Command、Event（含 Actor 的 Key）
  When ：Query（含 Actor 的 Key）
  Then ：Read Model（驗證查詢結果）
```

## 修改型（Command）

```
Rule：前置條件（Precondition）
  Given：Aggregate、Command、Event（含 Actor 的 Key）
  When ：Command、Event（含 Actor 的 Key）
  Then ：操作失敗
  And  ：Aggregate（驗證狀態保持不變）

Rule：後置條件（Postcondition）
  Given：Aggregate、Command、Event（含 Actor 的 Key）
  When ：Command、Event（含 Actor 的 Key）
  Then ：操作成功
  And  ：Aggregate（改變後的狀態）
  And  ：Event（產生的事件）
```

## 七項 SOP 補強決議（掃描時一併檢核是否可套用）

| # | 決議 | 對掃描的意義 |
|---|------|--------------|
| 1 | 失敗**依失敗原因分題**，各自獨立成 Rule（權限不足／輸入驗證錯誤／業務規則違反／併發衝突）。Query、Command 兩邊都套用；`And` 子句維持原始不對稱：**Query 端失敗 Rule 不加 `And`**（Query 不修改狀態），**Command 端失敗 Rule 每個都保留 `And：Aggregate（驗證狀態保持不變）`** | 需知道每個 Command 的失敗原因**共有幾類** |
| 2 | 權限驗證**獨立成一種 Rule 類型**，與「業務規則驗證」分開寫。權限驗證的 Given **沿用原始完整樣板，不簡化** | 需知道哪些 Command 的失敗含權限類 |
| 3 | 由 Policy 自動觸發的 Command，`When` 改寫成「**當某 Event 發生時**」（不用 Actor + Key）；與 Actor 觸發的版本**分開成兩個 Rule** | 需知道每個 Command 的觸發源是 Actor 還是 Event |
| 4 | Given 裡多個 Event 的順序，**只在順序會影響 Aggregate 最終狀態時**才明確列出並標示 | 需知道哪些 Given 的 Event 順序具語意 |
| 5 | Query 的 Postcondition **預設假設 Read Model 已同步完成**；符合三條件之一者視為「關鍵 Query」，額外新增專門 Rule 處理「尚未同步完成」情境 | 需逐一判定哪些 Query 是關鍵 Query |
| 6 | 同一 Rule 底下「**邏輯完全相同、只有輸入資料不同**」者，**強制**使用 `Scenario Outline` + `Examples`，禁止複製貼上多個獨立 Scenario | 需知道哪些規則屬同邏輯多資料 |
| 7 | **按 Aggregate 分資料夾**，資料夾內依 Command / Query 分別建立 Feature File，檔名統一「動詞＋名詞」格式；跨 Aggregate 的 Command 放在**發起端**的 Aggregate 資料夾 | 需知道跨 Aggregate Command 的發起端歸屬 |

---

# 執行步驟

## 1. 可翻譯性掃描

對模型中**每一個 Command 與每一個 Read Model（Query）**逐一套用下列檢查清單，標記狀態：Clear（可機械翻譯）／ Partial（樣板有空格填不滿）／ Missing（完全無法決定）。

### GH1. 翻譯單元切分（Feature File 的邊界）

- [ ] GH1.1 每一個 Command 是否都能對應到**恰好一個** Feature File？是否存在顆粒度過粗、實際上該拆成多個 Feature 的 Command？
- [ ] GH1.2 是否存在**同一個 Event 由多個 Command 導致**的情形？各 Command 是否確認為各自獨立的 Feature File（而非合併為一個 Event 檔）？
- [ ] GH1.3 標記為〔不需精準追蹤〕的 Event，其相關操作是否確認**不產生任何 Feature File**（無 Precondition / Postcondition 即無斷言可寫）？若該操作仍有 Command，該 Command 的 Feature 內容為何？
- [ ] GH1.4 循環型流程（自訂訓練、訓練紀錄、AI 訓練中調整）中的「一次循環」是否為一個 Feature，還是整段循環為一個 Feature？循環邊界的斷言掛在哪裡？
- [ ] GH1.5 一個 Command 若對不同 Actor（使用者／教官／管理員）行為有差異，是寫成同一 Feature 內的不同 Rule，還是拆成不同 Feature File？

### GH2. When 子句（觸發源的寫法）

- [ ] GH2.1 每一個 Command 的觸發源是 **Actor 主動**還是 **Policy 自動（由 Event 觸發）**？模型中是否已能明確判定？
- [ ] GH2.2 由 Policy 觸發的 Command，**觸發用的 Event 是哪一個**？是否已在模型中寫明？（決議 3 要求 `When：某 Event 發生時`）
- [ ] GH2.3 是否存在**同一個 Command 兩種觸發源都有**（使用者可手動觸發、系統也會自動觸發）的情形？是否確認拆成兩個 Rule？
- [ ] GH2.4 排程觸發（每日 04:00 重置、週期結算、逾期判定）的 `When` 該寫成哪個 Event？「時間到了」本身是否為模型中的 Event？若不是，`When` 的主詞是什麼？
- [ ] GH2.5 外部系統回呼（App Store 訂閱、Google／Apple 登入、金流）的 `When` 該寫成 Actor 觸發還是 Event 觸發？外部系統是否視為 Actor？

### GH3. Given 子句（前提的可寫性）

- [ ] GH3.1 每一條 Precondition 對應的 `Given`，樣板要求的三種素材（Aggregate 狀態、先前的 Command、先前的 Event）是否都能從模型取得？哪一種缺？
- [ ] GH3.2 `Given` 需要寫出 Aggregate 的**具體初始值**（例如「能力值六維皆為 10」「金幣餘額為 0」），這些值模型是否已給定？
- [ ] GH3.3 `Given` 中出現**多個 Event** 時，其先後順序是否會影響 Aggregate 最終狀態？（決議 4：影響才需標示順序）
- [ ] GH3.4 需要**跨 Aggregate 前提**的 Command（例如需同時滿足使用者狀態與團隊狀態），`Given` 要列出幾個 Aggregate？是否有不需寫出的？
- [ ] GH3.5 Actor 的 **Key 是什麼**（使用者 ID／教官 ID／團隊 ID）？`Given` 與 `When` 括號中該帶哪一個 Key？多 Actor 情境要帶幾個？
- [ ] GH3.6 權限驗證類 Rule 的 `Given` 沿用完整樣板（決議 2），該 Given 中**與權限無關的 Aggregate / Event 素材**具體要寫哪些？是否有可觀察的判斷依據？

### GH4. Then 子句（斷言與失敗分類）

- [ ] GH4.1 每一個 Command 的**失敗原因共有幾類**？是否可歸入四類（權限不足／輸入驗證錯誤／業務規則違反／併發衝突）？有無第五類？
- [ ] GH4.2 每一類失敗是否都能對應到模型中**具體的某一條 Precondition**？是否有 Precondition 找不到對應失敗類別？
- [ ] GH4.3 失敗時的 `Then` 除了「操作失敗」，是否需要斷言**具體的錯誤訊息或回饋內容**？該內容模型是否已定義？
- [ ] GH4.4 Command 端失敗 Rule 的 `And：Aggregate（驗證狀態保持不變）`，**比較基準的欄位範圍**為何（全部欄位／僅該 Command 會動的欄位）？
- [ ] GH4.5 成功時的 `And：Event（產生的事件）`，該 Command 會**連帶產生哪些其他 Event**（連鎖 Policy）？這些連帶 Event 要不要一併斷言，還是留給各自的 Feature？
- [ ] GH4.6 一個 Command 改變**多個 Aggregate** 時，`And` 要為每個 Aggregate 各寫一句，還是合併？跨 Aggregate 的一致性要不要斷言？
- [ ] GH4.7 具「單調遞增／不可逆」性質的規則，其 `Then` 是斷言「操作失敗」還是「狀態不變但操作成功（冪等）」？兩者在測試上不同。

### GH5. Scenario Outline 與 Examples

- [ ] GH5.1 哪些 Rule 屬於「邏輯完全相同、只有輸入資料不同」，依決議 6 **必須**改寫為 `Scenario Outline`？
- [ ] GH5.2 這些 Outline 的 **Examples 表格要有哪幾欄**（輸入參數欄／預期結果欄）？
- [ ] GH5.3 數值邊界的列數：是否統一採「剛好達標／差一點／超過」三列？各列的**具體數值**是否都已定案（無「尚未給定」）？
- [ ] GH5.4 列舉值域（狀態四值、9 類成就、六維能力值）是否**每一值各寫一列**，還是取代表值？（決議 6 註記：值域決定要寫幾列）
- [ ] GH5.5 是否存在「表面上同邏輯、但某幾筆資料需要**額外的 Given** 才成立」的情形？依決議 6 註記，此時應拆為獨立 Scenario，不硬塞 Outline —— 有哪些？
- [ ] GH5.6 Examples 中的參數若為**平台級可調參數**（存於設定 Aggregate），表格要寫死當前預設值，還是寫成參數名？

### GH6. Query 專屬（Read Model 與最終一致性）

- [ ] GH6.1 每一個 Read Model 的 `Then` 要斷言**哪些欄位**？是否全欄位斷言，還是只斷言該 Query 的核心欄位？
- [ ] GH6.2 依決議 5 的三條件逐一判定：本 Query 是否為**關鍵 Query**（資料延遲會導致使用者重複操作／導致金錢庫存資源上的實際損失／有明確 SLA 或使用者期待即時性）？
- [ ] GH6.3 被判定為關鍵 Query 者，「尚未同步完成」情境的 `Then` 該斷言什麼（顯示舊值？顯示載入中？阻擋操作？）？
- [ ] GH6.4 有**篩選、排序、分頁**規則的 Read Model，其 `Then` 如何斷言順序與筆數？分頁邊界（第一頁／最後一頁／空清單）要不要各寫一條？
- [ ] GH6.5 Query 的失敗 Rule 有哪些（無權限查看他人資料／查無資料／目標已刪除）？「查無資料」屬於**失敗**還是**回傳空集合的成功**？
- [ ] GH6.6 需要**即時計算**的 Read Model（排行榜分數、能力值等級、完成度）其 `Then` 斷言的是儲存值還是計算值？

### GH7. 檔案組織與語言慣例

- [ ] GH7.1 每一個 Command / Query 歸屬到**哪一個 Aggregate 資料夾**？是否有歸屬不明者？
- [ ] GH7.2 **跨 Aggregate 的 Command**，「發起端」的判定標準為何？（決議 7 註記此處易起爭議）哪些 Command 的發起端目前無法判定？
- [ ] GH7.3 Feature File 的檔名「動詞＋名詞」如何從中文 Command 名轉出（英文？拼音？中文檔名）？
- [ ] GH7.4 Gherkin 句子本身用**中文**還是英文撰寫？關鍵字（Given/When/Then）是否使用中文關鍵字（假設／當／那麼）？
- [ ] GH7.5 Feature 標題與 Rule 標題的命名格式是否統一（例：`Rule: 權限驗證`／`Rule: 業務規則驗證`／`Rule: 輸入驗證`）？
- [ ] GH7.6 Gherkin 句子中的名詞是否**逐字沿用模型的統一語言**？有無模型術語過長、需要在 Gherkin 中縮寫的情形？縮寫對照表放哪裡？

---

**釐清項目篩選原則**

對於狀態為 Partial 或 Missing 的檢查項建立釐清項目，除非：

- 答案不會改變任何一個 Feature File 的內容或數量，或
- 答案屬於實作階段的測試框架選型（step definition 怎麼寫、用哪個 runner）——這些不進本階段。

僅納入其答案會實質影響**Feature 檔案數量與邊界、Scenario 條數、Given/When/Then 句子內容、Examples 列數、檔案路徑**的問題。

**避免重複提問原則**

建立新釐清項目前，必須先掃描 `.es-clarify/resolved/`（392 項以上）與 `.gh-clarify/resolved/`：

- 若該問題的答案已在 `.es-clarify/resolved/` 中裁決過，**直接採用該答案，不建立釐清項目**，並在 `overview.md` 的〈直接沿用既有共識〉列出對照。
- 若問題角度不同但相關，在新釐清項目的「定位」中註記相關的已解決檔名。

## 2. 產生釐清項目檔案

### 檔案路徑規則

依「該問題的答案會改動 Gherkin 的哪一部分」歸檔，一個問題只放一個資料夾：

| 資料夾 | 收納對象 | 範例 |
|--------|----------|------|
| `.gh-clarify/feature/` | Feature File 的切分、邊界、數量（檢查項 GH1） | `.gh-clarify/feature/記錄該組成績_一次循環是一個Feature還是整段循環.md` |
| `.gh-clarify/when/` | 觸發源、Policy 觸發、排程與外部回呼的 When 寫法（檢查項 GH2） | `.gh-clarify/when/每日任務已重置_排程觸發的When主詞為何.md` |
| `.gh-clarify/given/` | Given 的素材、初始值、Event 順序、Actor Key（檢查項 GH3） | `.gh-clarify/given/建立團隊_Given要列出幾個Aggregate.md` |
| `.gh-clarify/then/` | 失敗分類、斷言內容、連帶 Event（檢查項 GH4） | `.gh-clarify/then/儲值金幣_失敗原因共有幾類.md` |
| `.gh-clarify/outline/` | Scenario Outline 與 Examples 表格（檢查項 GH5） | `.gh-clarify/outline/能力值已提升_邊界值要寫幾列.md` |
| `.gh-clarify/query/` | Read Model 斷言、關鍵 Query 判定、分頁排序（檢查項 GH6） | `.gh-clarify/query/個人排行榜_是否為關鍵Query.md` |
| `.gh-clarify/organization/` | 資料夾歸屬、檔名、語言慣例（檢查項 GH7） | `.gh-clarify/organization/全域_Gherkin句子用中文還是英文.md` |

命名格式：`<Command 或 Read Model 原始名稱>_<問題全句，以底線代替分隔符號>.md`

- 名稱使用模型檔中的原始名稱，不得自行改寫。
- 全域性的翻譯慣例問題（不屬於任一 Command），元素名寫 `全域`。

### 釐清項目檔案格式

```markdown
# 釐清問題

<釐清問題之完整句子，以白話撰寫>

# 定位

<翻譯單元：哪一個 Command / Query？屬哪一個 Aggregate？>
<Gherkin 位置：Feature 切分 / When / Given / Then / Examples / 檔案路徑 之中的哪一個？>
<對應樣板空格：這題填的是樣板中的哪一格？>
<相關既有共識：`.es-clarify/resolved/` 中的相關檔名（若有）>

# 白話說明

<用不含模型術語的白話，說明這題在問什麼，並附一段具體的 Gherkin 片段示意，
 讓使用者看得出「選 A 會長這樣、選 B 會長那樣」。>

# 多選題

| 選項 | 描述 | 推薦 |
|------|------|------|
| A | <選項 A 描述> | ★ |
| B | <選項 B 描述> | |
| C | <選項 C 描述> | |
| D | <選項 D 描述>（選用）| |
| Short | 提供其他簡短答案（<=5 字）| |

# 推薦選項與理由

<標 ★ 的選項為業界最常見做法。說明「為什麼多數團隊這樣做」，
 以及本專案模型中是否有既有慣例支持該選項（引用具體檔名與行為）。
 若本專案情況與常見做法相左，須明講並改推薦另一選項。>

# 各選項的翻譯後果

| 選項 | Feature 檔數 | Scenario 條數 | 維護成本 |
|------|-------------|--------------|----------|
| A | ... | ... | ... |
| B | ... | ... | ... |

# 影響範圍

<說明此釐清將影響哪些 Feature File、哪些 Rule 區塊、哪些 Examples 表格；
 是否會連帶決定其他尚未提問的釐清項目（列出檔名）。>

# 優先級

<High / Medium / Low>
- High：決定 Feature File 的數量或邊界、決定全域翻譯慣例（一旦定案會套用到所有檔案）
- Medium：影響單一 Feature 內的 Scenario 條數或斷言內容
- Low：檔名、句子措辭、標題格式
```

**多選題的撰寫規則（不可省略）**

- **每一題都必須標出推薦選項**（`★`）並在〈推薦選項與理由〉說明為什麼。沒有推薦選項的題目視為未完成。
- 推薦必須有依據：優先引用本專案 `.es-clarify/resolved/` 的既有裁決，其次才是業界通例。**不得憑記憶宣稱「模型裡已經有某條規則」——引用前先 grep 查證。**
- 涉及平台規範（App Store 審核、法規、支付規則）的選項，**必須查證官方文件後才能推薦**，不得憑記憶。查不到就在該選項註記「未查證」，不給推薦。
- 選項描述用白話 ＋ 具體例子。**不得直接用「Postcondition」「Aggregate 不變條件」這類術語出題**，必要時附一段實際的 Gherkin 片段對照。

## 3. 產生 Overview 文件

在 `.gh-clarify/overview.md` 產生總覽，內容包含：

### 3.1 翻譯標的盤點

| 項目 | 數量 |
|------|------|
| 待翻譯 Command（修改型 Feature） | X |
| 待翻譯 Read Model（查詢型 Feature） | X |
| 預估 Feature File 總數 | X |
| 已完成翻譯 | X |

### 3.2 釐清項目統計

- Feature 切分（GH1）：X 項
- When 觸發源（GH2）：X 項
- Given 前提（GH3）：X 項
- Then 斷言（GH4）：X 項
- Outline / Examples（GH5）：X 項
- Query 專屬（GH6）：X 項
- 組織與語言（GH7）：X 項
- 總計：Z 項

### 3.3 優先級分佈

High / Medium / Low 各 X 項。

### 3.4 建議釐清順序

**核心原則**：先定**全域慣例**，再定**單一 Feature 的內容**。全域慣例一旦晚定，前面翻好的檔案全要重改。

1. **第一階段：全域翻譯慣例（GH7）**
   語言、關鍵字、檔名格式、資料夾歸屬規則、Rule 標題格式。
   原因：這些會套用到每一個檔案，必須最先定案。
2. **第二階段：Feature 切分（GH1）**
   決定總共有幾個檔案、循環流程怎麼切。
   原因：檔案邊界決定後續每一題「這句話寫在哪個檔案」。
3. **第三階段：When 觸發源（GH2）**
   原因：決議 3 要求 Actor 觸發與 Policy 觸發分成兩個 Rule，會直接改變 Rule 數量。
4. **第四階段：Then 失敗分類（GH4）**
   原因：決議 1 要求依失敗原因分 Rule，失敗類別數 ＝ Rule 數，是 Scenario 條數的主要來源。
5. **第五階段：Given 前提（GH3）**
   原因：需建立在已確定的 Rule 分組之上。
6. **第六階段：Examples 與 Query（GH5、GH6）**
   原因：補足表格列數與查詢斷言，屬單一 Feature 內的細節。
7. **第七階段：Low 優先級的措辭與命名**

### 3.5 覆蓋度摘要

列出 GH1.1–GH7.6 每一檢查項的狀態（Clear / Partial / Missing）與已建立的釐清項目數。

### 3.6 直接沿用既有共識

列出「本可成題、但 `.es-clarify/resolved/` 已有答案」的項目，格式：`<問題> → 沿用 <resolved 檔名> 的裁決 <答案>`。此節用來向使用者證明沒有重複提問。

### 3.7 退回 es-discovery 清單

列出掃描中發現的**業務缺口**（非翻譯問題），格式：`<缺口> → 位於 <檔名>，建議跑 /es-discovery`。若為空，明確寫「無」。

## 4. 驗證產出

- [ ] 每個釐清項目都在問「怎麼寫成 Gherkin」，沒有一題在問「業務上該怎麼做」
- [ ] 每個釐清項目都能對應到樣板中的某一個空格
- [ ] **每一題都標出了推薦選項並附理由**
- [ ] 每一題都有〈白話說明〉且附 Gherkin 片段示意
- [ ] 沒有任何一題的答案已存在於 `.es-clarify/resolved/`
- [ ] 檔名使用模型原始名稱
- [ ] `overview.md` 的順序符合「全域慣例 → 檔案切分 → Rule 分組 → 句子內容」

## 5. 回報完成

- 掃描的模型檔案清單與 Command / Read Model 總數
- 釐清項目總數（分七類）與優先級分佈
- `.gh-clarify/` 資料夾結構概覽
- 〈直接沿用既有共識〉與〈退回 es-discovery 清單〉的筆數
- 提示使用者執行 `/gh-formulation` 進行下一階段釐清互動

# 行為規則

- **純偵測角色**：不進行互動式釐清，僅產出釐清項目檔案。
- **不重問業務**：凡答案會改變「系統該做什麼」的問題，一律不建立項目，改列入〈退回 es-discovery 清單〉。
- **不臆造模型**：模型沒寫的 Command、Event、欄位不得自行補上。
- **先查證再宣稱**：引用模型既有規則前必須實際查閱該檔案，不得憑記憶。
- **完整掃描**：不受題數限制，所有 Partial / Missing 都應成題。
- **每題必附推薦**：沒有推薦選項與理由的題目不得產出。
- **白話出題**：問題與選項須讓非技術背景者看得懂，一律附具體例子。
- **保持精煉**：一題只問一個決策點。
- **可驗收性**：每題的答案都能直接轉成 Feature File 的一段實際內容。

# 輸出格式要求

1. **釐清項目檔案** → `.gh-clarify/feature/*.md`、`.gh-clarify/when/*.md`、`.gh-clarify/given/*.md`、`.gh-clarify/then/*.md`、`.gh-clarify/outline/*.md`、`.gh-clarify/query/*.md`、`.gh-clarify/organization/*.md`
2. **總覽文件** → `.gh-clarify/overview.md`
3. **完成報告** → 終端輸出

# 與 gh-formulation 階段的銜接

- 本階段產出的釐清項目將被 `/gh-formulation` 讀取並逐題提問。
- `overview.md` 的釐清順序將指導提問順序。
- 〈各選項的翻譯後果〉表格讓使用者在回答時看得到取捨。
- 優先級與影響範圍幫助 formulation 決定是否提前終止。
