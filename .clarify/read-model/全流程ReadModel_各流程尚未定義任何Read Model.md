# 釐清問題

全模型 28 條流程皆未定義任何 Read Model。應優先定義哪些 Read Model？定義的顆粒度為何（依畫面或依 Actor 決策點）？

# 定位

流程：全流程
元素：Read Model：全模型皆未定義（D6 檢查項全數 Missing）
細節：Read Model 識別（D6）；Read Model 支撐 Command（E4）。

# 多選題

| 選項 | 描述 |
|--------|-------------|
| A | 依 Actor 決策點定義：每個需要判斷的 Command 前對應一個 Read Model（如訓練前的課表檢視、購買前的餘額與庫存檢視） |
| B | 依畫面定義：首頁 / 訓練頁 / 社群頁 / 排行榜 / 商城 / 個人檔案 / 師徒頁 / 管理後台，每頁一個 Read Model |
| C | 先僅定義高頻決策點的 Read Model（訓練、簽到、排行榜、商城購買），其餘延後 |
| D | 延後至實作規劃階段再定義，本階段不建模 Read Model |
| Short | 提供其他簡短答案（<=5 字） |

# 影響範圍

影響 Read Model 層的建模策略與工作量、每個 Command 是否有對應的判斷依據（E4）、以及是否存在無人使用的過度設計。建議在 Aggregate 定案後再展開。

# 優先級

High
