# Step Template 產生器

## 目的

從 Gherkin Feature File 生成 Step Definition 骨架（樣板），識別事件風暴部位，
標註對應的 Handler 類型，供 Red Implementation 階段逐一實作。

**產出僅為「樣板」** — 裝飾器 + 函數簽名 + TODO 註解 + 空方法體（pass / PendingException），不包含實作邏輯。

## 流程

### Step 0: Feature File 同步
僅在測試目錄尚未有對應 feature file 時執行：
- 建立 symbolic link（非複製），以 `${FEATURE_SPECS_DIR}` 為唯一 source of truth
- Link 必須使用**相對路徑**

### Step 1: 掃描現有 Step Definitions
**永遠不覆蓋已存在的 Step Definition！**
1. 掃描 `${STEPS_DIR}/` 所有已存在的 step patterns
2. 解析目標 .feature 需要的所有 Given/When/Then/And 步驟
3. 對比找出「缺少的步驟清單」
4. 只為缺少的步驟產生樣板

### Step 2: 句型分類（Handler Type 判定）

對每個缺少的步驟，用決策樹判定 handler type。

**精簡版決策樹**（快速分類用）：

```
Given → 狀態描述（「有」「為」「包含」） → aggregate-given
Given → 已完成動作（「已訂閱」「已建立」）  → command
When  → 寫入操作（「更新」「建立」「刪除」）→ command
When  → 讀取操作（「查詢」「取得」「列出」）→ query
Then  → 成功/失敗                         → success-failure
Then  → DB 狀態驗證（需額外查詢）          → aggregate-then
Then  → Response 驗證（用已拿到的資料）     → readmodel-then
And   → 繼承前一個 Then 的判斷
```

完整決策規則（含 4 抽象角色框架、判斷口訣、區別表）見：
`bdd-analysis/references/web-backend/句型分析方針.md`

### Step 3: 產生樣板
每個步驟產出含以下資訊的骨架：
- 裝飾器（`@given` / `@when` / `@then`）+ 完整 Gherkin pattern
- 函數簽名（`context` 為第一參數）
- TODO 標註：`[事件風暴部位: {TYPE} - {Name}]`
- TODO 標註：`參考 bdd-analysis/references/web-backend/handlers/{type}.md 實作`
- TODO 標註：`參考 Aggregate/Table: {Name}`（若為 DB 相關）
- 空方法體

## 模板規則

### 檔案組織
- **一個 Step Pattern 對應一個檔案**
- 先按 subdomain 分目錄（lesson/, order/, product/, role/）
- 再按 handler 類型分子目錄（aggregate_given/, commands/, query/, aggregate_then/, readmodel_then/）
- `common_then/` 為跨 subdomain 共用（操作成功/失敗等）

### 命名規則
- 語意化檔名（`lesson_progress.py` / `LessonProgressSteps.java`）
- 避免 `steps.py` 大雜燴

### 參數規則
- 第一個參數必須是 `context`（Python）/ 無（Java，用 @Autowired）
- 從 pattern 解析的參數直接跟在後面
- 不使用 fixtures 參數

## Handler 路由

Step Template 在 TODO 中標註 handler 類型，供 Red Implementation 階段載入對應的 handler reference。

| 事件風暴部位 | 抽象角色 | Handler Reference |
|------------|---------|------------------|
| Aggregate（初始狀態） | States Prepare | `bdd-analysis/references/web-backend/handlers/aggregate-given.md` |
| Command（寫入操作） | Operation Invocation | `bdd-analysis/references/web-backend/handlers/command.md` |
| Query（讀取操作） | Operation Invocation | `bdd-analysis/references/web-backend/handlers/query.md` |
| 操作成功/失敗 | Operation Result Verifier | `bdd-analysis/references/web-backend/handlers/success-failure.md` |
| Aggregate（DB 驗證） | States Verify | `bdd-analysis/references/web-backend/handlers/aggregate-then.md` |
| Read Model（Response 驗證） | Operation Result Verifier | `bdd-analysis/references/web-backend/handlers/readmodel-then.md` |

## 跨語言差異

| 面向 | Python (Behave) | Java (Cucumber) |
|------|-----------------|-----------------|
| 裝飾器 | `@given(...)` / `@when(...)` / `@then(...)` | `@Given("...")` / `@When("...")` / `@Then("...")` |
| 參數型別 | `{param:d}` (int), `"{param}"` (str) | `{int}`, `{string}` |
| 空方法體 | `pass` | `throw new PendingException()` |
| DataTable | `context.table` | `DataTable dataTable` 參數 |
| DocString | `context.text` | `String docString` 參數 |

## 完成條件

- [ ] 已掃描現有 Step Definitions，避免覆蓋
- [ ] 每個新增步驟都有正確的 Handler 類型標註
- [ ] 一個 step 一個 module/class
- [ ] 所有函數簽名正確
- [ ] 所有方法體為空（pass / PendingException）
