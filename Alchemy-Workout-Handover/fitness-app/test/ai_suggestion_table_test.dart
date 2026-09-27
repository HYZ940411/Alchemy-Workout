import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_app/domain/ai_adjust.dart';
import 'package:fitness_app/domain/models.dart';
import 'package:fitness_app/mock/mock_data.dart';
import 'package:fitness_app/screens/ai/ai_adjust_screen.dart';
import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/domain/platform_config.dart';
import 'package:fitness_app/state/app_state.dart';

/// 使用者回報「AI 建議給的排版不好做閱讀。可否用好看的表格呈現？」
///
/// 在此之前整份建議被拼成一段字串塞進**寬 260** 的對話泡泡 ——
/// 而那些欄位在 `AdjustChange` 裡本來就是分開的，是渲染時才被拼掉的。
void main() {
  setUp(platformConfig.reset);
  tearDown(platformConfig.reset);

  group('動作名與調整內容是兩個欄位，不是一個字串', () {
    AdjustChange change({
      String name = '深蹲',
      List<PlannedSet> before = const [PlannedSet(60, 8)],
      List<PlannedSet> after = const [PlannedSet(60, 8)],
      Exercise? replacement,
      String? reason,
    }) =>
        AdjustChange(
          exerciseIndex: 0,
          exerciseName: name,
          before: before,
          after: after,
          replacement: replacement,
          reason: reason,
        );

    test('維持不變', () {
      final c = change();
      expect(c.unchanged, isTrue);
      expect(c.title, '深蹲');
      expect(c.change, '維持不變');
    });

    test('換動作 —— 第一欄是「原 → 新」', () {
      final c = change(
        name: '外展臀橋',
        replacement: ex('squat'),
        after: const [PlannedSet(0, 15), PlannedSet(0, 15)],
      );
      expect(c.unchanged, isFalse);
      expect(c.title, '外展臀橋 → ${ex('squat').name}');
      expect(c.change, '15 下 × 2 組');
    });

    test('改重量與次數', () {
      final c = change(
        before: const [PlannedSet(60, 8)],
        after: const [PlannedSet(55, 10)],
      );
      expect(c.title, '深蹲');
      expect(c.change, '60kg × 8 下 → 55kg × 10 下');
    });

    test('改組數', () {
      final c = change(
        before: const [PlannedSet(60, 8), PlannedSet(60, 8)],
        after: const [PlannedSet(60, 8)],
      );
      expect(c.change, '2 組 → 1 組');
    });

    test('徒手（目標重量 0）只講下數', () {
      final c = change(
        before: const [PlannedSet(0, 10)],
        after: const [PlannedSet(0, 12)],
      );
      expect(c.change, '10 下 → 12 下');
    });

    // summary 由兩者組出來，不是反過來 —— 表格若靠切字串取欄位，
    // 遇到名字裡有全形空格的動作就會切錯。
    test('summary 是 title ＋ change 組出來的', () {
      final c = change();
      expect(c.summary, '${c.title}　${c.change}');
    });
  });

  group('畫面：建議排成表格，不是一坨字', () {
    const src = AiSource.beforeTraining;

    Future<void> open(WidgetTester t, AppState s) async {
      await t.pumpWidget(AppScope(
        state: s,
        child: const MaterialApp(home: AiAdjustScreen(source: src)),
      ));
      await t.pumpAndSettle();
    }

    AppState proposed() {
      final s = AppState();
      s.startWorkout(kPlans.firstWhere((p) => p.id == 'p_push'));
      s.aiRequest(src, '今天狀況不太好');
      s.aiConfirmDemand(src, '整體降強度');
      s.aiProduceSuggestion(src);
      return s;
    }

    testWidgets('每一個動作各自一列，看得到動作名與調整內容', (t) async {
      final s = proposed();
      final sug = s.aiSuggestion[src];
      expect(sug, isNotNull, reason: '前提：這一步要真的產出建議');
      await open(t, s);
      for (final c in sug!.changes) {
        expect(find.text(c.title), findsWidgets, reason: '${c.title} 那一列');
        expect(find.text(c.change), findsWidgets, reason: '${c.title} 的調整');
      }
    });

    testWidgets('標題列講得出動了幾項', (t) async {
      final s = proposed();
      final sug = s.aiSuggestion[src]!;
      final changed = sug.changes.where((c) => !c.unchanged).length;
      await open(t, s);
      expect(
        find.text(changed == 0 ? '無異動' : '$changed / ${sug.changes.length} 項調整'),
        findsOneWidget,
      );
    });

    testWidgets('作用範圍仍然講得出來', (t) async {
      final s = proposed();
      await open(t, s);
      expect(find.textContaining('作用範圍：'), findsWidgets);
    });

    // 對話紀錄要留得下來 —— 一段能唸出來的話比一個物件可靠。
    test('純文字版本仍然一起存進對話', () {
      final s = proposed();
      final turns = s.aiConversations[src]!;
      final ai = turns.lastWhere((x) => x.suggestion != null);
      expect(ai.text, contains('建議如下'));
      expect(ai.text, contains('作用範圍'));
      expect(ai.scope, isNotNull);
    });
  });
}
