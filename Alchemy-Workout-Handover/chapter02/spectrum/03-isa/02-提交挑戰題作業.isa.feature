Feature: 提交挑戰題作業

  Background:
    Given 準備一個課程, with table:
      | lesson_id | name | type | journey_id | chapter_id | reward.exp |
      | 1 | 物件導向基礎 | 2 | 1 | 1 | 300 |
      | 2 | 設計模式問卷 | 0 | 1 | 1 | 50 |
      | 3 | 實作練習 | 3 | 1 | 1 | 200 |
    And 準備一個用戶, with table:
      | >Alice.id | name | level | exp |
      | <id | Alice | 1 | 0 |
    And (UID="$Alice.id") 用戶訂閱旅程, call table:
      | journeyId |
      | 1 |

  Rule: 提交挑戰題作業直接完成
    
    Example: 提交挑戰題作業成功
      Given 準備一個課程進度, with table:
        | userId | lessonId | status |
        | $Alice.id | 3 | IN_PROGRESS |
      When (UID="$Alice.id") 提交挑戰題作業, call table:
        | lessonId | files |
        | 3 | solution.java |
      Then 回應 200, with table:
        | lessonId | status | message |
        | 3 | COMPLETED | &isStr |
      And 驗證存在一個課程進度, with table:
        | userId | lessonId | status |
        | $Alice.id | 3 | COMPLETED |
        | &isNum | 3 | COMPLETED |
    
    Example: 無法提交非挑戰題課程的作業
      Given 準備一個課程進度, with table:
        | userId | lessonId | status |
        | $Alice.id | 1 | IN_PROGRESS |
      When (UID="$Alice.id") 提交挑戰題作業, call table:
        | lessonId | files |
        | 1 | solution.java |
      Then 操作失敗
      And 驗證存在一個課程進度, with table:
        | userId | lessonId | status |
        | $Alice.id | 1 | IN_PROGRESS |
        | &isNum | 1 | IN_PROGRESS |
