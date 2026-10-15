# Firestore Schema 設計方案（[BE-03] 交付文件）

> 2026-09-10 由 Claude Code 產出，人審核通過。作為 `[BE-04]`（Auth＋Firestore 實作）的依據。
> 事實來源仍是 `Event-Storming_事件風暴/`；本文與規格衝突處以規格為準。

## Context

專案目前完成度約 60%：前端 Flutter App 幾乎做完，但資料全部存在本機（單一 JSON 快照，透過 `Store.load()/save()/clear()`），後端完全沒做。

本方案對照 `Event-Storming_事件風暴/02_Aggregate定義.md`、`03_能力值.md`（規格，事實來源）與現有 `fitness-app/lib/` 程式碼結構（尤其 `data/store.dart`、`state/app_state_snapshot.dart`、`domain/*.dart`）設計而成，確保 Firestore 落地後、`BE-04` 轉換邏輯的心智負擔最小。設計過程中發現三處程式碼與規格不一致，以及一處研究階段的假設有誤，皆已對照原文核實並修正，詳見第 8 節。

---

## 0. 設計總原則

1. **規格優先**：本文與 `02_Aggregate定義.md`／`03_能力值.md` 衝突處，一律以規格為準。
2. **三大分區**：使用者私有資料 / 跨使用者關聯資料 / 平台公用唯讀資料——對應安全規則的三種待遇，也對應 `toSnapshot()` 現有「排除平台目錄與社群假資料」的既有邊界。
3. **能少一個 collection 就少一個**：小且有界的集合（商品規格、團隊成員 ≤5人）用內嵌陣列/Map；只有「會頻繁寫、需要獨立查詢、或本質上無界成長」的資料才拆 subcollection。
4. **快照不變 vs 現況可變分離**：訓練紀錄、獎勵發放紀錄、排行榜歷史一旦寫入即不可變；能力值、金幣餘額等「現況」欄位可變。這條邊界決定 `set(merge)` 還是只能 `create()` 一次。

---

## 1. 頂層 Collection 結構圖

```
── 使用者私有資料（僅擁有者本人可讀寫，經濟/信任類子路徑僅限 Cloud Functions 寫）──

users/{uid}                                   核心使用者文件（身分/身體/設定/處罰狀態等純量欄位）
├─ ability/state                                (單例) 六維點數現況：points/pending/trainedDims/decayTimers
├─ ability_history/{dayIndex}                   能力值逐日快照
├─ streaks/training                             (單例) 連續訓練：lastTrainedDate/streakDays/noticeStage
├─ streaks/checkin                              (單例) 連續簽到：4 欄位皆儲存（見 §2.4、§8-1）
├─ checkin_records/{yyyy-mm-dd}                 每日簽到紀錄（doc id＝簽到日期，天然去重＋永久保留）
├─ wallet/coins                                 (單例) 金幣餘額
├─ wallet/makeup_tickets                        (單例) 補簽券張數（上限 5）
├─ wallet/ai_credits                            (單例) AI 點數：monthly/permanent 現況
│   └─ ledger/{entryId}                         點數異動明細（append-only）
├─ session_plans/{sessionId}                    **本次訓練課表**（獨立 Aggregate，選課表時建立，見 §2.3、§8-4）
├─ workout_sessions/{sessionId}                  **訓練紀錄**（獨立 Aggregate，1:1 對應 session_plans，開始訓練時建立）
├─ custom_plans/{planId}                        自訂訓練（狀態機 draft→saved→published→…）
├─ custom_exercises/{exerciseId}                自建動作
├─ daily_tasks/{yyyy-mm-dd}                     當日任務指派（doc id 本身即冪等鍵）
├─ achievements/{category}#{threshold}          成就解鎖紀錄
├─ novice_task (單例) / return_tasks/{assignedAt}   新手任務／回歸任務紀錄
├─ mailbox/{mailId}                             獎勵信箱
├─ reward_grants/{grantId}                      獎勵發放紀錄（一經寫入不變）
├─ orders/{orderId}                             訂單（虛擬商品）
├─ membership（單例，**不存在＝從未訂閱過**，見 §2.13、§8-3）
├─ instructor (單例，僅 isInstructor=true 時存在)   教官聲望/專長/測驗結果
├─ ai_conversations/{conversationId}            AI 調整對話（永久保存）
│   └─ turns/{turnIndex}
├─ rank_score/current (單例)                     個人排行榜週/月累計分數現況
├─ violations_log/{id}                          累計違規明細
└─ notifications_inbox/{requestId}              等我回應的請求（168h 時限）

── 跨使用者關聯資料（無單一擁有者，或雙方共同擁有）──────────────────

posts/{postId}
├─ comments/{commentId}
└─ likes/{uid}                                  按讚（doc id＝uid，天然唯一）

follows/{followerId}_{followeeId}               關注關係（複合 ID）
blocks/{blockerId}_{blockedId}                  封鎖（複合 ID，不掛對話下）
reports/{reportId}                              檢舉／申訴

conversations/{conversationId}
└─ messages/{messageId}

teams/{teamId}
├─ members/{uid}
├─ invites/{uid}、applications/{uid}             168h 逾期
└─ score_periods/{periodId}
    └─ contributions/{uid}

mentor_bonds/{mentorId}_{apprenticeId}          師徒關係（狀態機 生效中↔已解除）
├─ tasks/{taskId}
└─ questions/{questionId}
mentor_applications/{applicationId}             168h 逾期
instructor_applications/{uid}                   狀態機 初審中→…→已通過/已駁回

leaderboard_history/{period}_{groupId}          一經寫入不可修改
leaderboards_current/{period}                   Read Model：延遲更新快取

admins/{adminId}                                需要 custom claim

── 平台公用唯讀資料（一般使用者唯讀，管理端／Cloud Functions 寫）────────

platform_config/{groupId}                       平台可調參數（單例文件，見 §2.14、§8-5 已擴充項目）
└─ change_log/{changeId}                        稽核紀錄

exercises/{exerciseId}                          動作庫
plans/{planId}                                  訓練計畫
achievement_defs/{achievementKey}
reward_defs/{rewardId}
daily_task_pool/{taskId}
novice_task_templates/{templateId}
products/{productId}
lookups/{listId}                                真正靜態的值域清單（健身目標/經驗/器材/教官專長，系統邊界外）

idempotency_markers/{jobKey}                    集中式冪等標記（見 §4 範例三）
```

---

## 2. 主要 Collection / Document 欄位設計

只列核心欄位，型別依現有 Dart 欄位對齊；enum 一律存 `.name` 字串；Timestamp 一律用 Firestore 原生型別。

### 2.1 `users/{uid}`（核心文件）

```json
{
  "displayName": "string", "email": "string|null",
  "bodyweightKg": 70.0, "heightCm": 175.0, "isMale": true,
  "registeredOn": "Timestamp", "metricUnits": true,
  "daysPerWeek": 4, "duration": "string", "commonGoal": "string",
  "experience": "string", "equipmentTier": "string", "ownedEquipment": ["string"],
  "totalExp": 1700, "totalWorkouts": 0, "totalWorkoutDays": 0,
  "lastTrainedDate": "Timestamp|null",
  "followTotal": 0, "followers": 0, "peakFollowerCount": 0,
  "abilityPublic": true, "overallGradePublic": true, "aiAutoOptimize": false,
  "accountStatus": "active|pending_deletion|deleted", "deletionRequestedAt": "Timestamp|null",
  "punishment": { "kind": "none|warning|communitySuspended|permanent", "expiresAt": "Timestamp|null" },
  "myViolations": 0,
  "agreedTermsVersion": "string", "mentorDisclaimerVersion": "string|null", "instructorDutyVersion": "string|null"
}
```

### 2.2 `users/{uid}/ability/state`（能力值現況，單例）

```json
{
  "points":  { "chest": 10, "back": 10, "legs": 30, "shoulders": 10, "arms": 10, "core": 30 },
  "pending": { "chest": 0, "back": 0, "legs": 0, "shoulders": 0, "arms": 0, "core": 0 },
  "trainedDims": ["chest", "legs"],
  "decayTimers": { "chest": { "lastTrainedDate": "Timestamp", "nextDecayAt": "Timestamp|null", "cumulative": 0, "floorReached": false } }
}
```

`overallPoints`／`majorGrade`／`overallGrade`／**耐力值**皆為衍生且不儲存（見 §5.2、§8-2）：六階門檻是平台可調參數，管理員一改門檻若儲存等級就要重算全平台使用者；耐力值則是「讀取時由組紀錄與該動作的歷史最佳估算 1RM 即時計算」，規格明文「不設任何 Aggregate 欄位」。

`users/{uid}/ability_history/{dayIndex}`：對應 `snapshots` Map，獨立成 subcollection 避免單文件無限長大。

### 2.3 本次訓練課表 + 訓練紀錄（**兩個獨立 Aggregate，1:1 關聯**）

規格明確將「本次訓練課表」與「訓練紀錄」列為兩個獨立 Aggregate：前者於**選擇課表當下**建立（因為 AI 訓練前調整發生在開始訓練之前），是「計畫」；後者於**開始訓練**時建立，`本次訓練課表 ID` 為其表頭欄位，是「實績」。兩者拆成兩份文件：

```
users/{uid}/session_plans/{sessionId}
{ "sourceType": "officialPlan|customPlan|blank",
  "sourcePlanId": "string|null",
  "content": [ { "exerciseId": "string", "name": "string", "isTimed": false,
                 "restSeconds": 90,
                 "planned": [ { "targetWeightKg": 60.0, "targetReps": 8 } ] } ],
  "totalPlannedSets": 12 }

users/{uid}/workout_sessions/{sessionId}
{ "sessionPlanId": "string",           // 對應 session_plans 文件 ID，1:1
  "status": "in_progress|completed|ended_early|interrupted",
  "startedAt": "Timestamp", "endedAt": "Timestamp|null",
  "totalVolumeKg": 0.0,                 // float 一位小數，僅重訓，結算時寫入
  "caloriesBurned": 0,                  // 重訓+有氧，2026-08-20 新增
  "completedSetCount": 0,
  "exercises": [
    { "exerciseId": "string", "name": "string", "isTimed": false,
      "sets": [ { "seq": 1, "weightKg": 60.0, "reps": 8, "durationSec": null,
                   "completedAt": "Timestamp|null", "cancelled": false } ] }
  ] }
```

組紀錄採內嵌陣列（比照商品/商品規格模式）：單場訓練通常 ≤10 動作 × ≤6 組，遠低於文件大小上限。`session_plans` 的 `content` 與來源課表脫鉤（快照，來源之後異動不回溯）；`workout_sessions.exercises` 訓練中只能新增（AI 調整整段覆寫），完成後 `status` 轉終止態即為不可變快照。

### 2.4 連續訓練／連續簽到

```
users/{uid}/streaks/training
{ "streakDays": 12, "lastTrainedDate": "Timestamp", "noticeStage": "none|d1|d1_5" }

users/{uid}/streaks/checkin
{ "streakDays": 12, "totalDays": 340, "longestStreak": 45, "lastCheckInDate": "Timestamp" }

users/{uid}/checkin_records/{yyyy-mm-dd}
{ "method": "real|makeup" }
```

依規格（2026-08-23 版本，已核對原文），連續簽到 4 欄位**皆為彙總值、皆儲存**（累計天數／歷史最長連續天數單調遞增，連續天數中斷歸零，補簽時以逐日回溯 `checkin_records` 重算寫回）——現行 App 程式碼目前只存 2 欄位、其餘用衍生 getter 推算，與規格不符，`BE-04` 需同步調整 `app_state.dart`（見 §8-1）。

### 2.5 `users/{uid}/wallet/ai_credits` + `ledger` 子集合

```
users/{uid}/wallet/ai_credits
{ "monthly": 20, "permanent": 3, "resetMonth": "2026-09" }

users/{uid}/wallet/ai_credits/ledger/{entryId}
{ "at": "Timestamp", "kind": "deduct|refund|monthlyGrant|purchase|gift",
  "delta": -1, "monthlyAfter": 19, "permanentAfter": 3, "source": "beforeTraining|null" }
```

### 2.6 任務與成就

```
users/{uid}/daily_tasks/{yyyy-mm-dd}
{ "tasks": [ { "name": "string", "sourceEvent": "string", "target": 3, "progress": 1, "claimed": false } ],
  "allTasksBonusGiven": false }

users/{uid}/achievements/{category}#{threshold}
{ "unlocked": true, "claimed": true, "unlockedAt": "Timestamp" }
```

`daily_tasks` 的 doc id 直接是「每日任務已重置」排程的冪等鍵（見 §4）。`achievements` doc id 沿用現有 `category#threshold` 邏輯——用索引的話成就表一改順序，已解鎖紀錄就會套到別的成就上。

### 2.7 `users/{uid}/mailbox/{mailId}`

```json
{ "source": "string", "at": "Timestamp", "claimed": false, "exp": 120, "coins": 300, "makeupTickets": 0, "aiCredits": 0 }
```

只存數額不存顯示文字——沿用現有設計理由（存文字曾在 v1→v2 造成獎勵靜默清空）。

### 2.8 貼文 / 留言 / 按讚

```
posts/{postId}
{ "authorUid": "string", "authorRank": 20, "text": "string", "images": ["url"], "at": "Timestamp",
  "attachedWorkoutSessionId": "string|null", "visibility": "public|followersOnly|private",
  "pendingReview": false, "deleted": false, "likeCount": 0,
  "edits": [ { "before": "string", "at": "Timestamp" } ] }

posts/{postId}/comments/{commentId}
{ "authorUid": "string", "text": "string", "at": "Timestamp", "deleted": false, "edits": [] }

posts/{postId}/likes/{uid}
{ "at": "Timestamp" }
```

`likeCount` 是儲存的衍生計數，由 Cloud Function 在 `likes/{uid}` 建立/刪除時以 transaction 做 `increment(±1)`；`likes` 子集合本身才是「誰按過讚」的唯一鍵真相來源。

### 2.9 關注 / 封鎖

```
follows/{followerId}_{followeeId}  { "followerId": "string", "followeeId": "string", "at": "Timestamp" }
blocks/{blockerId}_{blockedId}     { "blockerId": "string", "blockedId": "string", "at": "Timestamp" }
```

複合 ID 直接防止重複建立同一組關係，查詢皆為單欄位 `where`，Firestore 自動建索引。

### 2.10 團隊 + 團隊分數

```
teams/{teamId}
{ "name": "string", "isPublic": true, "capacity": 5, "peakSize": 5, "lockedGroupSize": 3 }
teams/{teamId}/members/{uid}          { "role": "leader|member", "joinedAt": "Timestamp" }
teams/{teamId}/score_periods/{periodId}
{ "periodStart": "Timestamp", "periodEnd": "Timestamp", "dailyScore": 0, "timedScore": 0 }
teams/{teamId}/score_periods/{periodId}/contributions/{uid}   { "amount": 0 }
```

`dailyScore` 沿用即時對 `contributions` 加總（3–5 人成本可接受，規格明確要求「結構上成立」）；全平台團隊排行榜另由 `leaderboards_current/{period}` 批次快照。

### 2.11 師徒關係 / 師徒任務

```
mentor_bonds/{mentorId}_{apprenticeId}
{ "state": "active|released", "releasedReason": null, "releasedAt": null, "bondedAt": "Timestamp", "recoverableUntil": "Timestamp|null" }
mentor_bonds/{mentorId}_{apprenticeId}/tasks/{taskId}
{ "title": "string", "detail": "string", "state": "assigned|done|claimed|voided", "rewardCoins": 15, "rating": null }
mentor_bonds/{mentorId}_{apprenticeId}/questions/{questionId}
{ "from": "apprentice|mentor", "text": "string", "at": "Timestamp", "answer": "string|null" }
```

複合 ID 讓「已解除 3 天內可恢復同一筆」直接對應同一份文件的狀態轉換，不需新建文件。

### 2.12 訂單 / 商品

```
products/{productId}
{ "name": "string", "images": ["url"], "aiCredits": 10,
  "specs": [ { "name": "string", "coinPrice": 300, "stock": 10 } ] }

users/{uid}/orders/{orderId}
{ "productId": "string", "productName": "string", "spec": "string", "qty": 1,
  "placedAt": "Timestamp", "coinPaid": 300, "cashPaid": 0, "aiCredits": 10,
  "state": "pendingPayment|paid|delivered|cancelled|failed" }
```

商品規格內嵌陣列。訂單放在使用者私有樹下。

> **2026-10-15 訂正**：商店只剩虛擬商品（使用者裁決移除實體商品）。原本的 `kind: physical|virtual`、
> `shipping`、`holdUntil`、`trackingNo`、`shipped`／`refunded` 狀態，以及「後台掃描逾時未付款訂單」的
> collection-group 查詢都不再需要。消耗品類虛擬商品仍有 `stock`（權限解鎖類不適用）。
> 目前商品與訂單**只存在假資料裡**，這一節描述的是上雲時的目標形狀，尚未落地。

### 2.13 會員權益（**無 `none` 儲存值**）

```json
{ "state": "active|cancelledPending|expired",
  "plan": "monthly|yearly", "expiresAt": "Timestamp|null", "autoRenew": true }
```

已核對規格原文：「生效狀態為三值，無『未生效』——會員權益 Aggregate 於『使用者已訂閱會員』時方才產生，在此之前該實體不存在，沒有一筆資料處於未生效」。所以 **`users/{uid}/membership` 文件不存在＝從未訂閱過**，不是存一個 `none` 狀態值；現有 Dart 程式碼 `MembershipState` enum 多出的 `none` 是客戶端對「文件不存在」的本地詮釋，`BE-04` 轉接層讀不到文件時應對映為 `none`，而不是把 `none` 寫進 Firestore（見 §8-3）。「已失效」非終止態，重新訂閱時沿用同一筆文件轉回生效中。

### 2.14 平台設定 `platform_config/{groupId}`（**擴充群組清單**）

```
platform_config/ability
{ "command": "設定能力值參數", "event": "管理員已設定能力值參數",
  "params": { "baseline": 27.6, "mapping": 23.6, "initial": 10, "cap": 999, "firstCap": 450,
              "catchUp": 0.8, "epley": 10, "decayPct": 0.05, "decayHours": 240, "floorDrop": 2,
              "recover": 0.5, "tier0": 99, "tier1": 249, "tier2": 449, "tier3": 649, "tier4": 849, "tier5": 999 } }

platform_config/{groupId}/change_log/{changeId}
{ "event": "string", "item": "string", "before": "string", "after": "string", "at": "Timestamp", "by": "adminUid" }
```

現有 `platform_config.dart` 只實作 11 組（ability/rank/reward/membership/instructorGate/exam/commerce/taskPool/team/account/makeup）。已核對規格：**通知設定／審核時限設定／內容過濾設定／防作弊設定**四份文件明文寫著「平台級可調參數，由管理員於後台維護」，性質與現有 11 組相同（需要 `SettingChange` 稽核紀錄），應一併補上，成為 `platform_config` 的第 12–15 組（見 §8-5）。

值域清單類設定（健身目標/經驗/器材/教官專長）規格明文「系統邊界外，不建 Command 與 Event」，維持放 `lookups/{listId}` 靜態文件，不建稽核 log。**檢舉理由設定**因帶有「是否啟用」「顯示順序」等可調欄位、且被〈內容過濾設定〉引用其「過濾器是否可命中」值，性質偏向可調參數而非純靜態清單，建議也歸入 `platform_config`（而非 `lookups`），交給 `BE-04` 開工前再次確認即可，不影響整體結構。

### 2.15 排行榜歷史紀錄

```json
{ "period": "2026-W37", "groupId": "string", "board": "weekly|monthly|team_daily|team_timed",
  "rankings": [ { "uid": "string", "score": 1200, "rank": 1 } ], "finalizedAt": "Timestamp" }
```

一經寫入不可修改（只允許 `create()`）；`rankings` 內存 uid 快照而非 reference，帳號刪除不影響歷史紀錄（規格明確要求）。

### 2.16 其餘 Aggregate 的歸類方式

- **教官聲望** → `users/{uid}/instructor`（單例），比照「金幣現況＋異動明細」模式；`avgRating`/`ratingCount` 由 Cloud Function 批次寫回（延遲更新）。
- **教官申請／師徒申請／團隊成員資格申請** → 比照 `mentor_applications/{id}` 模式：doc 本身即排程掃描目標，逾時判定用「第二類冪等鍵＝排程名稱+目標AggregateID」。
- **檢舉／申訴** → `reports/{reportId}`，狀態機比照訂單模式。
- **回歸任務／新手任務** → `users/{uid}/return_tasks`、`users/{uid}/novice_task`，讀平台 `novice_task_templates` 落地成使用者私有的一份指派紀錄。
- **AI 調整對話** → `users/{uid}/ai_conversations/{id}/turns/{n}`，append-only turns 子集合。

---

## 3. 命名規範

| 層級 | 規範 | 理由 |
|---|---|---|
| Collection 路徑 | **snake_case**（`workout_sessions`、`checkin_records`） | GCP/Firestore 生態主流慣例，Rules 語法可讀性較高 |
| 文件內欄位 | **camelCase，盡量逐字沿用 Dart 既有欄位名**（`bodyweightKg`、`lastTrainedDate`） | `toSnapshot()` 現在就是 camelCase，沿用可讓 `BE-04` 的轉接層接近 1:1 映射 |
| Enum 值 | 存 Dart enum 的 `.name` 字串 | 現有 `toSnapshot()` 已這樣做，零轉換成本 |
| Document ID | 依語意選擇：天然唯一鍵複合 ID（`follows/{a}_{b}`）／冪等鍵即 ID（`daily_tasks/{date}`）／自動 ID（`posts/{auto}`） | 見 §4 |
| Timestamp | 一律 Firestore 原生 `Timestamp`，不用 ISO 字串 | 原生支援排序比較，比字串解析安全 |

---

## 4. 冪等鍵與排程 Cloud Functions 落地方式

**範例一：每日任務已重置**（第一類，`排程名稱+週期起點+使用者ID`）
不另開冪等紀錄集合，`users/{uid}/daily_tasks/{yyyy-mm-dd}` 的 doc ID 本身即冪等鍵。Cloud Function 用 `docRef.create(data)`（非 `set`），文件已存在會擲出 `ALREADY_EXISTS`，捕捉後判定重複觸發、略過。

**範例二：訓練結算**（多 Aggregate 原子性連動）
用目標文件的狀態欄位做條件式 transaction：
```
transaction:
  session = get(users/{uid}/workout_sessions/{sessionId})
  if session.status != 'in_progress': abort（已結算過）
  session.status = 'completed'; session.endedAt = now
  ……同一 transaction 內一併寫入 ability/state、wallet/coins、reward_grants
```
與範例一的差異：訓練結算牽動多個 Aggregate（能力值/金幣/經驗值需原子性一起變動），單純「文件已存在即拒絕」不夠。

**範例三：單次訓練逾時／師徒申請逾期**（第二類，純排程掃描驅動）
目標文件已有 `status` 欄位可判斷，但排程掃描可能因 retry 重複觸發，高併發下仍有極小競態風險。用輕量標記集合：
```
idempotency_markers/{jobKey}   // jobKey = "session_timeout_{sessionId}"
{ "processedAt": Timestamp }
```
Function 先 `create()` 這個 marker，成功才繼續執行逾時邏輯；`create()` 失敗代表已處理過。

---

## 5. 反正規化決策清單

### 5.1 衍生但儲存

| 欄位 | 來源 | 為何儲存 |
|---|---|---|
| `users/{uid}.followers`／`peakFollowerCount` | `follows` collection 筆數 | 避免每次顯示個人頁都做 count query |
| `totalWorkouts`／`totalWorkoutDays` | `workout_sessions` 筆數/去重天數 | 階級/教官初審門檻判斷依據，需 O(1) 讀取 |
| `workout_sessions.totalVolumeKg/caloriesBurned` | 組紀錄與動作 MET 值算出 | 凍結歷史值：體重/相對強度係數之後調整，不回溯改變已完成訓練 |
| `wallet/ai_credits.monthly/permanent` | `ledger` 明細加總 | 避免每次判斷點數是否足夠都掃描全部明細 |
| `streaks/checkin.streakDays/longestStreak/totalDays` | `checkin_records` 逐日紀錄 | 規格明訂儲存；補簽時才重算寫回，避免每次顯示都逐日回溯查詢 |
| `posts/{id}.likeCount` | `likes` 子集合筆數 | 高頻顯示，不能每次都數子集合 |
| `instructorReputation`／`peakReputation` | 逐次評分事件 | 現況值即時 `increment()`；peak 單調遞增另存 |
| `leaderboard_history.rankings[].score/uid` | 結算當下即時分數 | 一經寫入永久不可變，帳號刪除也不影響，必須是快照非 reference |

### 5.2 衍生且不儲存

| 值 | 來源 | 為何不儲存 |
|---|---|---|
| 六維點數的主階/小節點、綜合能力等級 | `ability/state.points` + `platform_config/ability` 門檻 | 門檻調整後即時生效，儲存等於管理員一改門檻就要重算全平台 |
| **耐力值**（已核對 §8-2） | 組紀錄 + 該動作歷史最佳估算 1RM | 規格明文「不設任何 Aggregate 欄位，讀取時即時計算」；無退步機制、不掛成就、不進綜合能力等級，無任何下游需要持久化它 |
| 訓練進度條（已完成組數/總組數） | `workout_sessions.exercises[].sets` | 規格明訂衍生不儲存，訓練中頻繁變動 |
| 補簽頁日曆格狀態 | `checkin_records/{date}` 是否存在＋`method` | 純映射，儲存會產生第二份可能對不齊的事實 |
| 獎勵信箱顯示文字 | `exp/coins/makeupTickets/aiCredits` 數額 | 現有程式碼註解已明講：存文字導致過 v1→v2 顯示與實際不符的 bug |
| 帶徒上限 | `peakReputation` | 純函式，門檻為平台可調參數 |

### 5.3 延遲更新的快取（第三類）

`04_ReadModel清單.md` 標注「少數延遲更新」者，由排程 Cloud Function 定期批次寫入獨立 Read Model 集合，不即時 transaction：`leaderboards_current/{period}`（排行榜目前名次）、動作庫累積練習次數、教官評分彙總。

---

## 6. 與現有 `Store` 介面的銜接方式

現況：`Store.load()/save()/clear()` 是整份快照存讀，`AppState` 每次 `notifyListeners()` 後 300ms debounce 呼叫 `saveNow()` 整份覆寫。這個模型直接套 Firestore 有兩個結構性問題：部分資料（訓練歷史、簽到紀錄）無界成長，不該塞進一份整包讀寫的 Map；部分資料（金幣、能力值、訂單狀態）依規格必須經 Cloud Function 做原子性/防作弊變更，不能任由客戶端 debounce 覆寫。

**`load()`**：對「現況型」單例文件（`ability/state`、`streaks/*`、`wallet/*`、`membership`、`instructor`）平行 `Future.wait` 讀取，映射回 `toSnapshot()` 對應欄位群組。對「無界成長集合」（`workout_sessions`、`checkin_records`、`ability_history`）不再整包讀入記憶體，只讀近期一部分，完整歷史改由對應畫面另開分頁式查詢——**這是對現有「`AppState` 把 `history`/`checkInRecords` 當成完整記憶體陣列」假設的架構調整**，需要在 `BE-04` 啟動前跟前端畫面邏輯對齊。`load()` 回傳等同「沒存過」對應到 `users/{uid}` 根文件不存在。`StoreLoadException` 對應「讀取到的必要文件格式不符預期 schema」，一樣要丟例外走既有的「告知使用者、備份原檔」流程。

**`save()`**：`FirestoreStore` 內部維護「上次已寫入的快照」做淺層 diff，只對真變動的分組發 `set(merge:true)`；同一邏輯事件牽動的多份文件用 `WriteBatch` 包成原子寫入。**重要責任邊界**：debounce-save 這條路徑只該承載「單純本機狀態」（設定開關、UI 展示計數器），金幣/能力值/AI點數/訂單狀態/聲望這類跟金流防作弊有關的欄位，應在對應領域事件發生當下直接呼叫 Cloud Functions Callable Function 原子寫入，`AppState` 只是收到回應後更新本機記憶體，不是「先改記憶體、等 debounce 才悄悄寫入」。append-only 集合（`workout_sessions`、`mailbox`、`checkin_records`、`reward_grants`）完全不透過 `save()`，一律在事件發生當下 `add()`/`create()`。

**`clear()`**：規格明訂刪除時「一律硬刪除個資/訓練紀錄/能力值/AI對話等，但排行榜歷史紀錄不刪」，牽涉數十個 collection，客戶端逐一 `delete()` 容易漏、容易中途中斷留殘資料。建議實作成呼叫 Cloud Function（Callable），與「帳號已刪除」這個 Command/Event 共用同一套實作，不要為了「開發測試用的清除」另寫一套。

---

## 7. 安全規則方向

| 資料範圍 | 讀取 | 寫入 |
|---|---|---|
| `users/{uid}` 個人資料/設定類欄位 | 本人可讀；公開欄位建議另拆一份精簡 `public_profile` | 僅本人 |
| `users/{uid}` 經濟/信任類子路徑（`ability/*`、`wallet/*`、`streaks/*`、`orders/*`、`reward_grants/*`、`instructor`） | 僅本人可讀 | **一律拒絕 client 寫入**，只能 Cloud Functions（Admin SDK）寫 |
| `workout_sessions/{id}`（進行中） | 僅本人 | `status=='in_progress'` 可寫（只能新增 sets）；轉終止態後禁止任何 `update` |
| `posts/*`、`comments/*` | 依 `visibility` 判斷；`followersOnly`/`private` 建議另建 Read Model feed | 僅作者本人；`likeCount` 禁止客戶端直改 |
| `follows/*`、`blocks/*` | 登入即可讀，或限「與自己相關」 | 僅發起方本人建立/刪除自己那筆 |
| `teams/*`、`mentor_bonds/*` | 隊員/師徒雙方可讀 | 狀態轉換一律走 Callable Function（涉及名額/冷卻期等跨文件不變條件） |
| `conversations/*`、`messages/*` | 僅 `participants` 內兩人 | 訊息一經發送不可刪除不可編輯（規格明訂）→ `allow update, delete: if false` |
| 平台公用資料（`exercises`、`plans`、`platform_config`、`products`、`lookups` 等） | 已登入使用者皆可讀 | client 一律拒絕；管理端經 custom claim 的 Callable Function 或服務帳號寫入 |
| `admins/{adminId}` | 僅本人或更高權限管理員 | 一般使用者不可讀寫；新管理員任命走額外審核流程，不靠 Rules 表達治理邏輯 |
| `leaderboard_history/*` | 已登入使用者可讀 | `allow create` 僅 Cloud Function；`update`/`delete` 永久禁止 |

custom claim（`request.auth.token.admin == true`）區分管理員/一般使用者；經濟與信任相關寫入一律收斂到 Cloud Functions，Rules 只負責讀取範圍與防直改，複雜業務不變條件留給 Cloud Functions 應用層驗證。

---

## 8. 已核對並修正的落差

以下五點原本標記「待核對」，已逐字比對 `02_Aggregate定義.md`／`03_能力值.md` 原文，結論與修正如下：

1. **連續簽到 Aggregate 欄位數**：規格（2026-08-23 版本）明文 4 欄位皆為儲存的彙總值，本方案 §2.4 已依此設計。現行 `app_state_snapshot.dart` 只存 2 欄位、其餘用衍生 getter，**與規格不符**——這不是本次 schema 設計的問題，而是現有 Dart 程式碼尚未跟上規格更新，`BE-04` 實作時需要一併同步調整 `app_state.dart`，這點會列入 `BE-04` 的工作範圍。

2. **耐力值**：已核對 `03_能力值.md`，確認為規格明訂的**衍生值、不儲存**概念（「耐力值不設任何 Aggregate 欄位，於讀取時由組紀錄與該動作的歷史最佳估算 1RM 即時計算」），目前尚未落地到 `lib/domain/ability.dart`。本方案 §5.2 已將其列入「衍生不儲存」清單，不需要新增任何 Firestore 欄位；公式實作是 `BE-04`／前端邏輯的工作，不影響 schema。

3. **會員權益狀態值域**：規格明文「生效狀態為三值，無『未生效』」，現有 Dart `MembershipState` enum 多出的 `none` 是客戶端對「尚未訂閱過」的本地詮釋，不是 Firestore 該儲存的狀態值。**本方案 §2.13**：`users/{uid}/membership` 文件不存在即代表從未訂閱過，只有 3 個狀態值會被實際寫入文件。

4. **本次訓練課表／訓練紀錄的邊界**：已核對規格原文，兩者是**明確分屬兩個獨立 Aggregate**、以「本次訓練課表 ID」欄位建立 1:1 關聯（前者於選課表時建立，因為 AI 訓練前調整發生在開始訓練之前；後者於開始訓練時才建立）。**本方案 §2.3** 拆成 `session_plans/{sessionId}` 與 `workout_sessions/{sessionId}` 兩個 collection。

5. **`platform_config` 群組清單**：已核對規格，確認〈通知設定〉〈審核時限設定〉〈內容過濾設定〉〈防作弊設定〉四份 Aggregate 皆明文「平台級可調參數，由管理員於後台維護」，與現有 11 組性質相同，應一併補上成為第 12–15 組。**本方案 §2.14** 已擴充。〈檢舉理由設定〉因帶有可調欄位，建議一併歸入 `platform_config` 而非純靜態 `lookups`，此點影響小，留給 `BE-04` 開工前最終確認即可。

---

## 9. 本次設計刻意不處理的部分（留給 BE-04）

- Firestore 複合索引清單（`firestore.indexes.json`）——需依 `04_ReadModel清單.md` 35 個 Read Model 的實際查詢語句逐一列出。
- Cloud Functions 觸發器技術選型（Firestore trigger / Scheduled / Callable）、重試與 dead-letter 策略。
- Security Rules 完整語法與 Rules Unit Test。
- `tools/import_exercises.py` 等既有 CSV 匯入腳本如何改造成寫入 Firestore。
- 讀寫成本/計費估算，以及 `checkin_records`／`workout_sessions` 這類永久保留資料未來是否需要冷資料歸檔。

---

## 10. 實際落地現況（2026-09-25）

> **第 1–9 節是 2026-09-10 的設計方案，不是現況。** 這一節記的是
> **線上真的存在的東西**。兩者不一致時以本節為準，並在下面註明為什麼偏離。
>
> 判準很簡單：**`fitness-app/firestore.rules` 有 `match` 區塊的才是真的存在**，
> 因為最後一條規則是 `match /{document=**} { allow read, write: if false; }`
> —— 沒有對應區塊的路徑，客戶端一個位元都讀寫不了。

### 已上線的頂層 collection

| 路徑 | 誰讀得到 | 誰寫得動 | 批次 |
|---|---|---|---|
| `users/{uid}/**` | 本人 | 本人 | `[BE-04]` |
| `public_profiles/{uid}` | 所有登入者 | 本人 | `[BE-11]` 批 1 |
| `follows/{followerUid}_{followeeUid}` | 所有登入者 | 關注者本人 | `[BE-11]` 批 2 |
| `posts/{postId}` ＋ `comments`／`likes` | 所有登入者 | 作者、按讚者、**管理員（下架）** | `[BE-11]` 批 3 |
| `teams/{teamId}` ＋ `requests` | 所有登入者 | 隊員（＋持有邀請者可自行入隊） | `[BE-11]` 批 4 |
| `conversations/{convId}` ＋ `messages` | 對話的兩人 | 對話的兩人（訊息只能建，已讀例外） | `[BE-11]` 批 5 |
| `mentor_bonds/{bondId}` ＋ `tasks`／`questions` | 當事兩人 | 當事兩人 | `[BE-11]` 批 6 |
| `mentor_requests/{requestId}` | 收件與寄件者 | 寄件者建、兩者皆可刪 | `[BE-11]` 批 6 |
| `reports/{targetKey}__{reporterUid}` | **管理員** | 檢舉者建、管理員裁決 | `[BE-13]` |
| `violations/{uid}` | 本人與管理員 | **僅管理員** | `[BE-13]` |
| `punishments/{uid}` | 本人與管理員 | 管理員；**本人僅限申訴那兩個欄位** | `[BE-13]` |
| `exercises`／`plans`／`platform_config`／`achievement_defs`／`daily_task_pool` | 所有登入者 | 管理員（custom claim） | `[BE-12]` |

### 與第 1–9 節的偏離，以及理由

**① `public_profiles/{uid}` 是後來才有的，原設計沒有它。**
原設計把階級、能力值等等留在 `users/{uid}`。但**安全規則的粒度是文件，
不是欄位** —— 「有些欄位公開」唯一可靠的做法就是把它們拆成另一份文件。
身高體重、生日、電子郵件、處罰狀態、違規次數全部留在只有本人可讀的那棵樹。

**② 累計違規次數**不在 `users/{uid}/violations_log/{id}`（原設計 §1 的位置），
**而在頂層 `violations/{uid}`**。
原設計那個位置**是錯的**：`users/{uid}/**` 的規則是「本人全權讀寫」，
而這個數字決定階梯累犯制的處罰級距 —— **當事人自己就能清掉**。
`public_profiles/{uid}` 同樣不行（本人可寫）。所以另開一份：管理員可寫、
當事人唯讀。當事人要讀得到，因為處罰畫面要告訴他這是第幾次。

**③ 處罰狀態**同理。原設計寫在 `users/{uid}` 的純量欄位裡（§1「處罰狀態等」），
理由與 ② 完全相同：被罰的人自己就能解除。現在在 `punishments/{uid}`。
**唯一的例外是申訴**——那是當事人發起的，所以他改得動 `appealed` 與
`appealState`，但只有這兩個（規則用 `affectedKeys().hasOnly([...])` 限住，
與貼文 `likeCount` 同一個手法）。少了那層，他就能把自己的處罰種類改成「警告」。

**④ 管理員可以改別人的貼文與留言**（只為了下架）。
原設計的 posts 規則只允許作者。但檢舉成立要下架違規內容，而那是**別人的**
貼文 —— 少了這一條，管理員按下「成立」畫面上內容消失了，雲端一個位元
都沒動，其他人照樣看得到。仍然只能軟刪（`deleted` 欄位），硬刪永遠 `false`：
貼文可被檢舉，硬刪會讓案件失去證據。

**⑤ collection group 查詢需要自己的規則區塊。**
`match /teams/{teamId}/requests/{targetUid}` **管不到** `collectionGroup('requests')`
—— 規則引擎眼中那是另一條帶遞迴萬用字元的路徑。少了
`match /{path=**}/requests/{targetUid}`，「誰邀我入隊」一律 PERMISSION_DENIED。

### 還沒上雲的（後台相關）

- **申訴**：`fileAppeal()` 只把案件加進本機 `appeals`，雲端沒有集合 ——
  使用者申訴了，管理員看不到。
- **教官審核**：`instructorCases` 同樣只在本機。
- **訂單與商品**：整個商城都在本機。**使用者裁決跳過**（2026-09-25）——
  那不是補讀取路徑，是從零建一套。
- **訓練體驗評分**：存在 `users/{uid}` 的存檔裡，管理員讀不到（`[BE-18]`）。

### 查證方式

不要相信這一節（也不要相信我的記憶）—— **去讀 `fitness-app/firestore.rules`**，
那是唯一會被 Firebase 真的執行的東西。索引看 `fitness-app/firestore.indexes.json`，
而 `test/cloud_gaps_test.dart` 會在新增複合查詢卻沒宣告索引時失敗。

---

### 關鍵參考檔案

- `fitness-app/lib/data/store.dart`
- `fitness-app/lib/state/app_state_snapshot.dart`
- `fitness-app/lib/state/app_state.dart`
- `fitness-app/lib/domain/ability.dart`、`commerce.dart`、`community.dart`、`platform_config.dart`
- `Event-Storming_事件風暴/02_Aggregate定義.md`、`03_能力值.md`
