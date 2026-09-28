// 課表推薦：加入「時長」這一維，並且不再只看得到一份。
//
// 2026-09-28 使用者：「每次只會看到一個推薦訓練，只能練到胸。」
//
// 推薦本身是單向指派（規格：使用者不可拒絕，無拒絕分支），那條沒有錯 ——
// 錯在**沒有別的東西可看**。所以單向指派不動（`recommendCurrentPlan()`
// 仍只回一份），另外開一條「還有哪些也適合」給畫面。
//
// 時長進比對是**規格偏離**（〈註冊流程〉明訂三個維度），使用者裁決 B。
// 它是問卷問過、卻從來沒被用來推薦的一題。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/platform_config.dart';
import 'package:fitness_app/domain/registration.dart';
import 'package:fitness_app/screens/plan_select_screen.dart';
import 'package:fitness_app/state/app_state.dart';
import 'package:fitness_app/theme.dart';
import 'package:fitness_app/widgets/common.dart';

class TestPlan {
  final String name;
  final String tier;
  final Set<String> exp;
  final Set<String> goals;
  final String? dur;
  const TestPlan(this.name, {this.tier = '健身房', this.exp = const {},
      this.goals = const {}, this.dur});
}

List<RankedPlan<TestPlan>> rank(List<TestPlan> plans, {
  String? equipment = '健身房器材',
  String? experience = '新手',
  String? goal = '增肌',
  String? duration = '30–60 分鐘',
}) =>
    recommendPlans<TestPlan>(
      plans,
      equipment: equipment,
      experience: experience,
      commonGoal: goal,
      duration: duration,
      tierOf: (p) => p.tier,
      experienceOf: (p) => p.exp,
      goalsOf: (p) => p.goals,
      durationOf: (p) => p.dur,
    );

void main() {
  setUp(platformConfig.reset);
  tearDown(platformConfig.reset);

  group('時長成為第四個比對維度', () {
    test('其餘條件相同時，時長符合的排前面', () {
      final got = rank(const [
        TestPlan('太長', dur: '90 分鐘以上'),
        TestPlan('剛好', dur: '30–60 分鐘'),
      ]);
      expect(got.first.plan.name, '剛好');
      expect(got.first.match.durationOk, isTrue);
      expect(got.last.match.durationOk, isFalse);
    });

    test('估不出時長的視為符合，不因為算不出來被推到最後', () {
      final got = rank(const [
        TestPlan('太長', dur: '90 分鐘以上'),
        TestPlan('空白課表', dur: null),
      ]);
      expect(got.first.plan.name, '空白課表');
    });

    test('沒問時長時，行為與加這一維之前一致', () {
      final got = rank(const [
        TestPlan('甲', dur: '90 分鐘以上'),
        TestPlan('乙', dur: '30–60 分鐘'),
      ], duration: null);
      expect(got.map((r) => r.plan.name), ['甲', '乙'], reason: '同分取建立最早');
    });
  });

  group('優先序是嚴格字典序，不是加權投票', () {
    // 器材是**硬約束且向下相容**：健身房的人做得了居家與徒手課表，
    // 所以要製造「器材不符」得反過來 —— 徒手的人做不了健身房課表。
    test('器材符合但其餘全不符，仍勝過器材不符但其餘全符', () {
      final got = rank(const [
        TestPlan('器材不符但其餘全符',
            tier: '健身房', exp: {'新手'}, goals: {'增肌'}, dur: '30–60 分鐘'),
        TestPlan('只有器材符合',
            tier: '徒手', exp: {'進階'}, goals: {'減脂'}, dur: '90 分鐘以上'),
      ], equipment: '徒手');
      expect(got.first.plan.name, '只有器材符合');
      expect(got.first.match.reasons, ['器材']);
    });

    test('經驗勝過目標與時長的總和', () {
      final got = rank(const [
        TestPlan('經驗不符', exp: {'進階'}, goals: {'增肌'}, dur: '30–60 分鐘'),
        TestPlan('經驗符合', exp: {'新手'}, goals: {'減脂'}, dur: '90 分鐘以上'),
      ]);
      expect(got.first.plan.name, '經驗符合');
    });
  });

  test('講得出為什麼推薦這一份', () {
    final got = rank(const [
      TestPlan('全符', exp: {'新手'}, goals: {'增肌'}, dur: '30–60 分鐘'),
    ]);
    expect(got.first.match.reasons, ['器材', '經驗', '目標', '時長']);
  });

  group('當前計畫與推薦清單是同一套排序', () {
    test('recommendPlan 回的就是排序第一名', () {
      const plans = [
        TestPlan('乙', exp: {'進階'}),
        TestPlan('甲', exp: {'新手'}),
      ];
      final first = rank(plans).first.plan;
      final one = recommendPlan<TestPlan>(
        plans,
        equipment: '健身房器材',
        experience: '新手',
        commonGoal: '增肌',
        duration: '30–60 分鐘',
        tierOf: (p) => p.tier,
        experienceOf: (p) => p.exp,
        goalsOf: (p) => p.goals,
        durationOf: (p) => p.dur,
      );
      expect(one?.name, first.name);
    });

    test('AppState：當前計畫＝ rankedPlans 的第一名', () {
      final s = AppState();
      expect(s.recommendCurrentPlan()?.id, s.rankedPlans().first.plan.id);
    });
  });

  group('推薦清單', () {
    test('只收器材做得到的 —— 推一份今天做不到的課表沒有意義', () {
      final s = AppState();
      for (final r in s.recommendedPlans()) {
        expect(r.match.equipmentOk, isTrue, reason: r.plan.name);
      }
    });

    test('最多五份', () {
      expect(AppState().recommendedPlans().length, lessThanOrEqualTo(5));
      expect(AppState().recommendedPlans(count: 3).length, lessThanOrEqualTo(3));
    });

    test('排序不篩掉器材不符的 —— 使用者可能正要去健身房', () {
      final s = AppState();
      expect(s.rankedPlans().length,
          greaterThanOrEqualTo(s.recommendedPlans(count: 999).length));
    });
  });

  group('畫面', () {
    Future<void> open(WidgetTester t, AppState s) async {
      await t.pumpWidget(AppScope(
        state: s,
        child: const MaterialApp(home: Scaffold(body: PlanSelectScreen())),
      ));
      await t.pumpAndSettle();
    }

    // 第一版是在清單上面另開一段「為你推薦」，那會把同一張卡片畫兩次，
    // 而且五張卡片把「選擇今天的課表」擠出畫面 —— `plan_filter_test`
    // 與 `smoke_test` 當場抓到。改成排進同一份清單並標籤。
    testWidgets('推薦排進同一份清單，不另開一區、不畫兩次', (t) async {
      final s = AppState();
      expect(s.recommendedPlans(), isNotEmpty, reason: '前提：要有推薦');
      await open(t, s);
      expect(find.text('為你推薦'), findsNothing);
      expect(find.text('選擇今天的課表'), findsOneWidget, reason: '不該被擠出畫面');
      expect(find.text('推薦'), findsWidgets, reason: '要標得出來哪幾份');
      // 2026-09-28 使用者回報標籤太多，「XX 符合」那四個是純重複
      // （內容本來就在下面），改成把對上的那幾個染成橘色。
      // 所以這裡驗的是**顏色**，不是多出來的標籤。
      final orange = t
          .widgetList<Pill>(find.byType(Pill))
          .where((p) => p.color == AppColors.accent);
      expect(orange, isNotEmpty, reason: '對上的維度要染色，那就是理由');

      // 同一份課表只出現一次。
      final top = s.recommendedPlans().first.plan;
      expect(find.text(top.name), findsOneWidget);
    });

    testWidgets('最適合的排在最上面', (t) async {
      final s = AppState();
      await open(t, s);
      final names = t
          .widgetList<Text>(find.byType(Text))
          .map((w) => w.data)
          .whereType<String>()
          .toList();
      final want = s.recommendedPlans().first.plan.name;
      final other = s.rankedPlans().last.plan.name;
      if (names.contains(want) && names.contains(other)) {
        expect(names.indexOf(want), lessThan(names.indexOf(other)));
      }
    });
  });
}
