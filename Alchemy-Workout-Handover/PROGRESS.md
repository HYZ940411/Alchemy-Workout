# 健金術 Alchemy Workout — 進度與交接

最後更新：2026-09-10

這份文件同時給**接手的人**與**接手者的 Claude Code** 看。
第 4 節是可勾選的待辦清單，開頭有更新規則，請照著改。

---

## 1. 這是什麼

<!-- 唯讀，勿改 -->

一個健身 App：把訓練轉成看得見的**六維能力值**，外加階級、成就、排行榜、
師徒制與團隊。前端用 Flutter，跨 iOS／Android／Web／macOS。

**事實來源是 `Event-Storming_事件風暴/`**，不是程式碼。那 37 份文件定義了所有
Command、Event、Aggregate、不變條件與已定案的決策。程式碼與文件不一致時，
**以文件為準**；真的覺得文件錯了，先問人，不要自己改文件。

**目前完成度：約 60%。前端幾乎做完，後端一行都沒有。**

`fitness-app/pubspec.yaml` 只有三個依賴（`cupertino_icons`、`path_provider`、`web`）
—— 沒有 Firebase、沒有 http。`系統架構` 那份文件描述的 Firebase + Cloud Functions
+ Gemini + RAG 全部尚未實作。**那份文件寫的是目標，不是現況。**

---

## 2. 現在跑得起來嗎

<!-- 唯讀，勿改 -->

| 平台 | 狀態 | 怎麼跑 |
|---|---|---|
| **macOS** | 可用，已建置 | 直接開 repo 根目錄的 `健金術.app` |
| **Web** | 可用，僅內網 | `cd fitness-app/build/web && python3 -m http.server 8099` |
| **Android** | 有 APK（2026-09-03，較舊） | 根目錄 `健金術-arm64.apk` |
| **iOS** | **不能跑** | 未簽章，`security find-identity -v -p codesigning` 回報 0 個憑證 |

開發環境：**Flutter 3.44.1 stable**、Dart SDK `^3.12.1`。
`pubspec.lock` 已進版控 —— 版本漂移會讓上千個測試一起紅，先確認版本再查 bug。

> **專案路徑不可含中文（或任何非 ASCII 字元）。**
> 含中文時 `flutter analyze` 會直接崩潰：
> `FormatException: Unterminated string` —— 分析伺服器把路徑百分比編碼後，
> LSP 的 Content-Length 算錯，JSON 被截斷。這與程式碼無關，換成純 ASCII
> 路徑即恢復正常。2026-09-10 實測於 Flutter 3.44.1。

驗證指令（都在 `fitness-app/` 底下跑）：

```bash
flutter analyze                       # 應該完全乾淨
flutter test --timeout 90s            # 應為 1,212 passed
flutter test --platform chrome test/web_smoke_test.dart test/store_web_test.dart
                                      # 應為 17 passed（需要 Chrome）
./tools/build_web.sh                  # Web 建置，見第 6 節第 8 條
flutter build macos --release
```

---

## 3. 完成度總覽

<!-- 唯讀，勿改 -->

對照 `系統架構` 的三階段：

| 階段 | 項目 | 狀態 |
|---|---|---|
| 一 | Flutter 跨平台開發 | ✅ |
| 一 | 500+ 動作結構化資料庫 | ✅ 527 個動作，含中譯教學 |
| 一 | 本地緩存機制 | ✅ 原子寫入、300ms 防抖、載入前擋寫、存檔版本控管 |
| 一 | 八角框架遊戲化 | ✅ 階級／經驗／金幣／成就／四個排行榜／簽到／任務／能力值退步 |
| 一 | **FlutterFire 串接 Firebase** | ❌ 完全未做 |
| 一 | **連網後自動同步** | ❌ 只有本地那一半 |
| 二 | 動態權重運算引擎 | ⚠️ 已實作（Epley 1RM + DOTS + 節點制），**但跑在裝置上** |
| 二 | 遊戲化視覺（雷達圖等） | ✅ |
| 二 | 師徒與社群系統 | ⚠️ 畫面與規則完整，**但只有一位使用者**（見第 5 節） |
| 二 | **Cloud Functions 部署** | ❌ |
| 二 | **FCM 推播** | ❌ 推播規則已實作並測過，只差真的送出去 |
| 三 | AI 訓練調整 | ⚠️ 介面／扣點／失敗退點都做好，**但背後是本地規則引擎，不是 Gemini** |
| 三 | **Gemini API** | ❌ |
| 三 | **RAG 接地** | ❌ 且不建議做（527 個動作直接放進 prompt 就好） |
| 三 | **App Check + Secret Manager** | ❌ |

規模參考：`lib/` 45,169 行、129 個 Dart 檔、約 80 個畫面；
`test/` 18,098 行、89 個測試檔。

---

## 4. 待辦清單

<!-- 可編輯 -->

### 更新規則（這是給 Claude Code 的指令，請嚴格遵守）

狀態只有三種，**不得自創**：

```
- [ ] 【CC】[XX-00] 任務描述                    未開始
- [~] 【CC】[XX-00] 任務描述                    進行中
- [x] 【CC】[XX-00] 任務描述 ✅2026-09-10        完成
```

（上面是**格式範例**，`XX-00` 不是真的任務。真任務從下面的 A 段開始。）

1. 每項有**穩定編號**（`BE-` 後端／`DEP-` 部署／`QA-` 檢查）。
   **編號永不重用、永不重排** —— 請用編號定位，不要用行號。
2. 完成時**只准在行尾追加日期**，不得改寫任務文字。
3. **不得刪除任務。** 作廢請移到本節末尾的「已放棄」並附理由。
4. **不得自行勾選【人】的項目。** 那些需要帳號、付費或實體裝置，
   你做不到。最多把它標成 `⏸ 等待人工`。
5. 新任務往該段末尾加，編號接續，附日期。
6. 每完成一項就更新，不要累積到最後。

責任標記：

- **【人】** 只有人做得到 —— 帳號、付費、簽章、發佈、不可逆刪除、商業判斷
- **【CC】** 可整包交給 Claude Code
- **【人→CC】** 人先解鎖前置條件，之後交給 Claude Code

---

### A. 串後端

> 使用者選定的第一優先。估 2–3 個月全職。
> 這一項做完會一起解掉：沒有帳號、只有一個使用者、分數在客戶端算、AI 不是真的 AI。

- [x] 【人】`[BE-01]` 裝 Node.js 與 `firebase-tools`，執行 `firebase login` ✅2026-09-10
- [~] 【人】`[BE-02]` 建立 Firebase 專案，**並在 GCP Console 設預算警示**
      （查詢寫法錯會在一天內燒光免費額度，而且不會壞、只會開始收費）
      —— 專案已建立（Project ID: `alchemy-workout`），預算警示延後到 `BE-10`
- [x] 【CC】`[BE-03]` Firestore 資料模型設計 —— **先進 Plan 模式給人審再動手**。
      這是唯一「做錯要整個重來」的項目：Firestore 是 NoSQL，schema 錯了等於資料遷移 ✅2026-09-10
      → 方案見 `Firestore-Schema設計.md`
- [x] 【CC】`[BE-04]` Auth ＋ Firestore 實作。換掉 `Store` 介面的實作即可，
      `AppState` 應該一行都不用改 —— `lib/data/store.dart` 的條件匯入就是為這件事存在 ✅2026-09-11
      → 分支 `wip/be-04-auth-firestore`。Google 登入、資料落地 Firestore、
      登出／重新登入資料完整，皆已端到端驗證；`AppState` 確實一行未改。
      **僅涵蓋使用者私有資料**，跨使用者與平台公用資料見 `[BE-11]`／`[BE-12]`
- [x] 【CC】`[BE-05]` 盤點加後端後會失效的測試，決定 mock 邊界
      （目前 1,212 個測試全部跑在無網路的假資料上） ✅2026-09-11
      → 結論：**一個都沒失效**。`FitnessApp` 新增的 `auth` 參數預設為空值，
      既有測試不傳它就完全走原路徑。mock 邊界定為 `fake_cloud_firestore`
      （記憶體版，不起 emulator），與既有「測試不碰網路」的哲學一致。
      現為 1,232 passed
- [ ] 【CC】`[BE-06]` FCM 推播。規則（同日總量上限、優先序由低至高捨棄、四個等級）
      **都已實作並測過**，只差真的送出去 —— 投資報酬最高的一項
- [ ] 【CC】`[BE-07]` 評分邏輯搬上 Cloud Functions。
      **務必保持只有一份實作**（見第 6 節第 3 條）—— 移植成兩份是這個專案最可能踩的坑
- [ ] 【CC】`[BE-08]` 接 Gemini API 取代本地規則引擎。
      對話介面、扣點、失敗退點、重試都已做好，換掉後端即可
- [ ] 【人→CC】`[BE-09]` App Check ＋ Secret Manager。
      **若先做手機簡訊驗證，這項要提前** —— 簡訊被刷是真的會付錢
- [ ] 【人】`[BE-10]` 升級 Blaze 方案並在 GCP Console 設定預算警示。
      **`BE-07`（Cloud Functions）開工前必須做完**——`BE-03`／`BE-04` 用免費方案（Spark）
      即可，暫不需要 Blaze，故意延後以避免提前綁信用卡曝險
- [x] 【CC】`[BE-11]` 跨使用者資料上雲：貼文／留言／按讚、關注、團隊、師徒、
      私訊、檢舉申訴。collection 結構 `Firestore-Schema設計.md` 第 1 節已設計好。
      **這項不做，事件風暴裡約一半的流程永遠只有一個人、跑不起來**
      （目前靠「我的 → 流程示範 → 模擬對方」控制台代打）
      → **分四批執行**。批次 1（公開檔案 `public_profiles`，身分層）程式碼完成、**未驗證**；
      批次 2（關注）✅2026-09-13 驗證通過（1,271 passed）；
      批次 3（貼文／留言／按讚）✅2026-09-13 驗證通過（1,287 passed）；
      批次 4（團隊）✅2026-09-13 驗證通過（1,306 passed）；
      批次 5（私訊）✅2026-09-13 驗證通過（1,320 passed）；
      批次 6（師徒）✅2026-09-14 驗證通過（1,340 passed）。
      **六批的資料層與測試全部完成並驗證** ✅2026-09-14（1,340 passed）。
      接線由 `[BE-14]` 完成（師徒教官側除外，見 `[BE-15]`）。
      **檢舉／申訴移出 `BE-11`** —— 那是管理端功能，而目前沒有任何帳號
      帶得到 admin custom claim，搬上雲也沒有人能處理案件。另立 `[BE-13]`。**批次由四改五** ——
      關注與貼文拆開，一次驗一塊比較抓得到問題。
      **先做身分層的理由**：現有社群層以暱稱字串為識別碼
      （`_mine(author) => author == displayName`、`following` 存的是暱稱），
      而雲端跨使用者資料必須以 uid 為鍵 —— 暱稱不唯一且可改。
      批次 2–4 全部依賴批次 1 建立的 uid ↔ 暱稱對應（`AppState.nameByUid`）
- [x] 【CC】`[BE-14]` 把團隊／私訊／師徒接上 `AppState` ✅2026-09-14
      → 私訊 3 個接線點、團隊 11 個、師徒 5 個（**學徒側**）。
      每塊各自驗證，皆為 1,340 passed。全部採樂觀更新＋即發即忘：
      記憶體先改、畫面先動，雲端寫入在背景進行並吞掉錯誤，
      下次登入以雲端為準重新對齊。
      **師徒教官側未接**，本機模型缺學徒身分，見 `[BE-15]`
- [ ] 【CC】`[BE-15]` 師徒的本機模型補上學徒身分。
      `mentorTasks`／`questions` 目前是**一份共用清單**，沒有記錄
      「這則是哪位學徒的」；而雲端的任務與問答掛在特定師徒關係下。
      因此 `[BE-14]` 只接得上**學徒側**，教官側（我帶的每位學徒各一段關係）
      接不上。另外 `MentorTask` 沒有 ID 欄位，雲端暫以標題辨識
- [ ] 【人→CC】`[BE-13]` 檢舉／申訴上雲 ＋ 管理端帳號。
      自 `[BE-11]` 移出：檢舉是管理端功能，而**目前沒有任何帳號帶得到
      admin custom claim**，案件搬上雲也沒有人處理得了。
      人要先決定誰是管理員並設好 claim，才輪得到 CC 做資料層
- [~] 【CC】`[BE-12]` 平台公用資料上雲：動作庫、訓練計畫、平台設定、商品、
      成就與獎勵定義。`tools/import_exercises.py` 要改成寫進 Firestore
      而不是產生 `.g.dart`。不做的話管理員後台改了東西不會生效
      → 程式碼寫完、置於分支 `wip/be-12-platform-data`，**本機無法驗證**
      （開發機 macOS 13，跑不動 Flutter 3.44.1），待 Codespaces 驗 `analyze`／`test`。
      範圍依使用者 2026-09-13 裁示調整：做「每日任務池」、**商品延後**，
      獎勵定義併入 `platform_config` 的 reward 群組。詳見第 9 節與決策紀錄。

### B. 部署

- [~] 【人】`[DEP-01]` 選 GitHub Pages 或 Firebase Hosting
      （若已做 A，選 Firebase Hosting，跟後端同一個專案）
      —— **實務上已選定 Firebase Hosting 並上線**，待使用者正式確認後勾選
- [x] 【CC】`[DEP-02]` 部署與線上驗證 ✅2026-09-15
      → 正式網址 **https://alchemy-workout.web.app**。
      已用**兩個真實帳號**完成端到端驗證：登入、發文、按讚、關注、
      私訊、團隊邀請皆通。`firebase.json` 含 Hosting 設定與快取標頭
- [ ] 【人】`[DEP-03]`（選）Apple Developer US$99／年 → TestFlight

### C. 檢查與修 bug

- [ ] 【人】`[QA-01]` 自己把 App 從頭用一遍。
      **歷史上產出最高的 bug 來源** —— 自動化工具抓不到的都是這樣抓到的
- [~] 【CC】`[QA-02]` 修 `[QA-01]` 回報的問題
      → 2026-09-15 使用者實際走過一遍，回報 **15 項**。依性質分三類：

      **甲、假資料未清除**（上線後最刺眼，優先）
      1. `[QA-02a]` 社群動態的假貼文未移除（且 A 發文 B 看不到）
      2. `[QA-02b]` 團隊假資料未移除
      3. `[QA-02c]` 訓練歷史的動作趨勢假資料未移除
      4. `[QA-02d]` 設定頁的通知假資料未移除
      5. `[QA-02e]` 全面清查其餘畫面的假資料

      **乙、流程與規格落差**
      6. `[QA-02f]` **功能未依事件風暴逐一解鎖，一開始就全開**
         （`socialUnlocked`／`_mentorUnlocked` 的預設值確實是 false，
         需查是假資料覆寫還是畫面沒遵守旗標）
      7. `[QA-02g]` 註冊完成後應接新手教學流程
      8. `[QA-02h]` **註冊流程沒有設定暱稱**，所有人都叫「你」
         —— 註冊問卷九題裡沒有這一欄，**加欄位等於改事件風暴的註冊流程**
      9. `[QA-02i]` 無法關注社群中看到的人
      10. `[QA-02j]` 排行榜的入口不應只在設定裡

      **丙、內容與呈現**
      11. `[QA-02k]` 服務條款內容待修
      12. `[QA-02l]` 訓練計畫的標籤待完善（進階、增肌等）
      13. `[QA-02m]` 移除會讓使用者困惑的補充說明文字
      14. `[QA-02n]` 移除退步模擬時鐘
         （目前用於 `decay_screen`／`counterpart_screen` 兩個示範畫面，
         `domain/clock.dart` 說明它是刻意設計的展示機制 —— **移除前須確認**）
      15. `[QA-02o]` 骨架屏與錯誤畫面不應讓前台使用者看到
         （`design/state_gallery_screen` 是設計用的展示頁）
- [ ] 【CC】`[QA-03]` 修第 5 節「小地方」那幾項

### 已放棄

（目前無）

---

## 5. 已知但未修的問題

<!-- 唯讀，勿改。修好之後移除該項並記到第 9 節 -->

### 會影響正確性

1. **評分跑在裝置上** → 改記憶體就能上排行榜，排行榜嚴格說不成立。等 `[BE-07]`。
2. **只有一位使用者。** 事件風暴裡約一半的流程需要第二個人（師徒申請、團隊審核、
   檢舉裁決、私訊回覆）。目前靠「我的 → 流程示範 → 模擬對方」控制台代打 ——
   那個控制台不繞過任何 Precondition，只是代替對方按送出。等 `[BE-04]`。
3. **沒有帳號系統。** 換裝置或清瀏覽器資料就從頭開始。
4. **AI 調整是本地規則引擎**（降強度／升強度／減組數），不是 Gemini。等 `[BE-08]`。
5. **通知只在 App 內**，沒有真的推播。等 `[BE-06]`。

### 資料與文件

6. `健身動作資料庫-1.csv` 與 `-2.csv` **是同一份資料，只有欄序不同**，未定何者為準。
   （已驗證：各 526 筆、動作名稱集合相同、逐欄比對零差異。）
7. `健身計劃-組數次數-待確認.csv` 是**殘留檔**。覆核已完成，成果在
   `健身計劃-組數次數.csv`，但待確認那份沒刪。
8. `健身計劃-組數次數.csv` 有 **32 列組數是由訓練時長回推的**，未經專業覆核。
   檔案內 `組數來源` 欄已標 `估算`，`組數依據` 欄寫得出推算方式。
9. **27 份課表的階級門檻 Beta 期間全部拿掉了**，之後要加回。
   原設計為戰士級 20 階、精銳級 45 階，見 `fitness-app/tools/gen_platform_plans.py`
   的 `RANK` 字典註解。
10. `.gitmodules` 指向 `/Users/johnnypan/...` —— 別人機器上的路徑，是死的。
11. **文件引用了不存在的東西**：`.es-clarify/`、`UI設計執行管理/`、
    `/es-discovery` 與 `/es-formulation` 指令。
12. `UI設計規格書_基礎規範.md` 表頭寫 **v0.4.1**，但修訂表已到 **v0.8** —— 表頭沒跟著更新。

### 小地方

13. 登入頁寫「**歡迎回來**」，但那是第一次來的人看到的畫面。
14. **7 份循環式課表的區段結構丟失。** 像「6 個動作一輪、每個 40 秒、做 4 輪，
    前後夾暖身與有氧」，App 的模型是「每個動作 N 組 × M 下」，裝不下。
    目前把輪數當組數 —— 練得起來，但看不出區段。
    **使用者已於 2026-09-09 裁示維持現狀**，要改需先問過。
15. **iOS 未簽章。** 需要 Apple ID 登入 Xcode（TestFlight 另需 US$99／年）。
16. `fitness-app/README.md` 仍是 Flutter 預設樣板。

---

## 6. 工作慣例

<!-- 唯讀，勿改。這一節是給接手者的 Claude Code 看的 -->

這幾天累積下來的紀律。**每一條都是踩過坑才寫下來的**，不是風格偏好。

1. **每條規則釘一個測試，然後故意把實作弄壞，確認測試會紅。**
   不會紅就代表測試太弱，要加強再驗一次。這是本專案最重要的一條 ——
   開發期間出現過三次「測試通過，但其實什麼都沒驗到」。

2. **驗證工具本身要先被驗證。**
   畫面爬蟲騙過三次：拿背景分頁的座標去點前景分頁、只爬一層漏掉第二層、
   找不到分頁入口就靜靜跳過（於是「訓練」分頁從來沒被爬過，而測試全綠）。
   任何自己寫的檢查工具，先問「它壞掉的話我看得出來嗎」。

3. **衍生值優於儲存欄位。**
   「存了一份、但其實算得出來」是本專案最高產的 bug 形狀 ——
   連續簽到天數、最後訓練日、教官帶徒數、信箱獎勵內容，全都栽在這上面。
   同一件事有兩個來源，遲早會對不起來。

4. **一個數字只服務一個主體。**
   學徒給教官評分，曾經加到**評分者自己**的聲望上；我買的東西與後台的訂單
   曾經是兩份沒接起來的清單。加欄位前先問「這個數字是誰的」。

5. **填錯的數字比留白更糟** —— 留白會被看見，錯的不會。
   **訓練處方尤其不准猜。** 從資料抽不出來的組數次數，寧可標「待填」交給人。

6. **不改規格書。** 偏離 `Event-Storming_事件風暴/` 或 `UI設計規格書_基礎規範.md`
   之前先問人。`Figma/` 是參考不是照搬，要改什麼先確認。

7. **生成檔不可手改**：`lib/mock/platform_exercises.g.dart`、
   `lib/mock/platform_plans.g.dart`。改資料來源再重跑 `tools/` 腳本
   （手改過一次，重新產生時整批動作 ID 被換掉，救了很久）。

8. **Web 一律用 `./tools/build_web.sh`**，不可直接 `flutter build web`。
   直接跑會打包完整的 Noto Sans TC 字集，首次載入多背 **11.5 MB**（gzip 後）。
   那支腳本會做字型子集化並自我驗證覆蓋率。

9. **全量測試加 `--timeout 90s`。** 沒加的話，無窮迴圈會空轉到你以為只是慢
   （曾經花二十分鐘才看出是卡住而不是慢）。

10. **不確定就問。** 不替使用者決定商業取捨、訓練處方、或規格偏離。

---

## 7. 檔案地圖

<!-- 唯讀，勿改 -->

### 活的（會讀、會改）

| 路徑 | 是什麼 |
|---|---|
| `fitness-app/` | Flutter App 本體 |
| `Event-Storming_事件風暴/` | **事實來源。** 37 份文件，11,476 行 |
| `系統架構` | 系統架構章節（**寫的是目標，不是現況**） |
| `UI設計規格書_基礎規範.md` | UI 規格，1,592 行 |
| `Figma/` | 設計原稿（參考用） |
| `Firestore-Schema設計.md` | `[BE-03]` 交付文件，Firestore collection/document 設計方案，`BE-04` 依據 |
| `tools/import_exercises.py` | 動作資料庫匯入器 |
| `健身動作資料庫-*.csv`、`健身計劃*.csv` | 資料來源 |

### 產生檔（不可手改）

- `fitness-app/lib/mock/platform_exercises.g.dart`
- `fitness-app/lib/mock/platform_plans.g.dart`
- `fitness-app/assets/data/exercise_guides.zh.json`

### 課程殘留（**可忽略，不要讀**）

`chapter01/`〜`chapter04/`、`specs/` —— 約 2.5 MB，是這個 repo 原本的
BDD 課程教材，與本 App 無關。讀它們只會浪費 context。

### 建置產物

`健金術.app`、`健金術-arm64.apk`、`健金術-web.zip`、`build/`、
`fitness-app/build/`、`fitness-app/coverage/`（已列入 `.gitignore`）。

`fitness-app/shots/` 的 17 張截圖**保留進版控** —— 那是整合測試的產物，
也是目前唯一有中文字型的畫面紀錄（widget 測試沒有中文字型，只會畫出豆腐）。

### 資料管線

```
健身動作資料庫-*.csv ─→ tools/import_exercises.py      ─→ platform_exercises.g.dart
                                                        └→ assets/data/exercise_guides.json
                        fitness-app/tools/guides_zh.py  ─→ exercise_guides.zh.json（中譯）

健身計劃.csv ─→ fitness-app/tools/extract_plan_volume.py ─→ 健身計劃-組數次數-待確認.csv
                                                    （人工覆核）↓
                                                     健身計劃-組數次數.csv
             ─→ fitness-app/tools/gen_platform_plans.py  ─→ platform_plans.g.dart
```

---

## 8. 決策紀錄

<!-- 唯讀，勿改。新決策往下加 -->

這個 repo **在 2026-09-10 之前沒有版本控制**，所以早期的決策只能寫在這裡，
以及 `Event-Storming_事件風暴/` 各檔案裡帶日期的 `[決策]` 標註。

| 日期 | 決策 | 理由 |
|---|---|---|
| 2026-09-09 | 27 份課表的階級門檻**全部拿掉** | Beta 期間多數測試者階級低，設門檻等於大半內容收不到回饋；回歸課表更不該鎖 —— 退步的人才需要它 |
| 2026-09-09 | 課表的每組**目標重量一律為 0** | 資料以 RPE（自覺強度）開處方，不指定公斤數。替一個沒見過的人填具體重量，比留白危險 |
| 2026-09-09 | 循環式課表**維持現狀**（輪數當組數） | 完整表達需要在課表模型加「區段」概念，成本 2–3 天，暫不做 |
| 2026-09-09 | 保留 7 份示範用假課表 | 它們撐著 AI 優化、會員鎖定、空白課表三條流程的示範 |
| 2026-09-08 | **Web 版字型子集化** | UI 規格 §2.1 要求「完整字集不瘦身」，但 Web 上那是每個訪客都要等的 12.5 MB。只在 Web 版子集化，手機版一個位元組都不動；子集外的罕用字由 Flutter 引擎的後備機制補上 |
| 2026-09-09 | **首次啟動走註冊流程** | 原本 `signUpCompleted` 預設 true（示範身分的一部分），於是全新瀏覽器打開看到的是別人的暱稱與階級。改成沒存檔就走完整註冊，並**當場歸零**，讓那份假資料根本不存在 |
| 2026-09-10 | `CLAUDE.md` 整份重寫 | 原內容是課程 repo 的自動產生檔（TypeScript／FastAPI），還留著未替換的佔位字串。Claude Code 每次啟動都會讀它 |
| 2026-09-10 | 殘留檔案**只標註不刪除** | 使用者裁示 |
| 2026-09-16 | **註冊流程加入「暱稱」欄位，並同步更新事件風暴文件** | 使用者裁示。原九題問卷沒有暱稱，所有人都叫「你」—— 社群、排行榜、師徒全靠暱稱辨識，少了它整個跨使用者體驗不成立。這是**對規格的修改**而非偏離：〈註冊流程〉要一併更新 |
| 2026-09-16 | 退步模擬時鐘**保留機制、但不讓一般使用者看到**（藏進開發者入口） | 使用者裁示。`domain/clock.dart` 明文記載它是刻意設計的展示機制，用來當場演出退步、到期、結算這些掛在時間上的規則 —— 移除等於失去演示能力，但擺在前台會讓使用者困惑 |
| 2026-09-16 | 設計展示頁（`state_gallery_screen`）藏起來 | 使用者裁示。那是骨架屏與錯誤畫面的**樣式集**，給設計看的，不是功能。**真正的載入中／錯誤畫面照常運作** —— 藏的是展示頁，不是那些狀態本身 |
| 2026-09-10 | Blaze 升級與 GCP 預算警示延後到 `BE-07` 前才做（新增 `BE-10`） | `BE-03`／`BE-04` 用 Firestore 免費方案（Spark）就夠，不需要提前綁信用卡曝險 |
| 2026-09-10 | 「本次訓練課表」與「訓練紀錄」在 Firestore 拆成兩個 collection（`session_plans`／`workout_sessions`），1:1 關聯 | 規格明訂兩者為獨立 Aggregate（選課表時建立 vs 開始訓練時建立），設計初稿曾誤合併為一，已對照 `02_Aggregate定義.md` 原文修正 |
| 2026-09-10 | 會員權益 Firestore 文件不儲存 `none` 狀態，文件不存在＝從未訂閱過 | 規格明訂「生效狀態為三值，無『未生效』」；現有 Dart `MembershipState.none` 是客戶端對「文件不存在」的本地詮釋，非要儲存的狀態值 |
| 2026-09-10 | `platform_config` 群組由 11 組擴充為至少 15 組（新增通知/審核時限/內容過濾/防作弊設定） | 已核對規格，確認這四項皆明文「平台級可調參數，由管理員於後台維護」，性質與既有 11 組相同 |
| 2026-09-13 | `BE-12` 範圍：做動作庫/訓練計畫/平台設定/成就定義/獎勵定義/每日任務池 6 項；**商品延後**；獎勵定義併入 `platform_config` 的 `reward` 群組，不另立集合 | 使用者裁示。獎勵定義在現有程式碼裡大多已是 `reward` 群組的 `SettingParam`（`trainCoin`/`rank*` 等），另立集合等於製造第二份真相 |
| 2026-09-13 | `BE-12` 上雲種子**取自打包在本地的 bundle，而非重跑 CSV** | 重跑 `import_exercises.py` 會因 `OVERRIDES` 鍵失配，把 15 個被 `ex('...')` 硬引用的友善動作 ID 換成 `pNNN` 並遺失校準值；committed `.g.dart` 才是正典，也正是 App 離線後備與測試夾具所用。由 `BundledPlatformData` 匯出保證三者一致 |
| 2026-09-13 | `BE-12` 管理端寫入用 `firestore.rules` 的 custom claim 直接放行，不走 Cloud Functions | 平台設定類沒有跨文件金流不變條件，規則放行即足；續留 Spark 免費方案，與 `BE-10`（Blaze 延後）一致。符合 `Firestore-Schema設計.md` §7 |

---

## 9. 變更記錄

<!-- 可編輯，只能往下追加，不得修改既有條目 -->

| 日期 | 變更 |
|---|---|
| 2026-09-10 | 建立本文件、重寫 `CLAUDE.md`、`git init` 並首次提交 |
| 2026-09-10 | 產出交接包；實測發現專案路徑含中文會使 `flutter analyze` 崩潰，記於第 2 節 |
| 2026-09-10 | `BE-01` 完成（`firebase-tools` 安裝＋登入）；`BE-02` 建立 Firebase 專案（Project ID: `alchemy-workout`），預算警示延後，新增 `BE-10` |
| 2026-09-10 | `BE-03` 完成：Firestore schema 設計方案（經 Plan 模式審核通過），交付於 `Firestore-Schema設計.md`。過程中核對規格發現「連續簽到 Aggregate」現有程式碼與規格不符（規格為 4 欄位皆儲存，程式碼只存 2 欄位），已記錄待 `BE-04` 一併同步調整 |
| 2026-09-11 | **發現原開發機無法執行本專案**：Flutter 3.44.1（Dart 3.12.1）的 VM 要求 macOS 14.0 以上，而該機為 2017 年 MacBook Pro（MacBookPro14,1）、macOS 13.7.8，Apple 已不支援升級到 macOS 14。降版亦無解 —— `pubspec.yaml` 要求 `sdk: ^3.12.1`，能滿足的最低版本正是要求 macOS 14 的那一版。裁示改用 GitHub Codespaces，新增 `.devcontainer/`（釘死 Flutter 3.44.1） |
| 2026-09-11 | `BE-04` 程式碼寫完但**完全未驗證**，置於分支 `wip/be-04-auth-firestore`：`lib/data/auth.dart`（Google 登入）、`lib/data/store_firestore.dart`（Firestore 版 Store）、`lib/screens/auth_gate.dart`、最小 `firestore.rules`，並改動 `main.dart`／`signup_screen.dart`／`login_screen.dart`／`settings_screen.dart`（登出）。決定改用 `firebase_auth` 內建 OAuth 而非 `google_sign_in` 套件，理由見 `auth.dart` 類別註解 |
| 2026-09-11 | Codespaces 環境建立完成並**首次驗證 `BE-04` 程式碼**：`flutter pub get` 解析成功（Firebase 套件版本未經驗證卻猜中）、`flutter analyze` 只回報 1 項 lint（已修）、`flutter test --timeout 90s` **1,212 passed**，既有測試一個都沒被牽動。Firestore 資料庫建於 `asia-east1`，`firebase_options.dart` 已產生（web／android 兩個平台） |
| 2026-09-11 | **`BE-04` 端到端驗證通過**：Google 登入 → 註冊問卷 → 資料落地 Firestore → 登出 → 重新登入，金幣／經驗值／連續簽到天數三項完全一致。證明快照拆成多份文件再組回來的轉換是正確的。過程中修掉兩個真 bug：登出後未 `popUntil`（`AuthGate` 換掉的是 `MaterialApp.home`，而設定頁疊在其上，看起來像「按了沒反應」）、devcontainer 缺 `python3-venv`（`build_web.sh` 第一步就失敗） |
| 2026-09-11 | **Codespaces 上不可用 `flutter run -d web-server`**：debug 模式靠 WebSocket（`$dwdsSseHandler`）傳程式碼模組，被連接埠轉發擋掉，症狀是整頁空白、主控台報 `Library not defined: web_entrypoint.dart`，且 App 當場死掉導致存檔靜默中斷。**改用 `./tools/build_web.sh` 建置後以 `python3 -m http.server` 靜態供應**，代價是沒有 hot reload |
| 2026-09-11 | **`BE-04` 與 `BE-05` 完成。** 補上 `test/store_firestore_test.dart`（20 條，涵蓋 `v` 版本號原樣進出、分組欄位回得到原位、組成績巢狀陣列轉換、membership「從未訂閱＝文件不存在」、連續簽到逐日推算），現為 **1,232 passed**。已知缺口：「讀取失敗要丟 `StoreLoadException`」無自動測試，`fake_cloud_firestore` 無法注入失敗，理由與補法寫在該測試檔尾 |
| 2026-09-11 | 新增 `[BE-11]`（跨使用者資料上雲）與 `[BE-12]`（平台公用資料上雲）。`BE-04` 只搬了使用者私有資料，社群／團隊／師徒／商城／動作庫仍是本機假資料，所以「只有一位使用者」這個問題**沒有隨 `BE-04` 解掉** |
| 2026-09-13 | `[BE-12]` 程式碼寫完，置於分支 `wip/be-12-platform-data`，**本機無法驗證**（開發機 macOS 13，Flutter 3.44.1 的 VM 要 macOS 14，`flutter`／`dart` 連 VM 都起不來，與 2026-09-11 記錄一致），待 Codespaces 跑 `analyze`／`test`。新增 `PlatformDataSource` 抽象層（`lib/data/platform_data.dart`＝後備＋序列化、`platform_data_firestore.dart`＝Firestore 實作），比照 `BE-04` 的注入模式：`FitnessApp`／`AuthGate` 新增選用 `platformData`，登入後即發即忘地載入並 `AppState.applyPlatformData()` 填進既有可變容器（`platformExercises`／`platformPlans`／`planSpecById`／`achievements`／`taskPool`／`platformConfig`）。**不注入就走本地後備 → 既有 1,232 測試零改動**（mock 邊界同 `BE-05`）。新增 `test/platform_data_test.dart`。`firestore.rules` 加平台五集合「使用者唯讀、custom claim 管理端寫」 |
| 2026-09-13 | **`[BE-11]` 改為分四批，批次 1（公開檔案）程式碼完成、未驗證。** 新增 `lib/data/public_profile.dart`（`PublicProfile` ＋ `PublicProfileSource` 邊界）、`public_profile_firestore.dart`（`public_profiles/{uid}`）、`test/public_profile_test.dart`（16 條）。`FitnessApp`／`AuthGate` 新增選用 `profileFor`，登入後即發即忘地先發布自己再讀別人；不注入就完全不同步 → 既有測試零改動。`firestore.rules` 新增「登入者皆可讀、僅本人可寫」—— **這是模型裡第一個「別人讀得到我的資料」的集合** |
| 2026-09-13 | **`[BE-11]` 批次 2（關注關係）程式碼完成、未驗證。** 新增 `lib/data/follow_data.dart`＋`follow_data_firestore.dart`（`follows/{followerUid}_{followeeUid}`）、`test/follow_data_test.dart`（12 條）。`AppState.toggleFollow` 的同步簽章不變，改為**樂觀更新＋即發即忘**：記憶體先改、畫面先動，雲端寫入在背景進行且吞掉錯誤 —— 下次登入由 `applyFollows` 以雲端為準重新對齊。`firestore.rules` 新增「只有關注者本人能建立／移除自己發出的關注」 |
| 2026-09-13 | `[BE-11]` 批次 1–2 **驗證通過**：`flutter analyze` 乾淨、`flutter test --timeout 90s` **1,271 passed** |
| 2026-09-13 | **`[BE-11]` 批次 3（貼文／留言／按讚）程式碼完成、未驗證。** 新增 `lib/data/post_data.dart`＋`post_data_firestore.dart`（`posts/{id}`＋`comments`／`likes` 子集合）、`test/post_data_test.dart`（17 條）。`toggleLike`／`addComment`／`publishPost`／`shareWorkout` 四處寫入皆為樂觀更新＋即發即忘 |
| 2026-09-13 | `[BE-11]` 批次 3 **驗證通過**：1,287 passed |
| 2026-09-13 | **`[BE-11]` 批次 4（團隊）程式碼完成、未驗證。** 新增 `lib/data/team_data.dart`＋`team_data_firestore.dart`（`teams/{id}`＋`requests` 子集合）、`test/team_data_test.dart`（20 條）|
| 2026-09-13 | `[BE-11]` 批次 4 **驗證通過**：1,306 passed。過程中測試抓到一個真 bug —— `removeMember` 把整份 members Map 寫回去，而 `update` 的 Map 值在真 Firestore 是**取代**、在 `fake_cloud_firestore` 是**深層合併**，被移除的鍵又被補回來。改用點記法 `'members.$uid': FieldValue.delete()`，兩邊行為一致 |
| 2026-09-13 | **`[BE-11]` 批次 5（私訊）程式碼完成、未驗證。** 新增 `lib/data/chat_data.dart`＋`chat_data_firestore.dart`、`test/chat_data_test.dart`（16 條）。對話 ID 由兩個 uid **排序後合成** —— 同一對人永遠只有一段對話，由主鍵保證；沒有這層的話兩人同時開啟對話會產生兩段、各自看到一半訊息 |
| 2026-09-14 | `[BE-11]` 批次 5 **驗證通過**：1,320 passed |
| 2026-09-14 | **`[BE-11]` 批次 6（師徒）程式碼完成、未驗證。** 新增 `lib/data/mentor_data.dart`＋`mentor_data_firestore.dart`（`mentor_bonds/{mentorUid}_{apprenticeUid}`＋`tasks`／`questions` 子集合、`mentor_requests/{id}`）、`test/mentor_data_test.dart`（21 條）|
| 2026-09-14 | **`[BE-11]` 與 `[BE-14]` 結案（1,340 passed）。** 跨使用者資料的六塊（公開檔案／關注／貼文／團隊／私訊／師徒）資料層、測試、接線全部完成 —— 事件風暴裡「需要第二個人」的流程，資料面到此為止都通了。僅餘師徒教官側（`[BE-15]`）與檢舉（`[BE-13]`）|
| 2026-09-14 | **`[BE-14]` 三塊接線完成、待驗證**：私訊（3 點）✅1,340、團隊（11 點）✅1,340、師徒（學徒側 5 點）未驗證 |
| 2026-09-14 | 師徒**只接學徒側**，教官側另立 `[BE-15]` | 本機的 `mentorTasks`／`questions` 是一份共用清單，沒有記錄「這則是哪位學徒的」，而雲端的任務與問答掛在特定關係下。硬接的話等於要猜是哪一段關係 —— 那是替使用者的資料做決定，不做。另外 `MentorTask` 沒有 ID 欄位，雲端暫以標題辨識（本機本來就這樣認），標題重複會落在同一份文件上，已知取捨 |
| 2026-09-14 | **修掉一顆時間定時炸彈：22 條簽到測試只在一天的某些時段才會綠。** `checkIn()` 寫入時用 `businessDate(now)`（換日 04:00），但 `buildCheckInRecords()` 的假資料與 `checkin_record_test.dart` 的 `dayOf()` 都用**原始日曆日**。當地 00:00–03:59 這四小時內兩者差一天，測試整批紅；其餘時間完全正常。Codespaces 預設 UTC，該時段正是台灣早上 8–12 點。已確認退回到先前「1,340 全過」的 commit 同樣會紅 —— 與當時的改動無關 |
| 2026-09-14 | `businessDate` **自 `app_state.dart` 移入 `domain/clock.dart`** | 它就是換日規則，而假資料產生器與純函式也要用同一套 —— 它們構不到 `AppState`。放在 `AppState` 的後果就是它們改用原始日曆日，長出第二套「今天」。`clock.dart` 的開頭本來就寫著「取時間一律走 `appNow`，不直接呼叫 `DateTime.now()`」，而 `buildCheckInRecords` 正是直接呼叫了系統時間。`app_state.dart` 轉出該符號以維持既有呼叫端不變 |
| 2026-09-14 | **`.g.dart` 漂移已修復，重跑腳本現在與版控逐位元相同。** 根因：`normalise_name()`（把動作名稱的分隔符統一為 ` · `）是後來才加的，加的時候沒有一併改 `OVERRIDES`／`MOBILITY`／`CONDITIONING` 三份**手寫名單的鍵** —— 它們仍是 CSV 原始寫法（`深蹲 -槓鈴`），而迴圈裡的名稱已是 `深蹲 · 槓鈴`，於是 16 筆校準值全部查不到，動作 ID 退回流水號 `pNNN`、休息秒數與相對強度一併遺失。修法是在 `normalise_name` 定義之後把三份名單的鍵一起正規化。並讓「校準值對不到 CSV」從寫進沒人看的報告改為**中止產出並回傳非零** —— 產出看起來正常、測試也不會紅，但 `ex('squat')` 那類硬引用會全部指向不存在的動作 |
| 2026-09-14 | `[BE-11]` 批次 6 **驗證通過**：1,340 passed。六批的資料層與測試全部完成 |
| 2026-09-14 | **`[BE-11]` 不結案**：批次 4–6（團隊／私訊／師徒）**尚未接上 `AppState`**，另立 `[BE-14]` | 資料層與測試齊備，但 App 裡按下去仍只改本機假資料。測試全過是因為驗的是資料層本身，不是 App 行為 —— 這正是第 6 節第 2 條「驗證工具本身要先被驗證」要問的那一句：它壞掉的話我看得出來嗎。批次 1–3 接線點少（關注一個開關、貼文四個寫入點）故一併做了；4–6 每個十幾個變更點，且本機以暱稱為鍵、與雲端的 uid 差距較大 |
| 2026-09-14 | 補上 `[BE-13]` 與 `[BE-14]` 兩個待辦項目 | `[BE-13]` 先前只寫進變更記錄、沒真的進待辦清單 |
| 2026-09-14 | 「同一學徒至多一筆生效中」的檢查放在**資料層**，不放呼叫端 | 走到建立關係的路徑有好幾條（接受申請、接受邀請、恢復關係），每一條都記得檢查是不可能的。放一處才有機會是對的 |
| 2026-09-14 | 解除關係與「未完成任務轉為已作廢」**放在同一批寫入** | 分開做的話中途失敗會留下「關係已解除，但任務還在指派中」——學徒點得下去，卻已經沒有教官。規格明訂已作廢為終止狀態 |
| 2026-09-13 | `fromMe`／`deletedByMe`／`peer` 一律**不存成欄位**，由讀取端依 uid 計算 | 三者都是「每位讀者各自不同」的狀態。存成欄位的話兩人共用同一份 —— 對話框會整段左右顛倒，或我刪掉對話連對方那一側也消失。與貼文的 `likedByMe` 是同一個陷阱，測試逐條釘住 |
| 2026-09-13 | **檢舉／申訴移出 `[BE-11]`，另立 `[BE-13]`** | 那是管理端功能，而目前沒有任何帳號帶得到 admin custom claim —— 案件搬上雲也沒有人處理得了。要先由人決定誰是管理員並設好 claim |
| 2026-09-13 | 團隊成員**內嵌在隊伍文件**，不另開 `members` 子集合 | `Firestore-Schema設計.md` §2.10 原本畫子集合，但同文件第 0 節原則 3 是「小且有界的集合用內嵌陣列」——**團隊上限 5 人**正是該原則的標準案例。內嵌之後「人數上限檢查」與「把人加進去」落在同一份文件，用 transaction 就保證得了不會擠進第六人；分開做的話兩人同時被核准即破功。另存 `memberUids` 陣列供「我在哪一隊」查詢（Firestore 無法對 Map 的鍵做查詢）|
| 2026-09-13 | `peakSize`（本週期最高人數）**只增不減** | 它是「曾經達到過」而非「現在有幾人」，排行榜分組依它判定。有人退出就跟著降的話，分組會在週期中途改變 |
| 2026-09-13 | 貼文的 Firestore 文件 ID **沿用本地產生的貼文 ID**，不用自動 ID | 否則每次發文都要處理「暫時 ID 換成正式 ID」，而畫面、留言、檢舉案件都各自握著舊的那一個。直接避開這類換算 |
| 2026-09-13 | 按讚存**兩份**：`likes/{uid}` 子集合（真相來源、一人一次由主鍵保證）＋貼文上的 `likeCount`（顯示用計數） | 動態牆每篇都去數一遍子集合的話，一頁 20 篇就是 20 次額外查詢。`likedByMe` 則**必須**放子集合 —— 那是每位讀者各自不同的狀態，放貼文欄位會變成所有人共用同一個「我按過了」 |
| 2026-09-13 | 安全規則用 `diff().affectedKeys().hasOnly(['likeCount'])` 讓非作者能改貼文 | 按讚的人不是作者，卻必須更新貼文上的計數。只允許作者寫則按讚寫不進去；允許任何人寫則別人能改你的文字。**計數本身仍可竄改，等 `[BE-07]`** |
| 2026-09-13 | 關注關係的文件 ID 用 **{follower}_{followee} 合成**，不用自動 ID | 「同一組關係只能有一筆」直接由 Firestore 主鍵保證，重複關注在這個結構下**寫不出來**，不必靠程式碼記得先查一次。兩個方向都是單欄位查詢，不需要複合索引 |
| 2026-09-13 | `AuthGate` 中 `applyFollows` **必須排在 `applyPublicProfiles` 之後** | 前者靠後者填好的 `nameByUid` 把 uid 翻回暱稱；順序顛倒的話一個都翻不出來，而且不會報錯，只會靜靜地少掉所有關注關係 |
| 2026-09-13 | 公開檔案**另立文件，不開放讀 `users/{uid}`** | 安全規則的粒度是**文件、不是欄位**。`users/{uid}` 裡有身高體重、生日、Email、處罰狀態、累計違規次數，「只公開其中幾個欄位」唯一可靠的做法就是拆成另一份文件。見 `Firestore-Schema設計.md` 第 7 節「建議另拆一份精簡 `public_profile`」 |
| 2026-09-13 | 關閉可見度時**不寫該鍵**（而非寫 null）；發布用 `set` 整份覆寫（**不用 merge**） | 寫 null 等於把「他有幾點但不給你看」也放上雲端，而規則擋不住已在文件裡的欄位；用 merge 則會讓關閉可見度之前的舊值留在雲端 —— 使用者以為關了、別人其實還讀得到。兩條各有測試釘住 |
| 2026-09-13 | `applyPublicProfiles` 對 `socialUsers` 是**併入而非取代** | 動態牆的貼文、對話、教官清單目前仍指向示範用的那幾位；直接換掉會讓那些畫面指到不存在的人。等批次 2–4 把貼文與師徒也搬上雲，示範資料才有辦法整批退場 |
| 2026-09-15 | **`[QA-01]` 實際走過一遍，回報 15 項問題**，已編號記於第 4 節 `[QA-02a]`–`[QA-02o]`。分三類：假資料未清除（5 項）、流程與規格落差（5 項）、內容與呈現（5 項）。**印證了第 6 節第 2 條** —— 1,340 個測試全綠，但這 15 項沒有一項是自動測試抓得到的 |
| 2026-09-15 | **`[DEP-02]` 完成：正式上線 https://alchemy-workout.web.app**，並以兩個真實帳號完成跨使用者功能的端到端驗證（發文、按讚、關注、私訊、團隊邀請）|
| 2026-09-14 | Google 登入在 Web 上一路卡關，修了三層：①`authDomain` 指向 App 自己的網域（`flutterfire` 預設的 `firebaseapp.com` 與 App 所在的 `web.app` 不同源，轉址回來讀不到 `sessionStorage`，報 `missing initial state`）；②改用 `signInWithRedirect`（手機瀏覽器會擋彈出視窗）並在啟動時 `getRedirectResult` 收尾；③到 Google Cloud Console 把新的 redirect URI 加進 OAuth 白名單（Firebase 只自動註冊 `firebaseapp.com` 那一個，換網域後 Google 回 `redirect_uri_mismatch`）|
| 2026-09-14 | **修掉一條會讓人填完整份問卷卻進不了 App 的死路**：手機與 Apple 登入尚未接上真實授權，但按下去仍會推進本機流程 —— 而 `AuthGate` 看的是 Firebase 登入狀態，使用者填完 9 題後卡在最後一頁，重新整理連資料都沒了。接上帳號系統時改為停用並標示「即將推出」|
| 2026-09-15 | **加上 Hosting 快取標頭。** 入口檔（`index.html`／`flutter_bootstrap.js`／`main.dart.js` 等）改為不快取，字型與圖片改為長期快取。在此之前每次部署都要跟瀏覽器快取與 Flutter 的 Service Worker 纏鬥 —— 實測線上檔案確認新版早已部署，使用者看到的一直是舊版 |
| 2026-09-14 | 網頁與 App 圖示改用專案 Logo（原為 Flutter 樣板預設）；啟動頁的佔位啞鈴圖示換成 Logo。另補 `apple-touch-icon`（不透明）—— iOS 主畫面圖示不支援透明，會把透明處畫成黑色 |
| 2026-09-15 | **字級稽核**：規格 §2.2 定 10 種字級，畫面卻寫死 242 處、其中 175 處（72%）不在表上，另冒出 17 種字級。顏色則 22 個色票完全相符。先以訓練結算頁為樣本收斂 17 處，待確認視覺效果後再決定是否推廣至其餘 27 個畫面 |
| 2026-09-13 | **發現 `.g.dart` 既有漂移**：對 `tools/import_exercises.py`／`gen_platform_plans.py` 重跑（我的改動為輸出中性，已與原腳本逐位元比對證實），產出與 committed `.g.dart` 不同 —— `OVERRIDES` 的鍵已對不上 CSV 現況，`deadlift`／`squat` 等 15 個被 `ex('...')` 硬引用的友善動作 ID 被換成 `pNNN`，且校準過的相對強度／休息秒數遺失（正是 CLAUDE.md 硬性規則 1 警告的情形）。故 **committed `.g.dart` 才是正典**，已還原重跑產出、不提交。因此 `BE-12` 的上雲**種子取自 bundle**（新增 `fitness-app/tools/export_platform_defs.dart` 由 `BundledPlatformData` 匯出五集合 JSON → `tools/upload_platform_data.py` 上傳），保證雲端＝打包內容＝測試夾具。`import_exercises.py --upload`／`gen_platform_plans.py --upload` 仍保留「tools 寫進 Firestore」能力（使用者指示），供日後 CSV／OVERRIDES 校準後以 CSV 為真相來源時使用。**CSV／OVERRIDES 的漂移本身是既有問題、未修，留待獨立處理** |
