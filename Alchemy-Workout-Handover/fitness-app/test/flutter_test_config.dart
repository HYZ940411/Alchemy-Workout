import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/clock.dart';

/// 每個測試開始前把展示時鐘歸零。
///
/// 時鐘是模組層級的狀態（畫面裡構不到 AppState 的地方也要讀得到同一個時鐘），
/// 代價是它會跨測試累積：一個推了 400 天的測試會讓後面每一個測試
/// 都從 400 天後開始。歸零放在這裡，個別測試不必記得。
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  setUp(resetAppClock);
  tearDown(resetAppClock);
  await testMain();
}
