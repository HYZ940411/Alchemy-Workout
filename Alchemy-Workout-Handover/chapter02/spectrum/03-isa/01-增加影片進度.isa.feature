Feature: 增加影片進度

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

  Rule: 影片進度必須單調遞增
    
    Example: 成功增加影片進度
      Given 準備一個課程進度, with table:
        | userId | lessonId | progress | status |
        | $Alice.id | 1 | 70 | IN_PROGRESS |
      When (UID="$Alice.id") 更新課程影片進度, call table:
        | lessonId | progress |
        | 1 | 80 |
      Then 回應 200, with table:
        | lessonId | progress | status |
        | 1 | 80 | IN_PROGRESS |
      And 驗證存在一個課程進度, with table:
        | userId | lessonId | progress | status |
        | $Alice.id | 1 | 80 | IN_PROGRESS |
        | &isNum | 1 | 80 | IN_PROGRESS |
    
    Example: 進度不可倒退
      Given 準備一個課程進度, with table:
        | userId | lessonId | progress | status |
        | $Alice.id | 1 | 70 | IN_PROGRESS |
      When (UID="$Alice.id") 更新課程影片進度, call table:
        | lessonId | progress |
        | 1 | 60 |
      Then 操作失敗
      And 驗證存在一個課程進度, with table:
        | userId | lessonId | progress | status |
        | $Alice.id | 1 | 70 | IN_PROGRESS |
        | &isNum | 1 | 70 | IN_PROGRESS |
    
    Example: 相同進度值的更新應被接受但不改變狀態
      Given 準備一個課程進度, with table:
        | userId | lessonId | progress | status |
        | $Alice.id | 1 | 70 | IN_PROGRESS |
      When (UID="$Alice.id") 更新課程影片進度, call table:
        | lessonId | progress |
        | 1 | 70 |
      Then 回應 200, with table:
        | lessonId | progress | status |
        | 1 | 70 | IN_PROGRESS |
      And 驗證存在一個課程進度, with table:
        | userId | lessonId | progress | status |
        | $Alice.id | 1 | 70 | IN_PROGRESS |
        | &isNum | 1 | 70 | IN_PROGRESS |
  
  Rule: 進度值必須在 0-100% 之間
    
    Scenario Outline: 有效範圍內的進度值可以更新
      Given 準備一個課程進度, with table:
        | userId | lessonId | progress | status |
        | $Alice.id | 1 | 50 | IN_PROGRESS |
      When (UID="$Alice.id") 更新課程影片進度, call table:
        | lessonId | progress |
        | 1 | <新進度> |
      Then 回應 200, with table:
        | lessonId | progress | status |
        | 1 | <新進度> | <預期狀態> |
      And 驗證存在一個課程進度, with table:
        | userId | lessonId | progress | status |
        | $Alice.id | 1 | <新進度> | <預期狀態> |
        | &isNum | 1 | <新進度> | <預期狀態> |
      
      Examples:
        | 新進度 | 預期狀態 |
        | 60 | IN_PROGRESS |
        | 100 | COMPLETED |
        | 51 | IN_PROGRESS |
    
    Scenario Outline: 超出範圍的進度值無法更新
      Given 準備一個課程進度, with table:
        | userId | lessonId | progress | status |
        | $Alice.id | 1 | 50 | IN_PROGRESS |
      When (UID="$Alice.id") 更新課程影片進度, call table:
        | lessonId | progress |
        | 1 | <新進度> |
      Then 操作失敗
      And 驗證存在一個課程進度, with table:
        | userId | lessonId | progress | status |
        | $Alice.id | 1 | 50 | IN_PROGRESS |
        | &isNum | 1 | 50 | IN_PROGRESS |
      
      Examples:
        | 新進度 |
        | 101 |
        | -10 |
  
  Rule: 觀看至 100% 則課程完成
    
    Example: 影片進度達到 100% 時課程自動完成
      Given 準備一個課程進度, with table:
        | userId | lessonId | progress | status |
        | $Alice.id | 1 | 90 | IN_PROGRESS |
      When (UID="$Alice.id") 更新課程影片進度, call table:
        | lessonId | progress |
        | 1 | 100 |
      Then 回應 200, with table:
        | lessonId | progress | status |
        | 1 | 100 | COMPLETED |
      And 驗證存在一個課程進度, with table:
        | userId | lessonId | progress | status |
        | $Alice.id | 1 | 100 | COMPLETED |
        | &isNum | 1 | 100 | COMPLETED |
  
  Rule: 已交付的課程仍可更新進度，但狀態不變
    
    Example: 已交付的課程更新進度不改變狀態
      Given 準備一個課程進度, with table:
        | userId | lessonId | progress | status |
        | $Alice.id | 1 | 100 | DELIVERED |
      When (UID="$Alice.id") 更新課程影片進度, call table:
        | lessonId | progress |
        | 1 | 100 |
      Then 回應 200, with table:
        | lessonId | progress | status |
        | 1 | 100 | DELIVERED |
      And 驗證存在一個課程進度, with table:
        | userId | lessonId | progress | status |
        | $Alice.id | 1 | 100 | DELIVERED |
        | &isNum | 1 | 100 | DELIVERED |
