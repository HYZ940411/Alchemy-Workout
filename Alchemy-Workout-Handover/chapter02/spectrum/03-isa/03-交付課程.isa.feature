Feature: 交付課程

  Background:
    Given 準備一個課程, with table:
      | lesson_id | name | type | journey_id | chapter_id | reward.exp |
      | 1 | 物件導向基礎 | 2 | 1 | 1 | 300 |
      | 2 | 設計模式問卷 | 0 | 1 | 1 | 300 |
      | 3 | 實作練習 | 3 | 1 | 1 | 200 |
    And 準備一個用戶, with table:
      | >Alice.id | name | level | exp |
      | <id | Alice | 1 | 0 |
    And (UID="$Alice.id") 用戶訂閱旅程, call table:
      | journeyId |
      | 1 |

  Rule: 課程完成後才能交付，交付課程後獲得經驗值和升級
    
    Example: 成功交付已完成的影片課程
      Given 準備一個課程進度, with table:
        | userId | lessonId | status |
        | $Alice.id | 1 | COMPLETED |
      When (UID="$Alice.id") 交付課程, call table:
        | lessonId |
        | 1 |
      Then 回應 200, with table:
        | lessonId | status | reward.exp | reward.newLevel |
        | 1 | DELIVERED | 300 | 3 |
      And 驗證存在一個課程進度, with table:
        | userId | lessonId | status |
        | $Alice.id | 1 | DELIVERED |
        | &isNum | 1 | DELIVERED |
      And 驗證存在一個用戶, with table:
        | id | exp | level |
        | $Alice.id | 300 | 3 |
    
    Example: 無法交付未完成的課程
      Given 準備一個課程進度, with table:
        | userId | lessonId | status |
        | $Alice.id | 1 | IN_PROGRESS |
      When (UID="$Alice.id") 交付課程, call table:
        | lessonId |
        | 1 |
      Then 操作失敗
      And 驗證存在一個課程進度, with table:
        | userId | lessonId | status |
        | $Alice.id | 1 | IN_PROGRESS |
        | &isNum | 1 | IN_PROGRESS |
      And 驗證存在一個用戶, with table:
        | id | exp |
        | $Alice.id | 0 |
    
    Example: 無法重複交付課程
      Given 準備一個課程進度, with table:
        | userId | lessonId | status |
        | $Alice.id | 1 | COMPLETED |
      When (UID="$Alice.id") 交付課程, call table:
        | lessonId |
        | 1 |
      And (UID="$Alice.id") 交付課程, call table:
        | lessonId |
        | 1 |
      Then 操作失敗
      And 驗證存在一個課程進度, with table:
        | userId | lessonId | status |
        | $Alice.id | 1 | DELIVERED |
        | &isNum | 1 | DELIVERED |
      And 驗證存在一個用戶, with table:
        | id | exp |
        | $Alice.id | 300 |
    
    Example: 交付多個課程累積經驗值並多次升級
      Given 準備一個課程進度, with table:
        | userId | lessonId | status |
        | $Alice.id | 1 | COMPLETED |
      And 準備一個課程進度, with table:
        | userId | lessonId | status |
        | $Alice.id | 2 | COMPLETED |
      When (UID="$Alice.id") 交付課程, call table:
        | lessonId |
        | 1 |
      And (UID="$Alice.id") 交付課程, call table:
        | lessonId |
        | 2 |
      Then 回應 200, with table:
        | reward.exp | reward.newLevel | reward.levelUp |
        | 600 | 5 | true |
      And 驗證存在一個用戶, with table:
        | id | exp | level |
        | $Alice.id | 600 | 5 |
      And 驗證存在一個課程進度, with table:
        | userId | lessonId | status |
        | $Alice.id | 1 | DELIVERED |
        | &isNum | 1 | DELIVERED |
      And 驗證存在一個課程進度, with table:
        | userId | lessonId | status |
        | $Alice.id | 2 | DELIVERED |
        | &isNum | 2 | DELIVERED |
