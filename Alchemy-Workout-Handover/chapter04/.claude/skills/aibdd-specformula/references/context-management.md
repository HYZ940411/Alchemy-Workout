# Context Management & Compact Proof 設計

specformula 的 context 管理策略，確保任何 compaction / session 中斷都能零遺失恢復。

## 三層持久化架構

```
Layer 1: 檔案系統（最持久，跨 session、跨 AI）
├── plan.md           → Dependency Graph（唯讀）
├── todo/doing/done/  → 卡片位置 = Phase 狀態
├── 卡片內簽核         → `- [x] ... — YYYY-MM-DD HH:mm`
├── clarify-log.md    → Consistency Analyzer 收斂紀錄
└── 交付物狀態         → PENDING / SPEC_READY / DONE

Layer 2: TodoWrite（跨 compaction 持久）
├── specformula 層    → 8 Phase + 8 Gate = 16 任務
├── discovery 層      → 7 里程碑任務（Phase 01，由 discovery 自管）
├── bdd-analysis 層   → 3 子階段（Phase 03，由 bdd-analysis 自管）
└── control-flow 層   → N features × 3 phases（Phase 05，由 cf 自管）

Layer 3: Context Window（最易失）
├── 當前 Phase 卡片內容
├── 當前步驟 (NN.M) 審查狀態
└── 最近一次 skill DELEGATE 結果
```

## Compaction 恢復策略

Context 被壓縮後，carry-on 自動執行：

1. 讀 `plan.md` → 取得 Dependency Graph
2. 掃 `todo/` `doing/` `done/` → 定位當前 Phase
3. 讀 `doing/` 中的卡片 → 檢查預審標記 + 找第一個未簽核步驟
4. 讀 TodoWrite → 確認子任務進度
5. 重新 LOAD 當前步驟需要的 skill
6. 重新展示步驟 + (A)(B1)(B2)(C)(D) 選項

**零資訊遺失**：所有狀態都在 Layer 1 + 2 中，Layer 3 可完全從前兩層重建。

## Compact Proof 層次化展開

```
specformula 層（Layer 0）— 固定 16 任務（8 Phase + 8 Gate）
│
├─ Phase 01 展開時（Layer 1）
│  └→ discovery 統一流程 6 步
│     └→ 組成分析 → Structural Read → Impact Analysis → 澄清 → 行為設計 → Quality Gate
│
├─ Phase 02 展開時（Layer 1）
│  └→ entity-spec 澄清循環
│
├─ Phase 03 展開時（Layer 1）
│  └→ bdd-analysis 三子階段
│     └→ 系統抽象 → 句型模型 → Examples（每層使用者審核）
│
├─ Phase 04 展開時（Layer 1）
│  └→ api-spec 澄清循環 + command/query 映射
│
├─ Phase 05 展開時（Layer 1）
│  └→ control-flow 內部 N features × 3 phases
│
├─ Phase 06 展開時（Layer 1）
│  └→ Starter Batch A-F → API Layer → Pages
│
├─ Phase 07 展開時（Layer 1）
│  └→ Activity Test Plan → Chrome E2E（mock mode）
│
└─ Phase 08 展開時（Layer 1）
   └→ 啟動後端 → 環境切換 → 重跑 E2E → 驗證矩陣
```

每一層各自用自己的 TodoWrite 管理。specformula 層看到 16 任務，不看到 discovery 的 7 步或 control-flow 的 N×3 步。

## Skill Lazy Loading 策略

| Phase doing 時 | LOAD 的 Skills |
|---------------|---------------|
| Phase 01 | `/aibdd-discovery`（統一流程：組成分析 → Structural Read → Impact → 行為設計） |
| Phase 02 | `/aibdd-form-entity-spec` |
| Phase 03 | `/aibdd-form-bdd-analysis`（內部 lazy load web-backend preset） |
| Phase 04 | `/aibdd-form-api-spec` |
| Phase 05 | `/aibdd-auto-control-flow` → 內部呼叫 `/aibdd-auto-red`、`green`、`refactor`（各自 lazy load variant references） |
| Phase 06 | `/aibdd-auto-frontend-apifirst-msw-starter` → `msw-api-layer` → `nextjs-pages`（依序載入） |
| Phase 07 | `/aibdd-frontend-e2e-activity-testplan` |
| Phase 08 | 無新 skill，重用 Phase 07 的 test plan |

**跨 skill 切換時必定重新 LOAD**（non-negotiable）— 確保 context 中涵蓋正確的規則。

## 多 AI 平行執行

Phase 05 & 06 可由兩個 AI session 平行執行：

- 每個 AI 獨立掃描 `todo/doing/done/`
- `doing/` 中的卡片視為已被占用，不搶
- 各 AI 只修改自己正在處理的卡片
- `plan.md` 不被修改，無衝突風險

Phase 08 必須等 05 + 07 都在 `done/` 才可啟動。
