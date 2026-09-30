// 自動優化：**系統自己判斷方向**，不問使用者（2026-09-28 使用者裁決 A）。
//
// 使用者問「他是會直接給我一個優化調整的清單還是什麼」。查證後：不會 ——
// 它掛一個標記，點「查看」之後走**訓練前調整的同一條追問流程**，
// 反過來問使用者要調哪個方向。
//
// 而 `01_Command清單.md`〈AI 自動優化訓練流程〉寫的是：
//     優化訓練強度 | 系統
//     確認使用新訓練強度 | 使用者
//     拒絕調整 | 使用者
// **流程裡沒有「使用者挑方向」這一步。**
//
// 差別不只是少一步：訓練前調整是免費功能，自動優化是會員權益。
// 兩者都要人挑方向的話，付費買到的只是「幫你記得每三次提醒一次」。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/ai_suggestion.dart';
import 'package:fitness_app/domain/ai_adjust.dart';
import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/domain/models.dart';
import 'package:fitness_app/domain/platform_config.dart';
import 'package:fitness_app/domain/rewards.dart';
import 'package:fitness_app/screens/ai/ai_adjust_screen.dart';
import 'package:fitness_app/state/app_state.dart';

/// 可控的自動優化來源。
class _Auto implements AiSuggestionSource {
  /// 模型判斷出來的方向。空值＝看不出來。
  final AdjustIntent? decide;
  final String? why;
  final bool throws;
  int calls = 0;

  _Auto({this.decide = AdjustIntent.easier, this.why, this.throws = false});

  @override
  Future<RemoteAutoAdjust> suggestAuto({
    required List<PlanExercise> exercises,
    AdjustContext? context,
    Map<String, List<Exercise>> candidates = const {},
  }) async {
    calls++;
    if (throws) throw StateError('雲端掛了');
    final d = decide;
    if (d == null) return const RemoteAutoAdjust();
    return RemoteAutoAdjust(
      intent: d,
      why: why,
      suggestion: AdjustSuggestion(
        intent: d,
        changes: [
          for (var i = 0; i < exercises.length; i++)
            AdjustChange(
              exerciseIndex: i,
              exerciseName: exercises[i].exercise.name,
              before: [...exercises[i].planned],
              // 33 是規則引擎絕對算不出來的數字。
              after: [for (final p in exercises[i].planned) PlannedSet(p.targetWeight, 33)],
            ),
        ],
      ),
    );
  }

  @override
  Future<RemoteIntent> classify(String say) =>
      throw UnimplementedError('自動優化不該走分類');

  @override
  Future<RemoteSuggestion> suggest({
    required List<PlanExercise> exercises,
    required AdjustIntent intent,
    int onlyFrom = 0,
    String? note,
    AdjustContext? context,
    Map<String, List<Exercise>> candidates = const {},
  }) =>
      throw UnimplementedError('自動優化不該走這一支');
}

AppState _withSuggestion(AiSuggestionSource? src) {
  final s = AppState()
    ..aiSource = src
    ..subscribe(yearly: false);
  for (var i = 0; i < AppState.kAutoOptimizeEvery; i++) {
    s.startWorkout(s.platformPlans.firstWhere((p) => p.id == 'p_push'));
    s.completeCurrentSet();
    s.finishWorkout(EndKind.completed);
  }
  return s;
}

void main() {
  setUp(platformConfig.reset);
  tearDown(platformConfig.reset);

  const src = AiSource.autoOptimize;

  test('不問方向就直接產出建議', () async {
    final ai = _Auto(decide: AdjustIntent.harder, why: '上次都做滿了');
    final s = _withSuggestion(ai);
    expect(s.aiOptimizePlan, isNotNull, reason: '前提：要有一份待優化的課表');

    await s.aiAutoPropose();

    expect(ai.calls, 1);
    expect(s.aiStage[src], AiStage.proposed, reason: '直接到「已產出」，不經過追問');
    expect(s.aiIntent[src], AdjustIntent.harder, reason: '方向由模型決定');
    expect(s.aiSuggestion[src]!.changes.first.after.first.targetReps, 33);
  });

  test('方向的理由也講得出來 —— 那是自動優化與訓練前調整的差別', () async {
    final s = _withSuggestion(_Auto(why: '上次 60 公斤第三組只完成 6 下'));
    await s.aiAutoPropose();
    expect(s.aiSuggestion[src]!.rationale, '上次 60 公斤第三組只完成 6 下');
  });

  test('判斷不出方向就不掛建議，下次再說', () async {
    final s = _withSuggestion(_Auto(decide: null));
    await s.aiAutoPropose();

    expect(s.aiStage[src], AiStage.idle);
    expect(s.aiSuggestion[src], isNull, reason: '不要憑空挑一個方向');
    expect(s.optimizedPlanId, isNotNull, reason: '標記還在，下次還會試');
  });

  test('呼叫失敗時說得出來，標記不清掉', () async {
    final s = _withSuggestion(_Auto(throws: true));
    await s.aiAutoPropose();

    expect(s.aiStage[src], AiStage.idle);
    expect(s.optimizedPlanId, isNotNull);
    final last = s.aiConversations[src]!.last;
    expect(last.text, contains('稍後再試'));
    expect(last.text, contains('不會消失'));
  });

  test('不扣點 —— 那是會員權益', () async {
    final s = _withSuggestion(_Auto());
    final before = s.aiTotal;
    await s.aiAutoPropose();
    expect(s.aiStage[src], AiStage.proposed, reason: '前提：這一步要成功');
    expect(s.aiTotal, before);
  });

  // 端內規則算得出 ×0.9，算不出「這個人現在該升還是該降」。
  test('沒接外部 AI 時退回舊的追問流程，至少挑得了方向', () async {
    final s = _withSuggestion(null);
    await s.aiAutoPropose();
    expect(s.aiStage[src], AiStage.clarifying);
  });

  testWidgets('畫面：進去就在分析，不是問你要怎麼調', (t) async {
    final s = _withSuggestion(_Auto());
    await t.pumpWidget(AppScope(
      state: s,
      child: const MaterialApp(home: AiAdjustScreen(source: src)),
    ));
    await t.pumpAndSettle();

    expect(find.textContaining('這份課表要怎麼調'), findsNothing,
        reason: '規格裡沒有「使用者挑方向」這一步');
    expect(s.aiStage[src], AiStage.proposed);
  });
}
