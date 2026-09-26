// 講「今天沒有啞鈴」要聽得懂（2026-09-26）。
//
// 使用者實測：在訓練中調整裡打「今天沒有啞鈴可以用」，系統回
// 「抱歉，我看不出你想往哪個方向調」。那句話講得再清楚不過了 ——
// 他要換掉做不了的動作（`AdjustIntent.swap`）。
//
// 根因：原本的條件只有 `沒有器材` 與 `器材不`。**沒有人會說「我沒有
// 器材」**，他會說沒有**哪一樣**器材。
//
// 器材名稱直接取自值域 `kEquipmentItems`，不自己再列一份 ——
// 管理員在後台加了品項，這裡要跟著認得。

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/ai_adjust.dart';
import 'package:fitness_app/mock/mock_equipment.dart';
import 'package:fitness_app/state/app_state.dart';

void main() {
  group('器材缺席＝換動作', () {
    for (final t in const [
      '今天沒有啞鈴可以用',
      '沒有槓鈴',
      '健身房的壺鈴被占了',
      '彈力繩壞了',
      '機械式器材不能用',
      '今天沒帶啞鈴',
    ]) {
      test('「$t」', () {
        expect(AppState.parseIntent(t), AdjustIntent.swap, reason: t);
      });
    }

    test('值域裡的每一樣器材都認得', () {
      for (final e in kEquipmentItems) {
        expect(AppState.parseIntent('今天沒有$e'), AdjustIntent.swap,
            reason: e);
      }
    });
  });

  group('不會誤判成換動作', () {
    test('「沒力氣了，想輕一點」→ 降強度', () {
      expect(AppState.parseIntent('沒力氣了，想輕一點'), AdjustIntent.easier);
    });

    test('「組數太多」→ 減少組數', () {
      expect(AppState.parseIntent('組數太多'), AdjustIntent.trim);
    });

    test('「今天狀況好，想加重」→ 升強度', () {
      expect(AppState.parseIntent('今天狀況好，想加重'), AdjustIntent.harder);
    });

    test('沒提到器材的否定句不算換動作', () {
      // 「沒睡飽」有「沒」但沒有任何器材名稱 —— 不該判成換動作。
      expect(AppState.parseIntent('沒睡飽'), isNull);
    });
  });

  group('認不出來就回空值，不猜', () {
    test('「早安」', () {
      // 猜錯的代價不是保守與否，是做了他沒要求的事還收了錢。
      expect(AppState.parseIntent('早安'), isNull);
    });
  });
}
