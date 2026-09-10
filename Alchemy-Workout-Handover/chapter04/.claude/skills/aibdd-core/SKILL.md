---
name: aibdd-core
description: >
  跨 skill 共用的 reference 庫。包含 reconciler contract（desired-state reconciliation 合約）等
  所有 form skill 共用的模式定義。不直接觸發，由其他 skill Read references/ 中的檔案。
---

# 共用 Reference 庫

本 skill 不執行任何流程，僅提供跨 skill 共用的 reference 文件。

## References

| 檔案 | 說明 | 消費者 |
|------|------|--------|
| `references/reconciler-contract.md` | Desired-State Reconciliation 合約 | 所有 form skill（entity-spec, api-spec, bdd-analysis, feature-spec, activity-spec） |
