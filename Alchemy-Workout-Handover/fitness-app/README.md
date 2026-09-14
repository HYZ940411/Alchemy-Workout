# 健金術 Alchemy Workout

把訓練轉成看得見的**六維能力值**，外加階級、成就、排行榜、師徒制與團隊。
Flutter 跨平台（iOS／Android／Web／macOS）。

> 這份是 App 本體的說明。**專案的進度、待辦、已知問題與決策紀錄
> 一律看上層的 [`PROGRESS.md`](../PROGRESS.md)**，動手之前先讀它。

## 開發環境

**Flutter 3.44.1 stable**、Dart SDK `^3.12.1`。
版本漂移會讓上千個測試一起紅 —— 先確認版本再查 bug。

> **專案路徑不可含中文（或任何非 ASCII 字元）。**
> 含中文時分析伺服器會崩潰，`flutter analyze` 直接跑不起來。

## 常用指令

```bash
flutter analyze                       # 應該完全乾淨
flutter test --timeout 90s            # 全量測試
./tools/build_web.sh                  # Web 建置（不要直接用 flutter build web）
firebase deploy --only hosting        # 部署
firebase deploy --only firestore:rules
```

`--timeout 90s` 不是可選的 —— 沒有它，無窮迴圈會空轉到你以為只是慢。

`build_web.sh` 會做中文字型子集化，省下約 19 MB。直接跑
`flutter build web` 會打包完整字集，首次載入多背 11.5 MB。

## 目錄

| 路徑 | 內容 |
|---|---|
| `lib/data/` | 存讀邊界。`Store`（本機／Firestore）、`AuthService`、各社群資料來源 |
| `lib/domain/` | 純函式與不可變模型，約 1:1 對應事件風暴的 Aggregate |
| `lib/state/` | `app_state.dart` 是狀態中樞 |
| `lib/screens/` | 約 80 個畫面 |
| `lib/design/` | 設計 token（顏色、字級、間距） |
| `lib/mock/` | 假資料與生成檔（`*.g.dart` **不可手改**） |
| `tools/` | 建置與資料匯入腳本 |

## 規格

事實來源是 `../Event-Storming_事件風暴/`（36 份文件），
UI 規格在 `../UI設計規格書_基礎規範.md`。
**程式碼與文件不一致時以文件為準。**
