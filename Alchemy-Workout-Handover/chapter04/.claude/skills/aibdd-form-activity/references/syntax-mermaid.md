# .mmd 語法規範

輸出格式為 Mermaid `flowchart TD`。業務語意（綁定路徑、Actor 宣告、便條紙）使用 `%%` 註解行承載，與視覺節點相鄰放置。

## 元資料註解規範（核心設計）

每個視覺節點的**上方**放置 `%%` 註解行，使用與 `.activity` **完全相同的 DSL 語法**：

```
%% [STEP:1] @Actor {features/domain/功能名.feature}
S1["@Actor<br/>功能名"]
```

**等價性保證**：提取所有 `%% ` 開頭的行、去掉前綴，即可得到等價的 `.activity` 格式。

## Node ID 命名規則

| 概念 | Node ID 格式 | Mermaid 形狀 |
|------|-------------|-------------|
| 起點 | `Start` | `(( ))` 小圓 |
| 終點 | `End` | `((( )))` 雙圓 |
| 主線步驟 `STEP:N` | `S{N}` | `["@Actor<br/>描述"]` 矩形 |
| 並行路徑內步驟 | `S{path-id}` | `["@Actor<br/>描述"]` 矩形 |
| 決策 `DECISION:id` | `D{id}` | `{"條件描述"}` 菱形 |
| 分支目標（有綁定） | `B{id}_{guard簡寫}` | `["@Actor<br/>描述"]` 矩形 |
| 分支目標（無綁定） | `B{id}_{guard簡寫}` | `["描述"]` 矩形 |
| 合流 `MERGE:id` | `M{id}` | `(( ))` 小圓 |
| 並行起點 `FORK:id` | `F{id}` | `[["並行"]]` 雙框矩形 |
| 並行路徑 `PARALLEL:id` | `P{id}_{n}` | `["@Actor<br/>描述"]` 矩形 |
| 並行合流 `JOIN:id` | `J{id}` | `(( ))` 小圓 |

**Id 規則（與 .activity 一致）**：
- 純數字（`1`、`2`、`3`）→ 永遠是 `STEP`，全局唯一
- 數字 + 後綴（`2a`、`2a1`、`3a`）→ 永遠是 `DECISION` / `FORK`，強制帶後綴
- 後綴命名：字母與數字交替，編碼嵌套路徑（`2a` → `2a1` → `2a1a`）

**Branch target Node ID 的 guard 簡寫**：使用簡短英文或拼音縮寫，保持可讀性與唯一性。中文 guard 文字放在邊標籤（`-- guard -->`）和節點標籤（`["..."]`）中。

## Guard 規則

邊的標籤（`-- guard -->`）為分支條件，必須明確寫出條件字串，禁止使用 `_`（else / 預設路徑不合法）。

## Loop-back

以邊直接指回目標節點，形成視覺上的迴路：
- `B{id}_{guard} --> S{N}` = 跳回 STEP:N，重新執行整個步驟
- `B{id}_{guard} --> D{Nx}` = 跳回 DECISION:Nx，直接重新評估條件

對應的 `%%` 元資料行使用 `-> N` 或 `-> Nx` 語法標記：

```
%% [BRANCH:4a:否 -> 3] @buyer {features/order/顯示付款失敗請重試.feature}
B4a_no["@buyer<br/>顯示付款失敗請重試"]
```

邊定義：

```
D4a -- 否 --> B4a_no
B4a_no --> S3
```

## 便條紙格式

以 `%%` 註解行掛在對應節點定義的**上方**：

```
%% CiC(ASM): 付款方式假設為信用卡...（完整內容）
%% [STEP:3] @buyer {features/order/選擇付款方式並確認.feature}
S3["@buyer<br/>選擇付款方式並確認"]
```

多行便條紙每行開頭都用 `%%`。

## 檔案結構（三段式）

```
%% ═══ 區段一：Activity 標頭與 Actor 宣告 ═══
%% [ACTIVITY] 流程名稱
%% [ACTOR] Actor1 -> {specs/actors/Actor1.md}
%% [ACTOR] Actor2 -> {specs/actors/Actor2.md}

flowchart TD

%% ═══ 區段二：節點定義（每個節點上方附 %% 元資料） ═══

    Start(( ))

    %% [STEP:1] @Actor1 {features/domain/功能名.feature}
    S1["@Actor1<br/>功能名"]

    %% [DECISION:1a] 條件描述
    D1a{"條件描述"}

    %% [BRANCH:1a:guard1] @Actor1 {features/domain/功能名.feature}
    B1a_g1["@Actor1<br/>功能名"]

    %% [MERGE:1a]
    M1a(( ))

    End((( )))

%% ═══ 區段三：邊（連線）定義 ═══

    Start --> S1
    S1 --> D1a
    D1a -- guard1 --> B1a_g1
    B1a_g1 --> M1a
    M1a --> End
```

完整範例見 `範例-複雜情境.mmd`。

---

## 更新時的注意事項

解決便條紙時，定位 `%%` 註解中的便條紙並刪除。若澄清導致節點 / 決策 / 並行結構改變，同時更新「節點定義」區段與「邊定義」區段。
