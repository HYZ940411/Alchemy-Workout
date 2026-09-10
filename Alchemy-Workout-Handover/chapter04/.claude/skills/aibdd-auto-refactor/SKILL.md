---
name: aibdd-auto-refactor
description: >
  BDD 重構階段。在測試保護下，以小步驟改善程式碼品質。
  內含完整的 code quality 規則集（SOLID、DRY、架構分層、日誌實踐），
  透過 arguments.yml 路由語言變體。
  當 /aibdd-auto-control-flow 呼叫重構階段，或使用者說「重構」「refactor」時觸發。
---

# 重構階段

在測試保護下，小步驟改善程式碼品質。

## 變體路由

| tech_stack | test_strategy | 載入 variant | 載入 code-quality |
|-----------|---------------|-------------|------------------|
| python | e2e | `references/variants/python-e2e.md` | `references/code-quality/python.md` |
| java | e2e | `references/variants/java-e2e.md` | `references/code-quality/java.md` |
| python | ut | `references/variants/python-ut.md` | `references/code-quality/python.md` |

**啟動時 Read：**
1. `references/code-quality-core.md`（語言無關清單）
2. 對應的 variant reference
3. 對應的 code-quality reference

---

## 入口模式

### 被 control-flow 調用

接收 `FEATURE_FILE` 參數，直接進入重構流程。

### 獨立使用

詢問目標範圍（特定 Feature 或全域），確認綠燈後進入重構流程。

---

## 核心循環

```
1. 確認測試全數通過（起始綠燈）
2. 識別一個改善點（依 code-quality 規則優先級）
3. 執行小步驟重構
4. 重新測試 → 仍全通過？
   ├─ 是 → 回到 2
   └─ 否 → 還原，換另一個改善點
5. 無更多改善點 → 結束
```

### 測試命令

| 變體 | 指令 |
|-----|------|
| python (e2e/ut) | `behave ${PY_TEST_FEATURES_DIR}/ --tags=~@ignore` |
| java (e2e) | `mvn clean test -Dtest=RunCucumberTest -Dcucumber.filter.tags="not @ignore"` |

---

## 安全規則

1. **每步測試** — 每次小重構後立即執行測試，失敗立即還原
2. **一次一件事** — 不同時重構多個部分
3. **不改外部行為** — 重構不加新功能、不改 API 契約、不改 DB schema
4. **不強行重構** — 程式碼已清晰時保持原樣（YAGNI）
5. **禁止自動抽 helpers** — 除非使用者明確要求，否則不新增共用模組
6. **禁止跨檔搬動** — 優先在原檔案內做最小改善；跨檔需先徵詢
7. **三次以上再抽** — 重複兩次可接受，三次以上才抽取

---

## 品質規則集

詳見 `references/code-quality-core.md`（語言無關）。

核心面向：
1. **SOLID 原則** — S（單一職責）、O（開放封閉）、L（里氏替換）、I（介面隔離）、D（依賴反轉）
2. **DRY** — 消除重複，但不過度抽象
3. **架構分層** — API → Service → Repository → Model，各層職責分明
4. **命名清晰** — 函數名表達意圖，不用縮寫
5. **Step Definition 整理** — 檔案組織、import 排序、共用 helper 提取
6. **Meta 清理** — 移除 TODO 註解、保留業務註解
7. **日誌實踐** — 結構化 key=value、正確日誌等級

語言特有規則（Python logging、Java @Slf4j 等）在 code-quality reference 中。
變體特有工作流（兩階段、重構方向等）在 variant reference 中。

---

## 重構邊界

- 不加新功能
- 不改測試（除非重構測試程式碼本身）
- 不改 API 契約或 DB schema
- 不做效能優化（除非明顯問題）

## 完成條件

- [ ] 測試仍全數通過（零失敗、零 warnings）
- [ ] code-quality 規則主要面向已檢查
- [ ] 無殘留 TODO 註解（樣板階段遺留已清除）
- [ ] 測試輸出乾淨（無 deprecation notices）
