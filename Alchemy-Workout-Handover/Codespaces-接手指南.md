# 在 GitHub Codespaces 接手 BE-04

> 2026-09-11 建立。原開發機（2017 MacBook Pro／macOS 13.7.8）無法執行
> Flutter 3.44.1 —— 它的 Dart VM 要求 macOS 14.0 以上，而 Apple 已不支援
> 該硬體升級到 macOS 14。降版也無解：`pubspec.yaml` 要求 `sdk: ^3.12.1`，
> 能滿足的最低版本正是要求 macOS 14 的那一版。

**目前狀態**：BE-04 的程式碼全部寫好，放在分支 `wip/be-04-auth-firestore`，
**但一行都沒有編譯過、沒有跑過測試**。這份文件就是把它驗證完成的步驟。

---

## 0. 開 Codespace

到 https://github.com/HYZ940411/Alchemy-Workout

1. 切到分支 **`wip/be-04-auth-firestore`**（不要用 main，程式碼不在那）
2. 綠色的 `Code` 按鈕 → `Codespaces` 分頁 → `Create codespace on wip/be-04-auth-firestore`

第一次建立要等 **10–15 分鐘**：容器會下載 Flutter 3.44.1（約 1 GB）、
裝 Claude Code 與 firebase-tools、跑 `flutter pub get`。
終端機會把過程印出來，看到「=== 完成 ===」才算好。

> 免費額度：個人帳號每月 120 core-hours（2-core 機器等於 60 小時）。
> 不用時記得到 github.com/codespaces 把它 **Stop**，不然閒置也在算錢。

---

## 1. 確認環境

Codespace 開好後，在終端機：

```bash
flutter --version
```

**必須**看到 `Flutter 3.44.1` / `Dart 3.12.1`。不是的話先停下來問，
不要硬著頭皮往下做 —— PROGRESS.md 明確警告版本漂移會讓上千個測試一起紅。

---

## 2. 登入 Claude Code

```bash
claude
```

第一次會要你授權：終端機印出一個網址，在瀏覽器打開、登入 Anthropic 帳號、
把回來的代碼貼回終端機。之後直接打 `claude` 就進得去。

進去之後第一句建議這樣說：

```
讀 Alchemy-Workout-Handover/PROGRESS.md 與 Codespaces-接手指南.md，
然後繼續做 BE-04：先跑 flutter analyze 把編譯錯誤修掉。
```

---

## 3. Firebase Console 的手動步驟（**這幾步只有你能做**）

這三件事沒有 CLI 指令可以代勞，而且**不做的話後面全部卡住**。

### 3-1. 啟用 Cloud Firestore API

https://console.developers.google.com/apis/api/firestore.googleapis.com/overview?project=alchemy-workout

按「啟用」。（已經確認過目前是關的。）

### 3-2. 建立 Firestore 資料庫

Firebase Console → 建構 → Firestore Database → 建立資料庫

- 模式：**正式版**（rules 我們自己管）
- 位置：建議 **asia-east1（台灣）**
  ⚠️ **位置一旦建立永久不可更改**，要換等於整個資料庫重建。

### 3-3. 啟用 Google 登入

Firebase Console → 建構 → Authentication → Sign-in method
→ 新增供應商 → **Google** → 啟用 → 填「專案支援電子郵件」→ 儲存

---

## 4. 產生 `firebase_options.dart`

**這是第一個非做不可的程式步驟** —— `main.dart` 匯入了這個檔案，
沒有它連 `flutter analyze` 都會直接報錯。

```bash
# 登入 Firebase（會給你一個網址，瀏覽器授權後貼回代碼）
firebase login --no-localhost

# 裝 flutterfire 指令
dart pub global activate flutterfire_cli
export PATH="$PATH":"$HOME/.pub-cache/bin"

cd Alchemy-Workout-Handover/fitness-app

# 只設定 web 與 android：
# macOS/iOS 在 Linux 容器裡本來就建置不了，iOS 另外還卡在未簽章（DEP-03）
flutterfire configure \
  --project=alchemy-workout \
  --platforms=web,android \
  --out=lib/firebase_options.dart
```

---

## 5. 驗證（重點在這裡）

```bash
cd Alchemy-Workout-Handover/fitness-app

flutter analyze                 # 目標：完全乾淨
flutter test --timeout 90s      # 目標：1,212 passed（不可以變少）
```

### 預期會踩到的問題

程式碼是在沒有 SDK 的機器上寫的，以下幾點**有相當機率要修**：

1. **Firebase 套件版本解析失敗** —— `pubspec.yaml` 裡的版本號是照 pub.dev
   當時的最新穩定版填的，沒驗證過。解析不過就：
   ```bash
   flutter pub add firebase_core firebase_auth cloud_firestore
   ```
   讓 pub 自己挑，不要手動猜。

2. **`firebase_auth` 的 API 對不上** —— `signInWithProvider` 與
   `signInWithPopup` 的簽章、`FirebaseAuthException` 的錯誤代碼字串，
   都是憑記憶寫的。`lib/data/auth.dart` 是唯一會受影響的檔案。

3. **既有測試變紅** —— 設計上刻意讓新增的 `auth` 參數預設為空值，
   1,212 個既有測試不傳它，行為應該完全不變。**如果有測試紅了，
   那是真的有問題，不要改測試去配合程式碼**（PROGRESS.md 第 6 節第 1 條）。

---

## 6. 還沒做的事（BE-04 尚未完成的部分）

- **`test/store_firestore_test.dart` 完全還沒寫。** 照 CLAUDE.md 第 5 條，
  沒有測試釘住就不算完成。至少要涵蓋：
  - `load()` 回傳的 Map 裡有 `v`（沒有的話 `applySnapshot` 會靜默整份忽略，
    使用者看到示範假資料卻沒有任何錯誤訊息 —— 這是最容易漏的一條）
  - 巢狀陣列的來回轉換（`[重量,次數]` ↔ `{w,r}`）
  - `membership` 為 `none` 時不建立文件；文件不存在時讀回 `none`
  - 連續簽到天數的逐日推算
  - 讀取失敗要丟 `StoreLoadException`，不可以回傳 `null`
    （回 null 等於告訴 App「沒存過」，下一次自動存檔就把空白寫回去了）

  建議用 `fake_cloud_firestore` 套件（純記憶體，不必起 emulator），
  與現有 1,212 個測試「不碰網路」的哲學一致。

- **安全規則還沒部署**：`firebase deploy --only firestore:rules`

- **實際跑一次登入流程**：Codespaces 可以跑 Web 版
  （`flutter run -d web-server --web-port 8080`，VS Code 會提示轉發連接埠）。
  要驗的是：登入 → 填問卷 → 到 Firebase Console 確認 `users/{uid}` 真的建立了
  → 重新整理應該直接進主畫面 → 登出 → 換另一個 Google 帳號登入應該看不到前一個帳號的資料。

---

## 7. 已知的取捨（不是 bug，是刻意的）

| 項目 | 現況 | 為什麼 |
|---|---|---|
| 手機簡訊驗證 | 仍是假的（任意 6 碼都過） | 防刷保護要等 `BE-09` App Check，簡訊被盜刷是真的會付錢 |
| Apple 登入 | 仍是假的 | 卡在 `DEP-03`（Apple 開發者帳號 US$99／年，未購買） |
| 金幣／能力值 | 客戶端仍可竄改 | 要等 `BE-07` 把邏輯搬上 Cloud Functions；現在就把欄位鎖成唯讀的話 App 自己也動不了 |
| 貼文／團隊／訂單 | 仍是本機假資料 | 不在 BE-04 範圍，`Firestore-Schema設計.md` 已規劃好結構 |
| `clear()` | 只清本實作寫過的路徑 | 規格要求的完整硬刪除涉及數十個 collection，必須由伺服器端執行 |
