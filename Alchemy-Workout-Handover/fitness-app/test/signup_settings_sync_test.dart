import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_app/domain/registration.dart';
import 'package:fitness_app/screens/me/settings_screen.dart';
import 'package:fitness_app/state/app_state.dart';

/// 註冊問卷填的每一項，都要（一）落地到 AppState、（二）進存檔、
/// （三）在設定頁看得到。
///
/// 使用者要求「再次確認當時註冊所填寫的問題都能跟設定的項目同步」。
/// 這一輪已經抓到兩項是**問了就丟**：生日與動機類目標 —— 註冊收了，
/// `completeSignUp` 沒有落地，存檔沒有，設定頁也沒有。
///
/// 這份測試是那個稽核的固化。日後在註冊問卷加一題而忘了接上，會在這裡紅。
void main() {
  /// 填滿一份與預設值**全部不同**的草稿。
  ///
  /// 「全部不同」很重要：若某一欄沒落地，它會停在 AppState 的預設值，
  /// 而預設值剛好等於草稿值的話，這個測試會綠得毫無意義。
  AppState signedUp() {
    final s = AppState();
    s.signUpDraft
      ..nickname = '阿昶'
      ..heightCm = 181
      ..weightKg = 68.5
      ..gender = '女'
      ..birthday = DateTime(2001, 7, 3)
      ..commonGoal = kCommonGoals.last
      ..motiveGoal = kMotiveGoals.last
      ..experience = kExperience.last
      ..daysPerWeek = 6
      ..duration = kDurations.first
      ..equipment.add(kEquipmentTiers.last);
    expect(s.signUpDraft.complete, isTrue);
    s.completeSignUp();
    return s;
  }

  group('註冊填的每一項都要落地到 AppState', () {
    test('十項必填＋一項選填，逐項比對', () {
      final s = signedUp();
      expect(s.displayName, '阿昶', reason: '暱稱');
      expect(s.heightCm, 181, reason: '身高');
      expect(s.bodyweightKg, 68.5, reason: '體重');
      expect(s.isMale, isFalse, reason: '性別');
      expect(s.birthday, DateTime(2001, 7, 3), reason: '生日');
      expect(s.commonGoal, kCommonGoals.last, reason: '健身目標（常見）');
      expect(s.experience, kExperience.last, reason: '健身經驗');
      expect(s.daysPerWeek, 6, reason: '每週天數');
      expect(s.duration, kDurations.first, reason: '每次時長');
      expect(s.equipmentTier, kEquipmentTiers.last, reason: '器材');
      expect(s.motiveGoal, kMotiveGoals.last, reason: '健身動機（選填）');
    });

    test('每一項都要進存檔 —— 存了讀回來還在', () {
      final a = signedUp();
      final b = AppState()..applySnapshot(a.toSnapshot());
      expect(b.displayName, a.displayName);
      expect(b.heightCm, a.heightCm);
      expect(b.bodyweightKg, a.bodyweightKg);
      expect(b.isMale, a.isMale);
      expect(b.birthday, a.birthday);
      expect(b.commonGoal, a.commonGoal);
      expect(b.experience, a.experience);
      expect(b.daysPerWeek, a.daysPerWeek);
      expect(b.duration, a.duration);
      expect(b.equipmentTier, a.equipmentTier);
      expect(b.motiveGoal, a.motiveGoal);
    });
  });

  group('設定頁看得到註冊填的值', () {
    testWidgets('每一項都出現在畫面上', (t) async {
      final s = signedUp();
      await t.pumpWidget(AppScope(
        state: s,
        child: const MaterialApp(home: SettingsScreen()),
      ));
      await t.pumpAndSettle();

      expect(find.text('${s.daysPerWeek} 天'), findsOneWidget, reason: '每週天數');
      expect(find.text(s.duration), findsOneWidget, reason: '每次時長');
      expect(find.text(s.commonGoal), findsOneWidget, reason: '健身目標');
      expect(find.text(s.experience), findsOneWidget, reason: '健身經驗');
      expect(find.text(s.equipmentTier), findsOneWidget, reason: '器材');
      expect(find.text(s.motiveGoal!), findsOneWidget, reason: '健身動機');
      expect(find.text('2001 / 07 / 03'), findsOneWidget, reason: '生日');
      expect(find.text('女'), findsOneWidget, reason: '性別');
      expect(find.text(s.heightText(s.heightCm)), findsOneWidget, reason: '身高');
      expect(find.text(s.weightText(s.bodyweightKg)), findsOneWidget,
          reason: '體重');
    });

    testWidgets('生日與性別唯讀，但說得出為什麼', (t) async {
      // 規格裁決：兩者為能力值計算鏈的輸入（年齡係數、DOTS 係數），
      // 可任意改動將使既有點數失去計算基準；如需更正屬客服範疇。
      // 唯讀是對的 —— 但只掛一把鎖頭而不給理由，使用者看不出是刻意還是壞了。
      final s = signedUp();
      await t.pumpWidget(AppScope(
        state: s,
        child: const MaterialApp(home: SettingsScreen()),
      ));
      await t.pumpAndSettle();

      await t.tap(find.text('2001 / 07 / 03'));
      await t.pumpAndSettle();
      expect(find.textContaining('年齡係數'), findsOneWidget);
      expect(s.birthday, DateTime(2001, 7, 3), reason: '點了不該改掉它');
    });
  });

  group('動機類目標不參與訓練計畫推薦', () {
    // 規格：「動機類與課表內容無對應關係，參與比對只會製造雜訊」。
    test('改動機不換掉當前計畫', () {
      final s = signedUp();
      final before = s.currentPlan;
      s.updateMotiveGoal(kMotiveGoals.first);
      expect(s.currentPlan, same(before));
    });

    test('選填 —— 清得掉', () {
      final s = signedUp()..updateMotiveGoal(null);
      expect(s.motiveGoal, isNull);
    });
  });
}
