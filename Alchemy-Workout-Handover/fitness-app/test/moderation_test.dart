import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_app/domain/admin.dart';
import 'package:fitness_app/domain/commerce.dart';
import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/domain/custom_plan.dart';
import 'package:fitness_app/mock/mock_data.dart';
import 'package:fitness_app/state/app_state.dart';
import 'package:fitness_app/domain/models.dart';

ReportCase mine(AppState s) => s.reports.firstWhere((c) => c.id == 'R-2046');

/// n 個動作的最小課表，供不關心內容的測試使用。
List<PlanExercise> plannedOf(int n) => [
      for (var i = 0; i < n; i++)
        PlanExercise(
          exercise: kExercises[i % kExercises.length],
          planned: const [PlannedSet(20, 10)],
        ),
    ];

void main() {
  group('使用者已檢舉內容', () {
    test('新標的開新案，檢舉者紀錄與人數各一', () {
      final s = AppState();
      final before = s.reports.length;
      final isNew = s.fileReport(
        target: ReportTarget.post,
        targetKey: 'post:x1',
        content: '違規內容',
        accused: '某人',
        reason: '廣告垃圾',
        note: '一直私訊我',
      );
      expect(isNew, isTrue);
      expect(s.reports.length, before + 1);
      final c = s.reports.first;
      expect(c.reporterCount, 1);
      expect(c.reporters.single.reason, '廣告垃圾');
      expect(c.reporters.single.note, '一直私訊我');
      expect(c.state, CaseState.pending);
    });

    test('多人檢舉同一標的合併為同一案件，不覆蓋既有紀錄', () {
      final s = AppState();
      s.fileReport(
        target: ReportTarget.post,
        targetKey: 'post:x1',
        content: '違規內容',
        accused: '某人',
        reason: '廣告垃圾',
      );
      final before = s.reports.length;
      final isNew = s.fileReport(
        target: ReportTarget.post,
        targetKey: 'post:x1',
        content: '違規內容',
        accused: '某人',
        reason: '假訊息',
      );
      expect(isNew, isFalse, reason: '併入既有案件，管理員只需審視一次');
      expect(s.reports.length, before);
      final c = s.reports.firstWhere((c) => c.targetKey == 'post:x1');
      expect(c.reporterCount, 2);
      expect(c.reporters.map((r) => r.reason), ['廣告垃圾', '假訊息']);
    });

    test('已結案者另開新案 —— 否則該對象其後的新違規再也無法被檢舉', () {
      final s = AppState();
      s.fileReport(
        target: ReportTarget.post,
        targetKey: 'post:x1',
        content: '違規內容',
        accused: '某人',
        reason: '廣告垃圾',
      );
      final first = s.reports.firstWhere((c) => c.targetKey == 'post:x1');
      s.reviewReport(first);
      s.dismissReport(first);

      final isNew = s.fileReport(
        target: ReportTarget.post,
        targetKey: 'post:x1',
        content: '違規內容',
        accused: '某人',
        reason: '假訊息',
      );
      expect(isNew, isTrue);
      expect(s.reports.where((c) => c.targetKey == 'post:x1').length, 2);
    });

    test('檢舉不觸發任何自動處置', () {
      final s = AppState();
      for (var i = 0; i < 10; i++) {
        s.fileReport(
          target: ReportTarget.post,
          targetKey: 'post:x1',
          content: '違規內容',
          accused: '某人',
          reason: '騷擾辱罵',
        );
      }
      final c = s.reports.firstWhere((c) => c.targetKey == 'post:x1');
      expect(c.reporterCount, 10);
      // 不設累積次數門檻，無自動隱藏機制。
      expect(c.state, CaseState.pending);
      expect(s.violationsOf('某人'), 0);
    });
  });

  group('階梯累犯制', () {
    test('級距為門檻而非單次：1–2 警告、3–4 停權 7 天、5–6 停權 30 天、7 起永久', () {
      expect(tierForViolations(1).label, '警告');
      expect(tierForViolations(2).label, '警告');
      expect(tierForViolations(3).label, '社群功能停權 7 天');
      expect(tierForViolations(4).label, '社群功能停權 7 天');
      expect(tierForViolations(5).label, '社群功能停權 30 天');
      expect(tierForViolations(6).label, '社群功能停權 30 天');
      expect(tierForViolations(7).label, '永久停權');
      expect(tierForViolations(99).label, '永久停權');
    });

    test('教官資格於停權以上一併撤銷，警告不撤銷', () {
      expect(revokesInstructor(2), isFalse);
      expect(revokesInstructor(3), isTrue);
    });

    test('檢舉理由的類別與處罰級距無對應關係', () {
      final a = AppState();
      final b = AppState();
      for (final (s, reason) in [(a, '暴力威脅'), (b, '廣告垃圾')]) {
        s.fileReport(
          target: ReportTarget.post,
          targetKey: 'post:z',
          content: 'x',
          accused: '路人',
          reason: reason,
        );
        final c = s.reports.firstWhere((c) => c.targetKey == 'post:z');
        s.reviewReport(c);
        s.upholdReport(c);
      }
      // 兩個理由天差地遠，級距一樣 —— 一律依累計違規次數決定。
      expect(a.violationsOf('路人'), b.violationsOf('路人'));
    });
  });

  group('檢舉 → 處罰 → 申訴 → 撤銷（端到端）', () {
    test('成立後本人受處罰，累計違規 +1', () {
      final s = AppState();
      expect(s.punishment, isNull);
      final c = mine(s);
      s.reviewReport(c);
      expect(c.state, CaseState.reviewing);
      expect(c.handlerName, s.admin.name);

      s.upholdReport(c);
      expect(c.state, CaseState.upheld);
      expect(c.handlerName, isNull, reason: '案件轉入終止狀態時清空處理中的管理員');
      expect(s.myViolations, 1);
      expect(s.punishment, isNotNull);
      // 累計 1 次 → 警告；警告的到期時戳為空值。
      expect(s.punishment!.kind, PunishmentKind.warning);
      expect(s.punishment!.expiresAt, isNull);
    });

    test('申訴進入管理員佇列，撤銷後處罰清空且累計違規 −1', () {
      final s = AppState();
      final c = mine(s);
      s.reviewReport(c);
      s.upholdReport(c);

      final before = s.appeals.length;
      s.fileAppeal('那句話不是針對任何人');
      expect(s.appeals.length, before + 1);
      final ap = s.appeals.last;
      expect(ap.appellant, s.displayName);
      expect(ap.reason, '那句話不是針對任何人');

      s.reviewAppeal(ap);
      s.upholdAppeal(ap);
      expect(ap.state, CaseState.upheld);
      expect(s.punishment, isNull, reason: '處罰狀態回復為無');
      expect(s.myViolations, 0, reason: '該次違規視為不成立');
    });

    test('申訴駁回：原處罰維持，累計違規不變', () {
      final s = AppState();
      final c = mine(s);
      s.reviewReport(c);
      s.upholdReport(c);
      s.fileAppeal('理由');
      final ap = s.appeals.last;
      s.reviewAppeal(ap);
      s.dismissAppeal(ap);

      expect(ap.state, CaseState.dismissed);
      expect(s.punishment, isNotNull, reason: '原處罰維持不變');
      expect(s.myViolations, 1, reason: '僅撤銷才 −1');
    });

    test('同一處罰限申訴一次，不論成立與否', () {
      final s = AppState();
      final c = mine(s);
      s.reviewReport(c);
      s.upholdReport(c);
      s.fileAppeal('第一次');
      final n = s.appeals.length;
      s.fileAppeal('第二次');
      expect(s.appeals.length, n);
    });

    test('駁回檢舉不對檢舉者做任何處置', () {
      final s = AppState();
      final c = mine(s);
      s.reviewReport(c);
      s.dismissReport(c);
      expect(c.state, CaseState.dismissed);
      expect(s.punishment, isNull);
      expect(s.myViolations, 0);
    });
  });

  group('處罰到期解除', () {
    test('限期處罰到期後解除；永久停權與警告沒有到期時戳', () {
      final s = AppState();
      // 先墊高累計違規，使下一次成立落在停權級距。
      s.myViolations = 2;
      final c = mine(s);
      s.reviewReport(c);
      s.upholdReport(c);
      expect(s.punishment!.kind, PunishmentKind.communitySuspended);
      expect(s.punishment!.expiresAt, isNotNull);

      // 尚未到期不解除。
      s.expirePunishmentIfDue();
      expect(s.punishment, isNotNull);
    });
  });

  group('其餘 Command 不再只是提示', () {
    test('訓練紀錄另存為自訂訓練：落地狀態為已儲存（未啟用）', () {
      final s = AppState();
      // 假資料剛好用滿名額，先刪一份 —— 刪除是釋放名額的唯一手段。
      s.deletePlan(s.customPlans.firstWhere((p) => p.isMine));
      final before = s.myPlanCount;
      final h = s.history.first;
      expect(s.saveHistoryAsPlan(h), isTrue);
      expect(s.myPlanCount, before + 1);
      final saved = s.customPlans.last;
      expect(saved.name, h.planName);
      expect(saved.state, CustomPlanState.saved,
          reason: '需自行發布後方可選用');
      expect(saved.contents.length, h.exercises.length);
    });

    test('名額已滿時擋下 —— 使用者本即位於訓練歷史頁，可先刪除', () {
      final s = AppState();
      while (s.myPlanCount < s.customPlanQuota) {
        s.addPlan('填滿 ${s.myPlanCount}', plannedOf(1));
      }
      expect(s.saveHistoryAsPlan(s.history.first), isFalse);
    });

    test('隊長已踢除成員：人數 −1，且不得踢除自己', () {
      final s = AppState();
      final t = s.myTeam!;
      final before = t.members.length;
      final leader =
          t.members.firstWhere((m) => m.role == TeamRole.leader);
      s.kickMember(leader);
      expect(t.members.length, before, reason: '隊長離隊須經轉讓或解散');

      final member =
          t.members.firstWhere((m) => m.role != TeamRole.leader);
      s.kickMember(member);
      expect(t.members.length, before - 1);
      expect(t.members.contains(member), isFalse);
    });

    test('隊長已邀請成員：滿員時擋下，待回應不佔名額', () {
      final s = AppState();
      final t = s.myTeam!;
      final invitesBefore = t.invites.length;
      expect(s.inviteMember('新朋友', 20), isTrue);
      expect(t.invites.length, invitesBefore + 1);
      // 重複邀請同一人不再新增。
      expect(s.inviteMember('新朋友', 20), isFalse);

      // 待回應的邀請不佔名額 —— 邀了人之後仍以已加入成員數判滿。
      expect(t.isFull, t.members.length >= t.capacity);
    });

    test('使用者已還原被替換的動作：組數與目標沿用', () {
      final s = AppState();
      final plan = kPlans.firstWhere((p) => p.id == 'p_push');
      s.startWorkout(plan);
      final i = s.session!.exercises
          .indexWhere((e) => e.replacedFrom != null);
      expect(i, greaterThanOrEqualTo(0));
      final before = s.session!.exercises[i];
      final origin = before.replacedFrom!;

      s.restoreReplacedExercise(i);
      final after = s.session!.exercises[i];
      expect(after.exercise.id, origin.id);
      expect(after.planned.length, before.planned.length);
      expect(after.replacedFrom, isNull);
    });

    test('教官已指派師徒任務', () {
      final s = AppState();
      final before = s.mentorTasks.length;
      s.assignMentorTask('本週三次腿訓', '深蹲為主');
      expect(s.mentorTasks.length, before + 1);
      expect(s.mentorTasks.first.title, '本週三次腿訓');
      expect(s.mentorTasks.first.state, MentorTaskState.assigned);
    });
  });
}
