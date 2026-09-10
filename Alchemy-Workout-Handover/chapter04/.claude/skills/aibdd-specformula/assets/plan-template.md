# 工程計畫：${REQUIREMENT_TITLE}

> **狀態**: DRAFT
> **建立日期**: ${DATE}
> **最後更新**: ${DATE}
> **技術棧**: ${LANG} (${TEST_STRATEGY})
> **需求摘要**: ${REQUIREMENT_SUMMARY}

---

## Dependency Graph

| Phase | Name | Depends On | 狀態 |
|-------|------|------------|------|
| 01 | Requirement Analysis（需求分析 + 影響評估 + 行為設計） | — | todo |
| 02 | Entity Modeling（外部品質 — 資料） | 01 | todo |
| 03 | BDD Analysis（外部品質 — 可執行規格） | 02 | todo |
| 04 | API Contract（內部品質） | 03 | todo |
| 05 | Backend TDD Track | 04 | todo |
| 06 | Frontend Build Track | 04 | todo |
| 07 | Integration Validation | 05, 06 | todo |

```
01 → 02 → 03 → 04 ──┬──→ 05 ──┐
                     │         │
                     └──→ 06 ──→ 07
                                ↑
                         05 ────┘
```

## 線性執行順序（建議）

> 若無平行資源，依此順序逐一執行。

1. 01-requirement-analysis
2. 02-entity
3. 03-bdd-analysis
4. 04-api-contract
5. 05-backend-tdd
6. 06-frontend-build
7. 07-integration

## 品質框架

### Phase 01: Requirement Analysis（統一入口）

不區分 greenfield / 新功能 / 改變需求。每個需求都是 current state → desired state 的 delta。
Phase 01 產出 **Execution Plan**，決定 Phase 02-07 各自的工作範圍。

### External Quality（外部品質）— Phase 02~04

推理順序：**行為(01) → 資料(02) → 規格精煉(03) → 實作契約(04)**。

| Phase | 推理依據 |
|-------|---------|
| 01 → 02 | 有了行為（features）才能推導「作用在什麼實體上」 |
| 02 → 03 | 有了實體結構（erm.dbml）才能寫出精準的 Examples |
| 03 → 04 | 每個 command/query 天然對應一個 API endpoint |

### Implementation — Phase 05~07

Phase 01-04 的產出物是所有實作 Phase 的共同契約。

## 共同契約

Phase 01-04 的產出物是 Phase 05-07 的共同依據（Single Source of Truth）：

| 產物 | 路徑 | 消費者 |
|------|------|--------|
| Execution Plan | `${PLAN_DIR}/plan.md` | Phase 02-07（scope 依據） |
| Activity Diagrams | `${SPECS_ROOT_DIR}/activities/` | Phase 06（Chrome Test Guard 測試計畫結構） |
| Feature Files（含 Examples） | `${SPECS_ROOT_DIR}/features/` | Phase 05（TDD 循環） |
| erm.dbml | `${SPECS_ROOT_DIR}/entity/erm.dbml` | Phase 05（Schema Analysis） |
| api.yml | `${SPECS_ROOT_DIR}/api/api.yml` | Phase 05（Red 欄位守衛）、Phase 06（MSW handlers）、Phase 07（驗證基準） |

## Context Management

- 三層持久化：檔案系統（卡片）+ TodoWrite + Context Window
- Compact Proof 層次化：specformula 16 任務 / 各 Phase 內部自管細節
- Lazy Loading：每個 Phase 只載入當前 skill，跨 skill 必定重新 LOAD
- 詳見 skill `references/context-management.md`
