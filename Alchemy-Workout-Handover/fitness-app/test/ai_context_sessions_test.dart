// 送給模型的脈絡要包含**最近幾場的完成度**（2026-09-28）。
//
// 使用者實測：練一份 16 組的課表只完成 2 組（13%），自動優化卻回
// 「這次看不出該往哪個方向調」。
//
// 查下去發現送過去的只有每個動作的（重量, 次數）——
// **模型完全不知道他做到一半就走了**。一個做了 13% 的人需要的是減量，
// 而那件事寫在完成度裡，不在重量裡。
//
// 資料本來就在（`HistoryEntry.completion`），只是沒送出去。

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/ai_suggestion.dart';
import 'package:fitness_app/domain/platform_config.dart';
import 'package:fitness_app/domain/rewards.dart';
import 'package:fitness_app/state/app_state.dart';

void main() {
  setUp(platformConfig.reset);
  tearDown(platformConfig.reset);

  /// 練一場，只完成 [done] 組。
  void train(AppState s, String planId, {int done = 1}) {
    s.startWorkout(s.platformPlans.firstWhere((p) => p.id == planId));
    for (var i = 0; i < done; i++) {
      s.completeCurrentSet();
    }
    s.finishWorkout(EndKind.endedEarly);
  }

  AdjustContext contextOf(AppState s) {
    final plan = s.platformPlans.firstWhere((p) => p.id == 'p_push');
    return s.aiContextForTest(plan.exercises);
  }

  test('完成度有送出去', () {
    final s = AppState()..resetToNewAccount();
    train(s, 'p_push', done: 1);
    final ctx = contextOf(s);
    expect(ctx.sessions, isNotEmpty);
    expect(ctx.sessions.first.completion, isNotNull);
    expect(ctx.sessions.first.completion!, lessThan(0.5),
        reason: '一組都做不完的那種');
  });

  test('最多五場，新的在前', () {
    final s = AppState()..resetToNewAccount();
    for (var i = 0; i < 8; i++) {
      train(s, 'p_push');
    }
    expect(contextOf(s).sessions.length, 5);
  });

  test('完成度進得了 JSON —— 不然等於沒送', () {
    final s = AppState()..resetToNewAccount();
    train(s, 'p_push');
    final json = contextOf(s).toJson();
    final sessions = json['sessions'] as List;
    expect(sessions, isNotEmpty);
    expect((sessions.first as Map).containsKey('completion'), isTrue);
    expect((sessions.first as Map)['plan'], isNotNull);
  });

  test('沒練過就沒有這一段，不要擺一個空陣列進 prompt', () {
    final s = AppState()..resetToNewAccount();
    expect(contextOf(s).sessions, isEmpty);
    expect(contextOf(s).toJson().containsKey('sessions'), isFalse);
  });

  // **不含身分** —— 承 `AdjustContext` 的既有裁決。
  test('多送了完成度，仍然沒有身分', () {
    final s = AppState()..resetToNewAccount();
    train(s, 'p_push');
    final json = contextOf(s).toJson().toString();
    expect(json.contains(s.displayName), isFalse);
    final uid = s.myUid;
    if (uid != null && uid.isNotEmpty) {
      expect(json.contains(uid), isFalse);
    }
  });
}
