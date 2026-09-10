# QA 測試分析指南

對每個操作，運用以下五種分析維度研判需要多少測試案例。

## (a) 等價類劃分（Equivalence Partitioning）

將輸入空間劃分為等價類，每類選一個代表值。

- 例：`需求分類` 有 3 個合法值（課程問題/技術問題/退費）→ 3 行 Examples
- 例：`姓名` 有 2 個等價類（非空 / 空）→ 各 1 行

## (b) 邊界值分析（Boundary Value Analysis）

在等價類的邊界上取值。

- 例：CSV 匯入筆數 = 1000（上限邊界）
- 例：進度 = 30%（自動晉升門檻邊界）
- 例：進度 = 100%（完課判定邊界）

## (c) 狀態轉移（State Transition）

操作前後的狀態變化，特別是依賴前置狀態的操作。

- 例：Stage = 已購課 → 手動晉升被拒 vs Stage = 已參與 → 手動晉升成功
- 例：學員存在 → 更新進度 vs 學員不存在 → 404 + Error Log

## (d) 組合覆蓋（Pairwise / Interaction）

多個參數同時變化時的交互效果。

- 例：篩選 Stage + 進度 + Journey 三個條件同時指定
- 例：CSV 中多筆資料混合合法與不合法

## (e) 錯誤推測（Error Guessing）

基於 domain 知識預判的易錯場景。

- 例：Email 格式合法但已存在（唯一性衝突）
- 例：Webhook 的 courseId 存在但 lessonId 不存在
- 例：同時觸發兩個自動晉升條件

## 分析原則

- **每一行 Example 都必須能回答：「你在驗證什麼等價類或邊界？」**
- **每一行 Example 都必須標註其前置狀態需求**——該測試案例需要哪些 Background 以外的 Given 步驟？前置狀態需求相同的行可以合併為 Scenario Outline，前置狀態需求不同的行必須拆為獨立 Example。
- 即使某些維度結論為「不適用」也要明確標註。
