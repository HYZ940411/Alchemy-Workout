import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_app/domain/registration.dart';
import 'package:fitness_app/screens/me/settings_screen.dart';
import 'package:fitness_app/state/app_state.dart';

Future<void> pump(WidgetTester t, AppState s) async {
  await t.pumpWidget(AppScope(
    state: s,
    child: const MaterialApp(home: SettingsScreen()),
  ));
  await t.pumpAndSettle();
}

void main() {
  // 使用者回報「設定中的訓練問卷、生日等也是假資料，不是我當初註冊填的，
  // 也不能修改」。那四列原本是寫死的字串，右邊還畫著看起來可點的箭頭。
  group('設定頁的訓練問卷讀的是真值', () {
    testWidgets('改了 AppState，畫面就跟著變', (t) async {
      final s = AppState();
      s.updateSurvey(
        daysPerWeek: 6,
        duration: kDurations.last,
        commonGoal: kCommonGoals.last,
        experience: kExperience.last,
      );
      await pump(t, s);

      expect(find.text('6 天'), findsOneWidget);
      expect(find.text(kDurations.last), findsOneWidget);
      expect(find.text(kCommonGoals.last), findsOneWidget);
      expect(find.text(kExperience.last), findsOneWidget);
      // 寫死的那四個字串不該再出現。
      expect(find.text('4 天'), findsNothing);
      expect(find.text('60–90 分'), findsNothing);
    });

    testWidgets('點下去改得動，且立刻重新推薦', (t) async {
      final s = AppState();
      final before = s.daysPerWeek;
      await pump(t, s);

      await t.tap(find.text('$before 天'));
      await t.pumpAndSettle();
      // 選一個與現值不同的。
      final pick = before == 7 ? 6 : 7;
      await t.tap(find.text('$pick 天').last);
      await t.pumpAndSettle();

      expect(s.daysPerWeek, pick);
      expect(s.currentPlan, isNotNull, reason: '更新後應重新推薦當前計畫');
    });

    testWidgets('可用器材也在這一頁 —— 它是推薦的第一順位比對維度', (t) async {
      final s = AppState();
      await pump(t, s);
      expect(find.text('可用器材'), findsOneWidget);
      expect(find.text(s.equipmentTier), findsOneWidget);
    });

    testWidgets('改可用器材會重新推薦', (t) async {
      final s = AppState();
      s.updateSurvey(equipmentTier: '徒手');
      expect(s.equipmentTier, '徒手');
      final plan = s.currentPlan;
      // 徒手是硬約束裡最緊的一層 —— 推薦出來的不可以是要器械的。
      if (plan != null) expect(plan.equipmentTier, '徒手');
    });
  });

  group('生日', () {
    test('註冊時填的生日要落地 —— 在此之前是問了就丟', () {
      final s = AppState();
      s.signUpDraft
        ..nickname = '阿昶'
        ..birthday = DateTime(2000, 4, 11)
        ..gender = '男'
        ..heightCm = 176
        ..weightKg = 72
        ..daysPerWeek = 4
        ..duration = kDurations.first
        ..commonGoal = kCommonGoals.first
        ..experience = kExperience.first
        ..equipment.add(kEquipmentTiers.first);
      expect(s.signUpDraft.complete, isTrue, reason: '10 項必填都要填滿');
      s.completeSignUp();
      expect(s.birthday, DateTime(2000, 4, 11));
    });

    testWidgets('沒有生日就說沒有，不擺一個看起來很真的假日期', (t) async {
      final s = AppState();
      s.birthday = null;
      await pump(t, s);
      // 2026-09-26 使用者裁決 B：沒填的可以補填，所以這一列說得出「可補填」，
      // 而不是只掛一把看不出是刻意還是壞了的鎖頭。
      // 補填的規則見 `test/birthday_fill_once_test.dart`。
      expect(find.text('未填寫（可補填）'), findsOneWidget);
      // 這個日期原本是寫死在畫面上的，每一位使用者看到的都是它。
      expect(find.text('1996 / 03 / 12'), findsNothing);
    });

    testWidgets('有生日就顯示他自己的', (t) async {
      final s = AppState();
      s.birthday = DateTime(2000, 4, 11);
      await pump(t, s);
      expect(find.text('2000 / 04 / 11'), findsOneWidget);
    });

    test('生日要進存檔 —— 存了讀回來還在', () {
      final a = AppState()..birthday = DateTime(1999, 12, 31);
      final b = AppState()..applySnapshot(a.toSnapshot());
      expect(b.birthday, DateTime(1999, 12, 31));
    });
  });

  group('身高體重改得動', () {
    test('身高有 Command —— 原本這一列點下去什麼都不會發生', () {
      final s = AppState()..updateHeight(180);
      expect(s.heightCm, 180);
    });

    test('英制輸入換算回公制，來回不變形', () {
      final s = AppState()..setFlag(metric: false);
      final shown = s.toDisplayUnit(176, true); // cm → in
      expect(s.toMetric(shown, true), closeTo(176, 0.01));
      final lb = s.toDisplayUnit(72, false);
      expect(s.toMetric(lb, false), closeTo(72, 0.01));
    });

    test('公制模式下換算是恆等的', () {
      final s = AppState()..setFlag(metric: true);
      expect(s.toMetric(176, true), 176);
      expect(s.toDisplayUnit(72, false), 72);
    });
  });
}
