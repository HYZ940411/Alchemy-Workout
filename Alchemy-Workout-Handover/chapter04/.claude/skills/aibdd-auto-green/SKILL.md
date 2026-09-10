---
name: aibdd-auto-green
description: >
  BDD 綠燈實作者。以 Red 階段產出的失敗測試為驅動，用最小增量迭代實作後端，
  直到所有測試通過。透過 arguments.yml 自動路由語言變體（Python E2E / Java E2E / Python UT）。
  當 /aibdd-auto-control-flow 呼叫綠燈階段，或使用者說「綠燈」「green」時觸發。
---

# 綠燈實作者

以失敗測試為驅動，迭代實作後端至所有測試通過。

## 變體路由

| tech_stack | test_strategy | 載入 | 實作目標 |
|-----------|---------------|------|---------|
| python | e2e | `references/variants/python-e2e.md` | FastAPI Schemas → Services → Controllers → Route 註冊 |
| java | e2e | `references/variants/java-e2e.md` | DTO → Service → Controller → Route 註冊 |
| python | ut | `references/variants/python-ut.md` | FakeRepository 方法體 → Service 業務邏輯 |

**啟動時 Read 對應的 variant reference。**

---

## 核心循環

```
while 測試未全部通過:
    1. 執行測試 → 讀取第一個失敗
    2. 分析失敗原因（404? 500? assertion error?）
    3. 寫最小增量程式碼修復該失敗
    4. 重新執行測試
    5. 若新失敗出現 → 回到 2
    6. 若全部通過 → 結束
```

### 失敗模式對照表（共用）

| 失敗模式 | 原因 | 修復方向 |
|---------|------|---------|
| HTTP 404 | Endpoint 未註冊 | 建立 Controller + 註冊路由 |
| HTTP 500 | 內部錯誤 | 檢查 Service/Repository 實作 |
| HTTP 400 | 驗證失敗 | 補齊 Schema/DTO 驗證 |
| HTTP 401 | 未授權 | 補齊 Auth middleware |
| Assertion Error | 回傳值不符預期 | 修正 Service 邏輯 |
| NotImplementedError | UT 方法體未實作 | 實作 FakeRepo/Service 方法體 |

### 最小增量原則

- 每次只修一個失敗
- 不預先實作其他測試還沒要求的功能
- 不做「順便」的重構（那是 Refactor 階段的事）

---

## Docker 環境檢查（E2E only）

與 Red 階段相同：確認 Docker daemon + PostgreSQL image。

## 完成條件

- [ ] 測試命令全數通過（零失敗）
- [ ] 未引入任何測試未要求的功能
