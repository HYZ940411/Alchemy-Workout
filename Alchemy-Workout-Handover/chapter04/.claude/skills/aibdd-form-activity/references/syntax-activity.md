# .activity 語法速查

完整語法見 `syntax.bnf`（版本 7 — 對齊 sf parser）。

**Id 規則（一條規則消除所有衝突）**：
- 純數字（`1`、`2`、`3`）→ 永遠是 `STEP`，全局唯一
- 數字 + 後綴（`2a`、`2a1`、`3a`）→ 永遠是 `DECISION` / `FORK`，強制帶後綴
- 後綴命名：字母與數字交替，編碼嵌套路徑（`2a` → `2a1` → `2a1a`）

**Guard 規則**：所有分支條件必須明確寫出字串，禁止 `_`。sf parser 支援 `else` 作為特殊 guard 值（`isElse = true`）。

**Loop-back**：
- `-> N`（純數字）= 跳回 `STEP:N`，重新執行整個步驟
- `-> Nx`（帶後綴）= 跳回 `DECISION:Nx`，直接重新評估條件（for-each / while）

**便條紙格式**：`# CiC(<CATEGORY>): <內容>`，寫在對應行末。僅 ACTOR / STEP / DECISION / BRANCH / PARALLEL 支援掛 CiC。

---

## 關鍵字一覽

| 關鍵字 | 用途 | @actor | label | {binding} | CiC |
|--------|------|--------|-------|-----------|-----|
| `[ACTIVITY]` | 流程標頭 | — | name（選用） | — | ✗ |
| `[ACTOR]` | Actor 宣告 | — | name（必要） | 選用 | ✓ |
| `[INITIAL]` | 起始節點 | — | — | — | ✗ |
| `[FINAL]` | 終止節點 | — | — | — | ✗ |
| `[STEP:id]` | 主線/路徑步驟 | 選用 | 選用 | 選用 | ✓ |
| `[DECISION:id]` | 條件分支 | — | description（選用） | — | ✓ |
| `[BRANCH:id:guard]` | 分支路徑 | 選用 | — | 選用 | ✓ |
| `[MERGE:id]` | 分支合流 | — | — | — | ✗ |
| `[FORK:id]` | 並行起點 | — | — | — | ✗ |
| `[PARALLEL:id]` | 並行路徑 | 選用 | — | 選用 | ✓ |
| `[JOIN:id]` | 並行合流 | — | — | — | ✗ |

---

## .activity 檔案結構

```
[ACTIVITY] <流程名稱>
[ACTOR] <Actor1> -> {specs/actors/<Actor1>.md}
[ACTOR] <Actor2>

[INITIAL]

[STEP:1] @<Actor> <label> {features/<domain>/<功能名>.feature}
[STEP:2] @<Actor> {features/<domain>/<功能名>.feature}  # CiC(ASM): ...
[DECISION:2a] <條件描述>                                 # CiC(AMB): ...
  [BRANCH:2a:<guard1>] @<Actor> {features/<domain>/<功能名>.feature}
  [BRANCH:2a:<guard2>] {specs/ui/<頁面名>.md}
[MERGE:2a]

[STEP:3] @<Actor> {features/<domain>/<功能名>.feature}
[FORK:3a]                                                # CiC(GAP): ...
  [PARALLEL:3a] @<Actor> {features/<domain>/<功能名>.feature}
  [PARALLEL:3a] @<Actor> {features/<domain>/<功能名>.feature}
[JOIN:3a]

[FINAL]
```

完整範例見 `examples/範例-複雜情境.activity`。

---

## STEP label 欄位

STEP 在 `@actor` 與 `{binding}` 之間可插入選用的 label 描述文字：

```
[STEP:1] @buyer 瀏覽商品 {features/order/瀏覽商品.feature}
[STEP:2] @buyer {features/order/結帳.feature}
```

sf parser regex: `[STEP:id] @actor label {path}`，其中 actor、label、path 皆為選用。

---

## 更新時的注意事項

解決便條紙時，定位 `# CiC(<CATEGORY>): ...` 標記並刪除。若澄清導致 STEP / DECISION / FORK 結構改變，更新對應行。
