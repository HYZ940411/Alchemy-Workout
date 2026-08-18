# 釐清問題

在 AI 調整流程中，AI 是否視為執行 Command 的獨立 Actor？還是視為使用者 Command 的系統回應？

# 定位

流程：AI 訓練前調整流程、AI 訓練中調整流程（插入訓練紀錄流程循環）、AI 自動優化訓練流程
元素：Command：調整訓練 / 微調訓練強度 / 優化訓練強度；Actor：AI
細節：Actor 是人、系統、排程還是外部系統（B4）；觸發源（B5）。

# 多選題

| 選項 | 描述 |
|--------|-------------|
| A | AI 為獨立 Actor（外部系統），需標示其為跨系統邊界的來源 |
| B | AI 為系統內部元件，Actor 仍是使用者，AI 調整是使用者 Command 的 Postcondition |
| C | AI 訓練前 / 中調整的 Actor 是使用者；AI 自動優化的 Actor 是排程系統 |
| D | AI 為獨立 Actor，且需區分「AI 建議」與「系統套用」兩個不同 Actor |
| Short | 提供其他簡短答案（<=5 字） |

# 影響範圍

影響三條 AI 流程所有 Command 的 Actor 定義、AI 服務是否為外部系統（影響逾時與失敗處理）、以及「Actor 執行 Command 導致 Event」串聯句的成立。

# 優先級

High

# 解決結果

D″ — AI 為獨立 Actor，且不歸入「外部系統」，於 Actor 清單中另立為第五種。
AI 僅負責產出建議（AI 已微調訓練強度 / AI 已調整訓練 / AI 已優化訓練強度），
不執行套用；套用調整的 Actor 為系統。

# 矛盾裁決紀錄

本題答案推翻了第 17 題（`resolved/command/Actor_模型中各角色名稱的定義與統一.md`，選項 A′）
所確立的「全模型 Actor **共四種**，清單封閉」。

使用者裁決：**採 D″，Actor 清單擴為五種，並註明清單非封閉**。
被推翻的 resolved 檔案已同步更新，`00_全域規範.md` 的 Actor 清單亦已改寫。

# 連帶影響

- `rule/AI已微調訓練強度_AI回應逾時或失敗時的處理.md`：AI 既非外部系統，該題屬平台內部角色的失敗處理，不套用跨系統邊界的逾時策略。
- 「系統套用調整」目前無對應 Event，記錄於 `.clarify/pending-gaps.md` G13。

# 回寫位置

- `Event-Storming_事件風暴/00_全域規範.md` → Actor 清單擴為五種，新增 AI 一列與 2 條規則
- `Event-Storming_事件風暴/AI訓練前調整流程.md` → 新增 [串聯] 一行
- `Event-Storming_事件風暴/AI 訓練中調整流程（插入訓練紀錄流程循環）.md` → 新增 [串聯] 一行
- `Event-Storming_事件風暴/AI自動優化訓練流程.md` → 新增 [串聯] 一行

# 解決日期

2026-07-30
