import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/mock/mock_data.dart';
import 'package:fitness_app/domain/platform_config.dart';
import 'package:fitness_app/domain/rewards.dart';
import 'package:fitness_app/state/app_state.dart';

/// 把示範時鐘挪出重新分隊期（每月前 2 天），否則團隊分數本來就不該累加。
AppState _outsideRegroup() {
  final s = AppState();
  var guard = 0;
  while (inRegroupWindow(s.now) && guard++ < 40) {
    s.advanceDemoClock(const Duration(days: 1));
  }
  return s;
}

void _train(AppState s) {
  s.startWorkout(s.platformPlans.firstWhere((p) => p.id == 'p_push'));
  s.completeCurrentSet();
  s.finishWorkout(EndKind.completed);
}

void main() {
  setUp(platformConfig.reset);
  tearDown(platformConfig.reset);

  group('團隊日常分數於成員得分時同額累加', () {
    test('訓練結算：個人加多少，團隊就加多少', () {
      final s = _outsideRegroup();
      final teamBefore = s.myTeam!.dailyScore;
      final mineBefore = s.weeklyScore;
      _train(s);
      final gained = s.weeklyScore - mineBefore;
      expect(gained, greaterThan(0));
      expect(s.myTeam!.dailyScore, teamBefore + gained, reason: '同額累加');
    });

    test('記到該成員的貢獻欄位，不是一個孤兒數字', () {
      final s = _outsideRegroup();
      final before = s.myTeam!.contributions[s.displayName]!;
      _train(s);
      expect(s.myTeam!.contributions[s.displayName], greaterThan(before));
      // 不變條件：團隊分數 ＝ 各成員貢獻的總和，且為結構上成立。
      expect(s.myTeam!.dailyScore,
          s.myTeam!.contributions.values.reduce((a, b) => a + b));
    });

    test('每日任務也算「個人排行榜分數已增加」', () {
      final s = _outsideRegroup();
      final before = s.myTeam!.dailyScore;
      s.checkIn(); // 推進「完成每日簽到」那一項
      expect(s.myTeam!.dailyScore, greaterThan(before));
    });

    test('排行榜上看得到 —— 不是只改了一個內部欄位', () {
      final s = _outsideRegroup();
      final before = s.myTeamOnBoard!.dailyScore;
      _train(s);
      expect(s.myTeamOnBoard!.dailyScore, greaterThan(before));
    });

    test('沒有團隊的人照常得個人分數', () {
      final s = _outsideRegroup();
      s.myTeam = null;
      final before = s.weeklyScore;
      _train(s);
      expect(s.weeklyScore, greaterThan(before));
    });
  });

  group('重新分隊期內團隊分數不累加，個人照常', () {
    test('每月前 2 天：團隊不動、個人照加', () {
      final s = AppState();
      // 把時鐘推到某個月的第 1 天。
      var guard = 0;
      while (!inRegroupWindow(s.now) && guard++ < 40) {
        s.advanceDemoClock(const Duration(days: 1));
      }
      expect(inRegroupWindow(s.now), isTrue);

      final team = s.myTeam!.dailyScore;
      final mine = s.weeklyScore;
      _train(s);
      expect(s.weeklyScore, greaterThan(mine), reason: '限制的是隊，不是練');
      expect(s.myTeam!.dailyScore, team);
    });
  });

  group('師徒功能解鎖：五個社群行為各一次', () {
    test('練再多次也不會解鎖 —— 條件不是訓練次數', () {
      final s = AppState();
      s.followTotal = 0;
      s.interactionTotals.updateAll((k, v) => 0);
      s.totalWorkouts = 999;
      expect(s.mentorUnlocked, isFalse);
    });

    test('五項集滿才解鎖', () {
      final s = AppState();
      s.followTotal = 0;
      s.interactionTotals.updateAll((k, v) => 0);
      expect(s.mentorUnlocked, isFalse);

      for (final k in kInteractionKinds) {
        s.interactionTotals[k] = 1;
      }
      expect(s.mentorUnlocked, isFalse, reason: '還差關注');
      s.followTotal = 1;
      expect(s.mentorUnlocked, isTrue);
    });

    test('少任何一項都不解鎖', () {
      for (final missing in ['關注', ...kInteractionKinds]) {
        final s = AppState();
        s.followTotal = missing == '關注' ? 0 : 1;
        for (final k in kInteractionKinds) {
          s.interactionTotals[k] = k == missing ? 0 : 1;
        }
        expect(s.mentorUnlocked, isFalse, reason: '缺 $missing 就不該解鎖');
      }
    });

    test('歷史行為計數：取消關注不扣回去', () {
      final s = AppState();
      s.followTotal = 0;
      s.following.clear();
      s.toggleFollow('深蹲王');
      expect(s.followTotal, 1);
      s.toggleFollow('深蹲王'); // 取消關注
      expect(s.following.contains('深蹲王'), isFalse);
      expect(s.followTotal, 1, reason: '行為發生過即為事實，事後取消不使其變為未發生');
    });

    test('單調遞增：解鎖後不會再被撤銷', () {
      final s = AppState();
      s.followTotal = 1;
      for (final k in kInteractionKinds) {
        s.interactionTotals[k] = 1;
      }
      expect(s.mentorUnlocked, isTrue);
      s.followTotal = 0;
      s.interactionTotals.updateAll((k, v) => 0);
      expect(s.mentorUnlocked, isTrue, reason: '一經設定不可撤銷');
    });

    test('進度逐項看得出來還差什麼', () {
      final s = AppState();
      s.followTotal = 0;
      s.interactionTotals.updateAll((k, v) => 0);
      s.interactionTotals['按讚'] = 3;
      final p = s.mentorUnlockProgress;
      expect(p.keys.toSet(), {'關注', ...kInteractionKinds});
      expect(p['按讚'], 3);
      expect(p['關注'], 0);
    });
  });
}
