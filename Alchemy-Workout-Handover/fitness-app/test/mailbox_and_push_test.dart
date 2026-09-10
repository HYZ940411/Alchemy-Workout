import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/commerce.dart';
import 'package:fitness_app/domain/rewards.dart';
import 'package:fitness_app/domain/novice_wrapup.dart';
import 'package:fitness_app/domain/social.dart';
import 'package:fitness_app/state/app_state.dart';

int pushes(AppState s, String event) =>
    s.notifications.where((n) => n.sourceEvent == event).length;

void main() {
  group('信箱領到的就是信箱上寫的', () {
    test('逐筆領取照實發放，經驗值與道具都算', () {
      final s = AppState();
      final m = s.mailbox.firstWhere((m) => !m.claimed && m.exp > 0);
      final coins = s.coins;
      final exp = s.totalExp;
      s.claimMail(m);
      expect(s.coins, coins + m.coins);
      expect(s.totalExp, exp + m.exp, reason: '經驗值原本一分都沒發');
    });

    test('補簽券也發得到', () {
      final s = AppState();
      final m = s.mailbox.firstWhere((m) => !m.claimed && m.makeupTickets > 0);
      final t = s.makeupTickets;
      s.claimMail(m);
      expect(s.makeupTickets, t + m.makeupTickets);
    });

    test('一鍵全部領取的總額等於各筆相加', () {
      final s = AppState();
      final pending = s.mailbox.where((m) => !m.claimed).toList();
      final coins = pending.fold<int>(0, (a, m) => a + m.coins);
      final exp = pending.fold<int>(0, (a, m) => a + m.exp);
      expect(coins, greaterThan(0));
      final c0 = s.coins;
      final e0 = s.totalExp;
      s.claimAllMail();
      expect(s.coins, c0 + coins);
      expect(s.totalExp, e0 + exp);
    });

    test('顯示文字由數額推導，不會與實發對不起來', () {
      final m = MailReward(source: 'x', coins: 300, exp: 120, at: DateTime.now());
      expect(m.content, '金幣 300 ＋ 經驗值 120');
      expect(MailReward(source: 'x', coins: 6, at: DateTime.now()).content,
          '金幣 6');
    });

    test('已領取者不重複發放', () {
      final s = AppState();
      final m = s.mailbox.firstWhere((m) => !m.claimed);
      s.claimMail(m);
      final coins = s.coins;
      s.claimMail(m);
      expect(s.coins, coins);
    });

    test('排行獎勵進信箱時帶的是該名次的實際數額', () {
      final s = AppState();
      final before = s.mailbox.length;
      s.settleWeekly();
      if (s.mailbox.length == before) return; // 未達獎勵名次
      final m = s.mailbox.first;
      expect(m.coins + m.exp, greaterThan(0));
      expect(m.isEmpty, isFalse);
    });
  });

  group('待回應類三則推播', () {
    test('拜師申請送出時發推播', () {
      final s = AppState();
      final n = pushes(s, '使用者已申請師徒關係');
      s.applyMentor(s.instructors.first);
      expect(pushes(s, '使用者已申請師徒關係'), n + 1);
      expect(s.notifications.first.priority, NotifyPriority.expiring,
          reason: '不處理就失效，屬第 1 級');
    });

    test('隊長邀請成員時發推播', () {
      final s = AppState();
      final n = pushes(s, '隊長已邀請成員');
      s.inviteMember('新朋友', 20);
      expect(pushes(s, '隊長已邀請成員'), n + 1);
    });

    test('申請加入團隊時發推播', () {
      final s = AppState();
      s.leaveTeam();
      // 退隊後有 12 小時換隊冷卻，先等過去。
      s.advanceDemoClock(const Duration(hours: 13));
      final n = pushes(s, '使用者已申請加入團隊');
      s.applyToTeam(
          s.publicTeams.firstWhere((t) => s.joinBlockedReason(t) == null));
      expect(pushes(s, '使用者已申請加入團隊'), n + 1);
    });
  });

  group('訓練提醒', () {
    test('有時段來源就每日一則', () {
      final s = AppState();
      // 先清掉訓練紀錄，斷掉「依訓練時戳推算」那條來源 ——
      // 這條測的是偏好時段那一條，兩條來源同時在就分不出是哪一條發的。
      s.history.clear();
      s.setPreferredTimes(PreferredTimes.empty());
      expect(s.reminderAvailable, isFalse);
      s.setPreferredTimes(PreferredTimes.empty()
          .withRange(0, const TimeRange(1200, 1260)));
      expect(s.reminderAvailable, isTrue);
      final n = pushes(s, '訓練提醒已發送');
      s.advanceDemoClock(const Duration(days: 1));
      expect(pushes(s, '訓練提醒已發送'), n + 1);
      expect(s.sendTrainingReminderIfDue(), isFalse, reason: '同一天只發一則');
    });

    test('沒有任何時段來源就不發 —— 猜的提醒不如不發', () {
      final s = AppState();
      s.setPreferredTimes(PreferredTimes.empty());
      s.history.clear();
      expect(s.reminderAvailable, isFalse);
      final n = pushes(s, '訓練提醒已發送');
      s.advanceDemoClock(const Duration(days: 1));
      expect(pushes(s, '訓練提醒已發送'), n);
    });
  });

  group('補簽提醒屬第 1 級', () {
    test('期限即將失效類，不是行動引導類', () {
      final s = AppState();
      s.checkIn();
      s.advanceDemoClock(const Duration(days: 3));
      final n = s.notifications
          .firstWhere((n) => n.sourceEvent == '補簽提醒已發送');
      expect(n.priority, NotifyPriority.expiring,
          reason: '回補範圍只有 7 天，過了就補不回來');
    });
  });

  group('同一件商品只有一個價格', () {
    test('商城的解鎖價與平台參數一致', () {
      final s = AppState();
      final p = s.products.firstWhere((p) => p.name.contains('進階訓練計畫'));
      expect(p.specs.first.coinPrice, kPlanUnlockCoins);
    });

    test('調整參數，商城的價格跟著動', () {
      final s = AppState()..adminMode = true;
      expect(s.applySettings('commerce', {'planUnlockCoins': 700}), isNull);
      final p = s.products.firstWhere((p) => p.name.contains('進階訓練計畫'));
      expect(p.specs.first.coinPrice, 700);
    });
  });

  group('課表選擇頁的自訂訓練欄位', () {
    test('自訂訓練帶來源免責標示，官方計畫不帶', () {
      final s = AppState();
      final mine = s.selectableCustomPlans.first.toWorkoutPlan();
      expect(mine.disclaimer, isNotNull);
      expect(s.platformPlans.first.disclaimer, isNull);
    });

    test('練過之後帶得出上次訓練日期與完成度', () {
      final s = AppState();
      final c = s.selectableCustomPlans.first;
      expect(c.lastTrainedAt, isNull);
      s.startWorkout(c.toWorkoutPlan());
      s.completeCurrentSet();
      s.finishWorkout(EndKind.endedEarly);
      expect(c.lastTrainedAt, isNotNull);
      expect(c.lastCompletion, isNotNull);
      expect(c.toWorkoutPlan().lastTrainedAt, isNotNull);
    });
  });
}
