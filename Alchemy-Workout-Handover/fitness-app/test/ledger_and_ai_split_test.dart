import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/commerce.dart';
import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/domain/decay.dart';
import 'package:fitness_app/state/app_state.dart';

/// 不變條件：最新一筆的「異動後餘額」須等於當前的兩個餘額欄位。
void expectLedgerBalanced(AppState s, {String? reason}) {
  expect(s.creditHistory, isNotEmpty, reason: reason);
  final last = s.creditHistory.first;
  expect(last.monthlyAfter, s.aiMonthly, reason: reason);
  expect(last.permanentAfter, s.aiPermanent, reason: reason);
}

void main() {
  group('AI 點數異動一律留下紀錄', () {
    test('每月配發', () {
      final s = AppState();
      s.subscribe(yearly: false);
      final n = s.creditHistory.length;
      s.advanceDemoClock(const Duration(days: 35));
      expect(s.creditHistory.length, greaterThan(n),
          reason: '餘額變了就要有一筆紀錄');
      expect(s.creditHistory.first.kind, CreditChange.monthlyGrant);
      expectLedgerBalanced(s);
    });

    test('會員權益生效', () {
      final s = AppState();
      final n = s.creditHistory.length;
      s.subscribe(yearly: false);
      expect(s.creditHistory.length, n + 1);
      expect(s.aiMonthly, kMonthlyAiCredits);
      expectLedgerBalanced(s);
    });

    test('會員權益失效', () {
      final s = AppState();
      s.subscribe(yearly: false);
      s.cancelSubscription();
      s.advanceDemoClock(const Duration(days: 32));
      expect(s.aiMonthly, 0);
      expectLedgerBalanced(s, reason: '歸零也是異動');
    });

    test('新手任務獎勵的 AI 點數', () {
      final s = AppState();
      s.startNovice();
      s.selectNovice(s.noviceCandidates.first.id);
      s.toggleNoviceCheck();
      s.finishNovice();
      expect(s.noviceFinished, isTrue);
      final before = s.aiPermanent;
      final r = s.claimNoviceReward();
      expect(r, isNotNull);
      expect(s.aiPermanent, before + r!.ai);
      expect(s.creditHistory.first.kind, CreditChange.gift);
      expectLedgerBalanced(s);
    });

    test('扣點與退還照舊有紀錄', () {
      final s = AppState();
      s.startWorkout(s.platformPlans.first);
      s.aiRequest(AiSource.beforeTraining, '想調整');
      s.aiConfirmDemand(AiSource.beforeTraining, '整體降強度');
      s.aiProduceSuggestion(AiSource.beforeTraining);
      expectLedgerBalanced(s);
      expect(s.creditHistory.first.kind, CreditChange.deduct);
    });

    test('任何一次餘額變動之後，流水都對得起來', () {
      final s = AppState();
      s.subscribe(yearly: false);
      s.advanceDemoClock(const Duration(days: 35));
      s.startWorkout(s.platformPlans.first);
      s.aiRequest(AiSource.beforeTraining, '想調整');
      s.aiConfirmDemand(AiSource.beforeTraining, '整體降強度');
      s.aiProduceSuggestion(AiSource.beforeTraining);
      expectLedgerBalanced(s);
    });
  });

  group('兩條訓練前 AI 路徑是兩件事', () {
    test('主動要求的訓練前微調不涉及自訂訓練名額', () {
      final s = AppState();
      // 騰出一個名額 —— 名額滿時分流本來就不擋，那樣驗不到東西。
      s.deletePlan(s.customPlans.firstWhere((p) => p.isMine));
      expect(s.customPlanSlotFree, isTrue);
      expect(s.aiQuotaConsent, isFalse, reason: '尚未確認任何名額意願');
      s.startWorkout(s.platformPlans.first);
      final plans = s.customPlans.length;
      s.aiRequest(AiSource.beforeTraining, '想調整');
      expect(s.aiStage[AiSource.beforeTraining], AiStage.clarifying,
          reason: '不該被名額確認擋下來');
      s.aiConfirmDemand(AiSource.beforeTraining, '整體降強度');
      s.aiProduceSuggestion(AiSource.beforeTraining);
      s.aiAccept(AiSource.beforeTraining);
      expect(s.aiStage[AiSource.beforeTraining], AiStage.applied);
      expect(s.customPlans.length, plans,
          reason: '只改本次快照，不落地為自訂訓練');
    });

    test('器材解鎖後的課表調整才走名額分流', () {
      expect(aiUsesPlanQuota(AiSource.planAdjust), isTrue);
      expect(aiUsesPlanQuota(AiSource.beforeTraining), isFalse);
      expect(aiUsesPlanQuota(AiSource.duringTraining), isFalse);
      expect(aiUsesPlanQuota(AiSource.autoOptimize), isFalse);
    });

    test('四條路徑各自獨立，互不干擾', () {
      final s = AppState();
      s.startWorkout(s.platformPlans.first);
      s.aiRequest(AiSource.beforeTraining, '想調整');
      expect(s.aiStage[AiSource.planAdjust], AiStage.idle,
          reason: '另一條路徑不該被帶著走');
      expect(AiSource.values.length, 4);
    });

    test('自動優化不扣點，其餘三條扣點', () {
      expect(aiCostsCredit(AiSource.autoOptimize), isFalse);
      for (final s in AiSource.values) {
        if (s != AiSource.autoOptimize) expect(aiCostsCredit(s), isTrue);
      }
    });
  });

  group('連簽有自己的階段，沒有「已退步」那一階', () {
    test('三道門檻各自對應一個階段', () {
      expect(checkInStageOf(0), CheckInStage.normal);
      expect(checkInStageOf(25), CheckInStage.warned);
      expect(checkInStageOf(40), CheckInStage.broken);
      expect(checkInStageOf(50), CheckInStage.makeupReminded);
    });

    test('最高階為「已提醒補簽」，不會停在能力值的階段上', () {
      expect(checkInStageOf(9999), CheckInStage.makeupReminded);
      expect(CheckInStage.values.length, 4);
      expect(checkInStageNames[CheckInStage.makeupReminded], '已提醒補簽');
    });

    test('推進到 48 小時之後，兩則通知各發一次', () {
      final s = AppState();
      s.checkIn();
      final warn = s.notifications
          .where((n) => n.sourceEvent == '連簽中斷預告已發送')
          .length;
      final makeup =
          s.notifications.where((n) => n.sourceEvent == '補簽提醒已發送').length;
      s.advanceDemoClock(const Duration(days: 3)); // 一次跨過三階
      expect(
          s.notifications
              .where((n) => n.sourceEvent == '連簽中斷預告已發送')
              .length,
          warn + 1);
      expect(s.notifications.where((n) => n.sourceEvent == '補簽提醒已發送').length,
          makeup + 1);
    });
  });
}
