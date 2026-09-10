# Phase 02: Entity Modeling（外部品質 — 資料）

## 審查進度

- [ ] 02.1 相關規格已審查 — **簽名**: ___
- [ ] 02.2 交付物已審查 — **簽名**: ___

## 目的 (What)

從 Phase 01 的 Feature Files（Rules）推導資料結構——系統操作「作用在什麼實體上」。

**erm.dbml 必須在 BDD Analysis 之前完成。** Phase 03 的 QA 五維分析需要知道欄位名、型別、約束條件才能推導精準的 Examples。

**Reconciler 模式**：entity-spec 以 desired-state reconciliation 運作——讀取現有 erm.dbml（若存在）→ 推導 desired state → 計算 diff → 增量更新。Greenfield 時 current = 空。讀取 Execution Plan 中 Phase 02 的 scope 決定工作範圍。

**依賴**：Phase 01 必須在 `done/` 中。

## 相關規格

| # | 規格 | 來源 | 說明 |
|---|------|------|------|
| 1 | Execution Plan | Phase 01 交付 | 本 Phase 的工作範圍（create/modify/delete 哪些實體） |
| 2 | Feature Files（Rules） | Phase 01 交付 | 行為規則——每個 command/query 操作的前置/後置條件 |
| 3 | Activity Diagrams | Phase 01 交付 | 流程結構——實體間的關聯與生命週期 |

## 交付物

carry-on Step 02.2 觸發時：

1. **DELEGATE `/aibdd-form-entity-spec`**，傳入：
   - Feature Files 路徑（`${SPECS_ROOT_DIR}/features/`）
   - Activity Diagrams 路徑（`${SPECS_ROOT_DIR}/activities/`）
   - 輸出路徑（`${SPECS_ROOT_DIR}/entity/erm.dbml`）
   - Execution Plan scope（Phase 02 區段）
2. entity-spec 以 Reconciler 6 步執行：Derive Desired → Read Current → Compute Diff → Preview → Apply with Clarify → Output
3. 產出 erm.dbml 後回傳控制權

| # | 交付物 | 路徑 | 狀態 |
|---|--------|------|------|
| 02.1 | erm.dbml | `${SPECS_ROOT_DIR}/entity/erm.dbml` | PENDING |
| 02.2 | 澄清紀錄 | `${SPECS_ROOT_DIR}/clarify/` | PENDING |

### 驗收點

- [ ] erm.dbml 已產出
- [ ] Grep `CiC\(` 掃描 `entity/erm.dbml` 結果為空
- [ ] 每個 Feature 中的操作都能追溯到 erm.dbml 中的實體
- [ ] 欄位名、型別、約束條件完整
