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
