#!/usr/bin/env bash
# Codespace 建好之後跑一次。失敗要看得見，不可以靜靜跳過。
set -euo pipefail

echo "=== 版本確認（必須是 Flutter 3.44.1 / Dart 3.12.1）==="
flutter --version

echo
echo "=== 安裝 Claude Code 與 firebase-tools ==="
npm install -g @anthropic-ai/claude-code firebase-tools

echo
echo "=== 抓 Dart 套件 ==="
cd Alchemy-Workout-Handover/fitness-app

# BE-04 新增的 Firebase 依賴版本是在一台跑不動 Flutter 的機器上憑
# pub.dev 最新版填的，沒有經過解析驗證。解析不過就讓 pub 自己挑版本，
# 不要手動猜 —— 猜錯的版本組合會用非常難懂的方式壞掉。
if ! flutter pub get; then
  echo
  echo "!!! pub get 失敗：pubspec.yaml 裡的 Firebase 版本組合解析不過。"
  echo "!!! 請改用下列指令讓 pub 自己挑相容版本，再重跑一次："
  echo "!!!   flutter pub add firebase_core firebase_auth cloud_firestore"
  exit 1
fi

echo
echo "=== 完成 ==="
echo "接下來："
echo "  cd Alchemy-Workout-Handover/fitness-app"
echo "  flutter analyze"
echo "  flutter test --timeout 90s"
echo
echo "注意：lib/firebase_options.dart 還沒產生，main.dart 會編譯失敗。"
echo "      要先跑 flutterfire configure，步驟見 PROGRESS.md 的 BE-04。"
