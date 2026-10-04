import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_app/domain/adjust_volume.dart';
import 'package:fitness_app/data/ai_suggestion.dart';
import 'package:fitness_app/domain/ai_adjust.dart';
import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/domain/models.dart';
import 'package:fitness_app/domain/platform_config.dart';
import 'package:fitness_app/screens/ai/ai_adjust_screen.dart';
import 'package:fitness_app/state/app_state.dart';

/// **從畫面打字到看見建議的整條路。**
///
/// 使用者回報 P62 C「一直轉圈不停」。根因：`aiConfirmDemand` 自 2026-09-27
/// 起是非同步的（先問 AI 判方向），而送出鍵沒有等它 —— `onSent()` 執行的
/// 那一刻 stage 還是 `clarifying`，於是它裡面的
/// `if (stage == analyzing) _startAnalyzing()` 永遠不成立：
/// 方向判出來了、stage 也變成 analyzing 了，**卻沒有任何人去產生建議**。
///
/// 既有的測試都直接呼叫 `AppState` 的方法，所以一條都沒有紅 ——
/// 那個缺陷只存在於「畫面怎麼串這些方法」這一層。
void main() {
  setUp(platformConfig.reset);
  tearDown(platformConfig.reset);

  const src = AiSource.beforeTraining;

  Future<AppState> open(WidgetTester t, {AiSuggestionSource? ai}) async {
    final s = AppState()..aiSource = ai;
    s.startWorkout(s.platformPlans.firstWhere((p) => p.exercises.isNotEmpty));
    await t.pumpWidget(AppScope(
      state: s,
      child: const MaterialApp(home: AiAdjustScreen(source: src)),
    ));
    await t.pumpAndSettle();
    return s;
  }

  Future<void> send(WidgetTester t, String text) async {
    await t.enterText(find.byType(TextField).first, text);
    await t.tap(find.byIcon(Icons.send_rounded));
    // 判讀 → 分析 → 建議，中間有幾段等待。
    await t.pump();
    await t.pump(const Duration(seconds: 3));
    await t.pumpAndSettle();
  }

  testWidgets('打一句 AI 判得出來的話 → 真的看得到建議，不是卡在轉圈', (t) async {
    final s = await open(t, ai: _Classifies(AdjustIntent.trim));
    await send(t, '我等一下要趕去接小孩');
    // 減組數先問時間（2026-10-04）。回一個一定做不完的時間，才會真的砍。
    expect(s.aiAwaitingMinutes[src], isTrue, reason: '要先問還剩多久');
    await send(t, '5 分鐘');

    expect(s.aiIntent[src], AdjustIntent.trim, reason: '方向要判出來');
    expect(s.aiStage[src], AiStage.proposed,
        reason: '**這一條是 P62 的核心**：不能停在 analyzing');
    expect(find.text('分析中…'), findsNothing, reason: '不可以一直轉圈');
    expect(find.textContaining('項調整'), findsOneWidget, reason: '建議要出得來');
  });

  testWidgets('點四顆方向鍵也要走到建議', (t) async {
    final s = await open(t);
    await t.tap(find.text(adjustIntentNames[AdjustIntent.easier]!).last);
    await t.pump();
    await t.pump(const Duration(seconds: 3));
    await t.pumpAndSettle();

    expect(s.aiStage[src], AiStage.proposed);
    expect(find.text('分析中…'), findsNothing);
  });

  testWidgets('AI 判不出來時停在追問，而且不轉圈', (t) async {
    final s = await open(t, ai: _Classifies(null));
    await send(t, '早安');

    expect(s.aiStage[src], AiStage.clarifying);
    expect(find.text('判讀你的需求…'), findsNothing, reason: '判完就要收掉');
    expect(find.text('分析中…'), findsNothing);
    expect(find.textContaining('個方向調'), findsOneWidget);
  });

  testWidgets('AI 掛掉時退回端內規則，照樣走到建議', (t) async {
    final s = await open(t, ai: _Throws());
    await send(t, '今天太重了');

    expect(s.aiIntent[src], AdjustIntent.easier);
    expect(s.aiStage[src], AiStage.proposed);
    expect(find.text('分析中…'), findsNothing);
  });
}

class _Classifies implements AiSuggestionSource {
  /// 這幾份假件都不測自動優化 —— **擲例外而不是回空值**：
  /// 回空值會讓「沒被呼叫到」與「回了個空的」長得一樣。
  @override
  Future<RemoteAutoAdjust> suggestAuto({
    required List<PlanExercise> exercises,
    AdjustContext? context,
    Map<String, List<Exercise>> candidates = const {},
    List<AdjustIntent>? intents,
    VolumePlan? volume,
    List<Exercise> addCandidates = const [],
  }) =>
      throw UnimplementedError('這個假件不支援自動優化');

  final AdjustIntent? intent;
  _Classifies(this.intent);

  @override
  Future<RemoteIntent> classify(String say) async => RemoteIntent(intent);

  // 這一份測試驗的是**整條路走不走得完**，不是建議的來源 ——
  // 所以建議就用端內規則產一份回去。
  @override
  Future<RemoteSuggestion> suggest({
    required List<PlanExercise> exercises,
    required AdjustIntent intent,
    int onlyFrom = 0,
    String? note,
    AdjustContext? context,
    Map<String, List<Exercise>> candidates = const {},
    List<AdjustIntent>? intents,
    VolumePlan? volume,
    List<Exercise> addCandidates = const [],
  }) async =>
      RemoteSuggestion(SuggestionOrigin.rule,
          buildSuggestion(exercises, intent, onlyFrom: onlyFrom));
}

class _Throws implements AiSuggestionSource {
  /// 這幾份假件都不測自動優化 —— **擲例外而不是回空值**：
  /// 回空值會讓「沒被呼叫到」與「回了個空的」長得一樣。
  @override
  Future<RemoteAutoAdjust> suggestAuto({
    required List<PlanExercise> exercises,
    AdjustContext? context,
    Map<String, List<Exercise>> candidates = const {},
    List<AdjustIntent>? intents,
    VolumePlan? volume,
    List<Exercise> addCandidates = const [],
  }) =>
      throw UnimplementedError('這個假件不支援自動優化');

  @override
  Future<RemoteIntent> classify(String say) async => throw Exception('分類逾時');

  @override
  Future<RemoteSuggestion> suggest({
    required List<PlanExercise> exercises,
    required AdjustIntent intent,
    int onlyFrom = 0,
    String? note,
    AdjustContext? context,
    Map<String, List<Exercise>> candidates = const {},
    List<AdjustIntent>? intents,
    VolumePlan? volume,
    List<Exercise> addCandidates = const [],
  }) async =>
      RemoteSuggestion(SuggestionOrigin.rule,
          buildSuggestion(exercises, intent, onlyFrom: onlyFrom));
}
