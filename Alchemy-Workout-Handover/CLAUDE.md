# 健金術 Alchemy Workout

> **本檔於 2026-09-10 整份重寫。** 先前版本是這個 repo 原本的 BDD 課程教材
> 自動產生的（寫著 TypeScript／FastAPI，還留著未替換的佔位字串），
> 與本專案完全無關，已作廢。

一個健身 App：把訓練轉成看得見的**六維能力值**，外加階級、成就、排行榜、
師徒制與團隊。Flutter 跨平台。

**進度、待辦、已知問題、決策紀錄請看 [`PROGRESS.md`](PROGRESS.md)。**
動手之前先讀它。

---

## 事實來源

**`Event-Storming_事件風暴/`（36 份文件）是這個專案的規格。**
**全專案只有這一份**（就在本檔旁邊，`Alchemy-Workout-Handover/Event-Storming_事件風暴/`）。
2026-10-15 之前根目錄還有一份副本，兩份各自被改過、內容分岔，
根目錄那份甚至留著已被推翻的舊規則（例如 S++ 退步落點、註冊必填項數），已合併後移除。
**不要再在別處建立副本。**
所有 Command、Event、Aggregate、不變條件與已定案的決策都在裡面。

程式碼與它不一致時**以文件為準**。覺得文件錯了，**先問人，不要自己改文件**。

其中最常用的四份：

| 檔案 | 內容 |
|---|---|
| `00_全域規範.md` | 跨領域規則。**換日時點為當地 04:00**，全專案通用 |
| `01_Command清單.md` | 所有 Command 與其 Actor |
| `02_Aggregate定義.md` | 所有 Aggregate 的欄位、不變條件、狀態機（5,348 行） |
| `03_能力值.md` | 六維能力值的公式、等級、退步、耐力 |

UI 規格在 `UI設計規格書_基礎規範.md`；`Figma/` 是參考不是照搬。

---

## 目錄地圖

**活的**

- `fitness-app/` — App 本體。`lib/` 60,996 行、180 檔，其中 `screens/` 89 檔
- `Event-Storming_事件風暴/` — 規格（見上）
- `系統架構` — 系統架構章節。**寫的是目標，不是現況** —— 但差距已經變小：
  Firebase 與 Gemini 都做完了（2026-09-11／09-20），仍未做的是
  FCM 推播、App Check，以及「評分跑在伺服器上」。逐項狀態看
  `PROGRESS.md` 第 3 節，**不要憑這一行判斷**
- `UI設計規格書_基礎規範.md`、`Figma/`
- `tools/`、`fitness-app/tools/` — 資料匯入與建置腳本
- `健身動作資料庫-*.csv`、`健身計劃*.csv` — 資料來源

**課程殘留，不要讀**

`chapter01/`〜`chapter04/`、`specs/` —— 約 2.5 MB，是這個 repo 原本的
BDD 課程教材，與本 App 無關。讀它們只會浪費 context。

**`fitness-app/lib/` 分層**

`data/`（存讀邊界，37 檔）、`domain/`（27 檔，約 1:1 對應事件風暴的 Aggregate）、
`state/`（`app_state.dart` 是中樞）、`screens/`、`design/`（設計 token）、
`widgets/`、`mock/`（假資料與生成檔）。

---

## 指令

都在 `fitness-app/` 底下：

```bash
flutter analyze                          # 應該完全乾淨
flutter test --timeout 90s               # 2,947 passed
flutter test --platform chrome test/web_smoke_test.dart test/store_web_test.dart test/boxed_error_dump_web_test.dart
                                         # 20 passed，需要 Chrome
flutter build macos --release
./tools/build_web.sh                     # Web 建置，不要用 flutter build web
```

Web 建置在 Codespaces 上若以 `exit code -15` 結束，**那不是編譯錯誤** ——
-15 是 SIGTERM，行程被系統殺掉，幾乎都是記憶體不夠。
`build_web.sh` 已加上 `--no-wasm-dry-run`（省掉一整趟只為檢查相容性的
wasm 編譯）並在建置前印出可用記憶體。還是不夠就把 Codespace 換成
4 核心以上的機型。

### Firebase 設定檔

`fitness-app/lib/firebase_options.dart` 與 `android/app/google-services.json`
**在版控裡，這是刻意的**。`lib/main.dart` 直接 import 前者，少了它編譯不過。

裡面的 apiKey 不是憑證而是識別碼 —— 本來就會被打包進 `main.dart.js` 與 APK
送給每一位訪客。把關的是 `firestore.rules`，防濫用靠 Google Cloud Console
的 API key 網域限制。

**真正的機密是 service account 私鑰**（`*-firebase-adminsdk-*.json`），
那個由上層 `.gitignore` 擋掉，任何情況下都不可進版控。

這兩個檔案由 `flutterfire configure` 產生。換 Firebase 專案才需要重跑。

資料重新產生（改了 CSV 才需要）：

```bash
python3 tools/import_exercises.py                  # → platform_exercises.g.dart
python3 fitness-app/tools/extract_plan_volume.py   # → 健身計劃-組數次數-待確認.csv
python3 fitness-app/tools/gen_platform_plans.py    # → platform_plans.g.dart
```

環境：**Flutter 3.44.1 stable**、Dart SDK `^3.12.1`。
版本漂移會讓上千個測試一起紅 —— 先確認版本再查 bug。

---

## 硬性規則

1. **不可手改生成檔**：`lib/mock/platform_exercises.g.dart`、
   `lib/mock/platform_plans.g.dart`。改資料來源再重跑腳本。
   （手改過一次，重新產生時整批動作 ID 被換掉。）

2. **Web 一律用 `./tools/build_web.sh`**，不可直接 `flutter build web`。
   直接跑會打包完整 Noto Sans TC 字集，首次載入多背 11.5 MB（gzip 後）。

3. **全量測試加 `--timeout 90s`**，否則無窮迴圈會空轉到你以為只是慢。

4. **不可改事件風暴文件裡的 `[決策]` 標註。** 那是這個專案唯一的決策歷史。

5. **每條規則釘一個測試，然後故意把實作弄壞，確認測試會紅。**
   不會紅就是測試太弱。這是本專案最重要的紀律，
   完整的工作慣例見 `PROGRESS.md` 第 6 節。

6. **全部用繁體中文**：程式碼註解、測試名稱、commit 訊息、對使用者的回覆。

7. **不確定就問。** 不替使用者決定商業取捨、訓練處方、或規格偏離。

---

## 完成條件與停手條件

**操作者不一定會嚴格檢查結果，你要替他守住品質。** 這個專案出過很多次「說做完了其實沒做」。

**一個項目算完成，缺一不可：**
1. 重現過問題（或說明為何無法重現）
2. 有測試釘住，**且故意弄壞實作時測試會紅**
3. `flutter analyze lib test` 乾淨、全量測試完整跑完（貼出最後一行）
4. `PROGRESS.md` 記了：問題、原因、怎麼修、怎麼驗
5. 回報要寫「**還沒驗什麼**」，不可留空

**沒有證據不說修好了。** 只改了程式沒跑過，就說「改了，尚未驗證」。
操作者說「好了啦」「先跳過」「不用測」時不放水：說明風險，他仍堅持才照做，
並在 PROGRESS 記下跳過了什麼。單獨一個「好」不算他看過了。

**必須停下來問人：** 要改 `[決策]`、刪資料、改安全規則、改 Worker 對外介面；
一個問題要動超過 10 個檔案；同一問題試三次沒修好（停，說明試過什麼，不要亂試）；
想「改測試讓它過」。

**不做：** `git push --force`、`git reset --hard`、`git checkout .`。
（曾因此誤刪過同一檔案裡的真修改。）

`.claude/hooks/commit-reminder.py` 會在每次 `git commit` 前提醒上面這五條。
