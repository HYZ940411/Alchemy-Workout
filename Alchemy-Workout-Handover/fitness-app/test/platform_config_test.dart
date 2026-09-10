import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_app/main.dart';
import 'package:fitness_app/screens/admin/platform_settings_screen.dart';
import 'package:fitness_app/screens/me/more_screen.dart';

import 'package:fitness_app/domain/ability.dart';
import 'package:fitness_app/domain/admin.dart';
import 'package:fitness_app/domain/commerce.dart';
import 'package:fitness_app/domain/platform_config.dart';
import 'package:fitness_app/domain/rank.dart';
import 'package:fitness_app/domain/rewards.dart';
import 'package:fitness_app/state/app_state.dart';

/// 全域設定會在測試間互相污染，故每個測試結束就復原。
/// 還原至出廠預設 —— 平台設定為全域可變狀態，測試間必須隔離。
void _reset() => platformConfig.reset();

void main() {
  tearDown(_reset);

  group('六階門檻', () {
    test('預設門檻重現〈能力值等級〉的 18 節點分段表', () {
      const expected = [
        ['E', 0, 29], ['E+', 30, 69], ['E++', 70, 99],
        ['D', 100, 149], ['D+', 150, 199], ['D++', 200, 249],
        ['C', 250, 314], ['C+', 315, 384], ['C++', 385, 449],
        ['B', 450, 514], ['B+', 515, 584], ['B++', 585, 649],
        ['A', 650, 714], ['A+', 715, 784], ['A++', 785, 849],
        ['S', 850, 899], ['S+', 900, 949], ['S++', 950, 999],
      ];
      final nodes = kNodes;
      expect(nodes.length, expected.length);
      for (var i = 0; i < expected.length; i++) {
        expect(nodes[i].label, expected[i][0], reason: '第 $i 個節點的標籤');
        expect(nodes[i].lower, expected[i][1], reason: '${expected[i][0]} 的下緣');
        expect(nodes[i].upper, expected[i][2], reason: '${expected[i][0]} 的上緣');
      }
    });

    test('六階門檻調整後即時生效：同一個點數的等級當場改變', () {
      final s = AppState();
      expect(majorGradeOf(300), 'C');
      // 把 D 階上界從 249 拉到 320，300 點就落進 D 階。
      final failure = s.applySettings('ability', {'tier1': 320});
      expect(failure, isNull);
      expect(majorGradeOf(300), 'D');
    });

    test('不變條件：六階門檻須嚴格遞增', () {
      final s = AppState();
      // C 階上界 449 → 200，低於 D 階的 249。
      final failure = s.applySettings('ability', {'tier2': 200});
      expect(failure, isNotNull);
      expect(failure, contains('嚴格遞增'));
      // 被擋下者不留下任何痕跡：值未動，也不記變更紀錄。
      expect(platformConfig.i('ability', 'tier2'), 449);
      expect(platformConfig.log, isEmpty);
    });

    test('不變條件：連續無空隙 —— 前一階上界 +1 即次一階下界', () {
      final s = AppState();
      s.applySettings('ability', {'tier0': 120, 'tier1': 300});
      final nodes = kNodes;
      for (var i = 1; i < nodes.length; i++) {
        expect(nodes[i].lower, nodes[i - 1].upper + 1,
            reason: '${nodes[i].label} 的下緣須接在前一節點上緣之後');
      }
    });

    test('S 階上界須等於點數硬截斷上限', () {
      final s = AppState();
      expect(s.applySettings('ability', {'tier5': 900}), contains('硬截斷'));
    });
  });

  group('變更紀錄', () {
    test('Event 攜帶所變更的項目、變更前的值、變更後的值', () {
      final s = AppState();
      s.applySettings('reward', {'trainCoin': 45});
      expect(s.settingLog.length, 1);
      final c = s.settingLog.first;
      expect(c.event, '管理員已設定獎勵定義');
      expect(c.item, '訓練獎勵金幣基底');
      expect(c.before, '30');
      expect(c.after, '45');
      expect(c.by, s.admin.id);
    });

    test('前後相同者不是一次變更，不記入', () {
      final s = AppState();
      s.applySettings('reward', {'trainCoin': 30, 'checkInCoin': 12});
      expect(s.settingLog.length, 1);
      expect(s.settingLog.single.item, '簽到獎勵金幣');
    });
  });

  group('Precondition：狀態生效中且權限組涵蓋平台設定', () {
    test('權限組不含平台設定者不得執行', () {
      final s = AppState();
      s.setAdminScopes({AdminScope.contentReview});
      expect(s.canConfigure, isFalse);
      expect(s.applySettings('reward', {'trainCoin': 45}), contains('權限不足'));
      expect(kTrainingCoinBase, 30);
    });

    test('已停用者不得執行任何管理員 Command', () {
      final s = AppState();
      s.setAdminStatus(AdminStatus.disabled);
      expect(s.applySettings('reward', {'trainCoin': 45}), contains('權限不足'));
      expect(kTrainingCoinBase, 30);
    });
  });

  group('參數確實被讀取', () {
    test('獎勵定義驅動訓練與簽到的獎勵值', () {
      final s = AppState();
      s.applySettings('reward', {'trainExp': 55, 'checkInCoin': 25});
      expect(kTrainingExp, 55);
      expect(kCheckInCoin, 25);
    });

    test('會員權益驅動訂閱價格與 AI 點數配額', () {
      final s = AppState();
      s.applySettings('membership', {'monthly': 220, 'credits': 40});
      expect(kMonthlyPrice, 220);
      expect(kMonthlyAiCredits, 40);
    });

    test('年訂價格須低於月訂 ×12', () {
      final s = AppState();
      expect(s.applySettings('membership', {'yearly': 2400}), isNotNull);
    });

    test('階級門檻的滿階經驗值驅動階級推導', () {
      final s = AppState();
      final before = rankForExp(4000);
      s.applySettings('rank', {'fullExp': 4170}); // 門檻減半
      expect(rankForExp(4000), greaterThan(before));
    });

    test('Epley 次數上限驅動 1RM 估算的截斷', () {
      final s = AppState();
      expect(epley1RM(100, 20), closeTo(100 * (1 + 10 / 30), 0.001));
      s.applySettings('ability', {'epley': 15});
      expect(epley1RM(100, 20), closeTo(100 * (1 + 15 / 30), 0.001));
    });
  });

  group('補簽回補範圍', () {
    test('判定式含端點：距今天數等於回補範圍者仍可補', () {
      final s = AppState();
      final days = s.makeupDaysInRange;
      expect(days.map((d) => s.daysAgo(d.date)),
          contains(s.makeupRangeDays),
          reason: '日曆須涵蓋到端點那一天');
      expect(days.map((d) => s.daysAgo(d.date)).reduce((a, b) => a > b ? a : b),
          s.makeupRangeDays,
          reason: '最遠就到端點，不多也不少');
    });

    test('範圍縮短的當下，超出者即刻補不回來', () {
      final s = AppState();
      final day = s.makeupDaysInRange.firstWhere(
          (d) => d.state == MakeupDayState.missed && s.daysAgo(d.date) >= 3);
      expect(s.canMakeUp(day), isTrue);
      s.applySettings('makeup', {'days': 2});
      expect(s.canMakeUp(day), isFalse);
      final tickets = s.makeupTickets;
      s.useMakeupTicket(day);
      expect(s.makeupTickets, tickets, reason: '超出範圍者不得消耗補簽券');
      expect(day.state, MakeupDayState.missed);
    });

    test('回補範圍須大於 0', () {
      final s = AppState();
      expect(s.applySettings('makeup', {'days': 0}), isNotNull);
    });
  });

  group('教官初審門檻', () {
    test('兩條門檻須同時成立', () {
      final g = evaluateInstructorGate(
          rank: 19, workouts: 500, quality: 70, sanity: 70);
      expect(g.rankOk, isFalse);
      expect(g.passed, isFalse);
    });

    test('品質分折抵只折抵次數，階級門檻不折抵', () {
      final g = evaluateInstructorGate(
          rank: 5, workouts: 35, quality: 85, sanity: 70);
      expect(g.discounted, isTrue);
      expect(g.requiredWorkouts, 30);
      expect(g.workoutsOk, isTrue);
      expect(g.requiredRank, 20, reason: '階級門檻不因品質分而放寬');
      expect(g.rankOk, isFalse);
      expect(g.passed, isFalse);
    });

    test('紀錄合理性一票否決獨立於加權平均', () {
      final g = evaluateInstructorGate(
          rank: 30, workouts: 100, quality: 95, sanity: 39);
      expect(g.qualityOk, isTrue);
      expect(g.vetoed, isTrue);
      expect(g.passed, isFalse, reason: '加權平均再高也擋不住一票否決');
    });

    test('不變條件：折抵須為放寬', () {
      final s = AppState();
      expect(s.applySettings('instructorGate', {'discounted': 80}),
          contains('放寬'));
    });

    test('不變條件：折抵門檻須高於通過門檻', () {
      final s = AppState();
      expect(s.applySettings('instructorGate', {'qualityDiscount': 50}),
          isNotNull);
    });
  });

  group('教官測驗設定', () {
    test('簡答題不得歸零 —— 否則人工審核形同虛設', () {
      final s = AppState();
      expect(s.applySettings('exam', {'saCount': 0}), contains('人工審核'));
    });
  });

  group('定義類設定', () {
    test('成就門檻調整不改動既有解鎖紀錄', () {
      final s = AppState();
      final a = s.achievements.firstWhere((x) => x.unlocked);
      final name = a.name;
      s.setAchievementDefinition(a,
          threshold: a.threshold + 500, coins: a.rewardCoins, exp: a.rewardExp);
      final after = s.achievements.firstWhere((x) => x.name == name);
      expect(after.unlocked, isTrue, reason: '門檻調升不撤銷既有解鎖');
      expect(s.settingLog.single.item, contains('達成門檻'));
    });

    test('每日任務的目標改得動，進度原樣保留', () {
      final s = AppState();
      final t = s.dailyTasks.first;
      final progress = t.progress;
      s.setDailyTaskTarget(t, t.target + 3);
      expect(s.dailyTasks.first.progress, progress);
      expect(s.dailyTasks.first.target, t.target + 3);
    });

    test('設定平台動作改得動相對強度係數與預設組間休息', () {
      final s = AppState();
      final e = s.platformExercises.firstWhere((x) => x.name == '深蹲');
      final failure =
          s.setPlatformExercise(e, relativeIntensity: 0.9, restSeconds: 210);
      expect(failure, isNull);
      final after = s.exerciseById(e.id);
      expect(after.relativeIntensity, 0.9);
      expect(after.defaultRestSeconds, 210);
      expect(s.settingLog.length, 2);
    });

    test('設定訓練計畫改得動所需階級與解鎖價格', () {
      final s = AppState();
      final p = s.platformPlans.first;
      expect(s.setPlanConfig(p, requiredRank: 40, unlockCoins: 300), isNull);
      expect(s.platformPlans.first.requiredRank, 40);
      expect(s.platformPlans.first.unlockCoins, 300);
    });
  });

  group('管理員本身的維護', () {
    test('新增管理員的權限組至少 1 項', () {
      final s = AppState();
      expect(s.addAdmin('新人', {}), contains('至少 1 項'));
      expect(s.addAdmin('新人', {AdminScope.contentReview}), isNull);
      expect(s.admins.last.name, '新人');
    });

    test('不得停用自己', () {
      final s = AppState();
      final me = s.admins.firstWhere((a) => a.id == s.admin.id);
      expect(s.disableAdmin(me), contains('不得停用自己'));
      expect(s.admins.firstWhere((a) => a.id == me.id).status,
          AdminStatus.active);
    });

    test('不得停用最後一位具平台設定權限的生效中管理員', () {
      final s = AppState();
      s.addAdmin('第二位平台設定者', {AdminScope.platformConfig});
      final other = s.admins.last;
      // 目前有兩位：本人與新增的這位。停用新增的這位是允許的。
      expect(s.disableAdmin(other), isNull);
      expect(s.admins.last.status, AdminStatus.disabled);
    });

    test('停用不刪除帳號 —— 既往的判定紀錄仍可稽核', () {
      final s = AppState();
      final before = s.admins.length;
      final target = s.admins.firstWhere(
          (a) => a.id != s.admin.id && a.status == AdminStatus.active);
      s.disableAdmin(target);
      expect(s.admins.length, before);
      expect(s.admins.firstWhere((a) => a.id == target.id).status,
          AdminStatus.disabled);
    });

    test('調整權限組會同步到當前登入的管理員', () {
      final s = AppState();
      final me = s.admins.firstWhere((a) => a.id == s.admin.id);
      expect(s.setAdminScopesOf(me, {AdminScope.platformConfig}), isNull);
      expect(s.admin.scopes, {AdminScope.platformConfig});
      expect(s.settingLog.single.event, '管理員權限組已調整');
    });
  });

  group('後台走一遍', () {
    testWidgets('平台設定頁列出 16 個 Command，改一個值後變更紀錄看得到', (t) async {
      t.view.physicalSize = const Size(393 * 3, 852 * 3);
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(const FitnessApp());
      await t.pumpAndSettle();

      await t.tap(find.text('我的').last);
      await t.pumpAndSettle();
      final more = find
          .descendant(
              of: find.byType(MoreScreen), matching: find.byType(Scrollable))
          .first;
      final entry = find.descendant(
          of: find.byType(MoreScreen), matching: find.text('管理員後台'));
      await t.scrollUntilVisible(entry, 120, scrollable: more);
      await t.pumpAndSettle();
      await t.tap(entry);
      await t.pumpAndSettle();

      // 後台首頁 → 平台設定
      final gate = find.text('16 個 Command　·　訓練計畫、平台動作、成就與獎勵定義、'
          '任務範本、各項門檻、管理員帳號');
      await t.scrollUntilVisible(gate, 200);
      await t.pumpAndSettle();
      await t.tap(gate);
      await t.pumpAndSettle();

      expect(find.byType(PlatformSettingsScreen), findsOneWidget);
      expect(find.text('設定訓練計畫'), findsOneWidget);

      final reward = find.text('設定獎勵定義');
      await t.scrollUntilVisible(reward, 200);
      await t.pumpAndSettle();
      await t.tap(reward);
      await t.pumpAndSettle();

      // 訓練獎勵經驗值 30 → 45
      final field = find.byType(TextField).first;
      await t.enterText(field, '45');
      await t.pumpAndSettle();
      await t.tap(find.text('儲存設定'));
      await t.pumpAndSettle();

      // 回到平台設定頁，變更紀錄多了一列
      expect(find.byType(PlatformSettingsScreen), findsOneWidget);
      final row = find.text('管理員已設定獎勵定義　·　訓練獎勵經驗值');
      await t.scrollUntilVisible(row, 200);
      await t.pumpAndSettle();
      expect(row, findsOneWidget);
      expect(find.textContaining('30 → 45'), findsOneWidget);
    });
  });
}
