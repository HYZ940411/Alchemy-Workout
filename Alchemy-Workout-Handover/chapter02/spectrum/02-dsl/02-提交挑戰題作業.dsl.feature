Feature: 提交挑戰題作業

  Background:
    Given 系統中有以下課程：
      | 課程 ID | 名稱 | 類型 | 旅程 ID | 章節 ID | 獎勵.經驗值 |
      | 1 | 物件導向基礎 | 影片課程 | 1 | 1 | 300 |
      | 2 | 設計模式問卷 | 問卷課程 | 1 | 1 | 50 |
      | 3 | 實作練習 | 挑戰題課程 | 1 | 1 | 200 |
    And 系統中有以下用戶：
      | 名稱 | 等級 | 經驗值 |
      | Alice | 1 | 0 |
    And 用戶 "Alice" 已訂閱旅程 1

  Rule: 提交挑戰題作業直接完成
    
    Example: 提交挑戰題作業成功
      Given 用戶 "Alice" 在課程 3 的狀態為 "進行中"
      When 用戶 "Alice" 提交課程 3 的挑戰題作業
      Then 操作成功
      And 用戶 "Alice" 在課程 3 的狀態應為 "已完成"
    
    Example: 無法提交非挑戰題課程的作業
      Given 用戶 "Alice" 在課程 1 的狀態為 "進行中"
      When 用戶 "Alice" 提交課程 1 的挑戰題作業
      Then 操作失敗
      And 用戶 "Alice" 在課程 1 的狀態應為 "進行中"
