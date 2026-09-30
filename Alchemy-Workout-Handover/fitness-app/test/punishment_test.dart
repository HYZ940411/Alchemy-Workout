import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/admin.dart';
import 'package:fitness_app/domain/commerce.dart';
import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/state/app_state.dart';

/// 把本人罰到指定的累計違規次數。級距由階梯累犯制決定，
/// 管理員只判斷檢舉是否成立 —— 故此處只是反覆判定成立。
void _punishMeTo(AppState s, int times) {
  for (var i = 0; i < times; i++) {
    s.fileReport(
      target: ReportTarget.post,
      targetKey: reportKey(ReportTarget.post, 'v$i'),
      content: '違規內容 $i',
      accused: s.displayName,
      reason: '騷擾辱罵',
    );
    final c = s.reports.first;
    s.reviewReport(c);
    s.upholdReport(c);
  }
}

void main() {
  group('處罰的功能封鎖（各處罰級距的功能對照）', () {
    test('警告不做任何功能處置，僅記次', () {
      final s = AppState()..punishment = null;
      _punishMeTo(s, 1);
      expect(s.punishment!.kind, PunishmentKind.warning);
      expect(s.myViolations, 1);
      expect(s.communityBlockedReason, isNull);
      expect(s.trainingBlockedReason, isNull);
      expect(s.commerceBlockedReason, isNull);
    });

    test('社群功能停權擋住社群互動，但不擋訓練與商城', () {
      final s = AppState()..punishment = null;
      _punishMeTo(s, 3);
      expect(s.punishment!.kind, PunishmentKind.communitySuspended);
      expect(s.communityBlockedReason, isNotNull);
      expect(s.trainingBlockedReason, isNull,
          reason: '社群功能停權不影響訓練與所有累積');
      expect(s.commerceBlockedReason, isNull);
    });

    test('永久停權擋住所有功能', () {
      final s = AppState()..punishment = null;
      _punishMeTo(s, 7);
      expect(s.punishment!.kind, PunishmentKind.permanent);
      expect(s.communityBlockedReason, isNotNull);
      expect(s.trainingBlockedReason, isNotNull);
      expect(s.commerceBlockedReason, isNotNull);
    });

    test('停權者發不出文、按不了讚、留不了言', () {
      final s = AppState()..punishment = null;
      final post = s.posts.firstWhere((p) => p.author != s.displayName);
      final likes = post.likes;
      final comments = post.comments.length;
      final n = s.posts.length;
      _punishMeTo(s, 3);
      expect(s.publishPost('停權中還想發文', PostVisibility.public),
          FilterVerdict.blocked);
      expect(s.posts.length, n, reason: '被擋下的貼文不得寫入');
      s.toggleLike(post);
      expect(post.likes, likes);
      expect(s.addComment(post, '停權中的留言'), 0);
      expect(post.comments.length, comments);
    });

    test('停權者送不出私訊、關注不了人、建不了團隊、拜不了師', () {
      final s = AppState()..punishment = null;
      final conv = s.conversations.first;
      final msgs = conv.messages.length;
      final following = Set<String>.from(s.following);
      _punishMeTo(s, 3);
      expect(s.sendMessage(conv, '嗨'), FilterVerdict.blocked);
      expect(conv.messages.length, msgs);
      s.toggleFollow('全新的人');
      expect(s.following, following);
      expect(s.createTeam('停權中建隊'), isFalse);
    });

    test('處罰撤銷後功能立刻回復', () {
      final s = AppState()..punishment = null;
      _punishMeTo(s, 3);
      expect(s.communityBlocked, isTrue);
      final a = s.appeals.first;
      s.fileAppeal('我沒有違規');
      final mine = s.appeals.firstWhere((c) => c.appellant == s.displayName);
      expect(mine, isNot(a));
      s.reviewAppeal(mine);
      s.upholdAppeal(mine);
      expect(s.punishment, isNull);
      expect(s.communityBlocked, isFalse);
      expect(s.myViolations, 2, reason: '該次違規視為不成立，累計 −1');
    });
  });

  group('處罰已到期解除', () {
    test('7 天停權在展示時鐘推過到期時戳後自動解除', () {
      final s = AppState()..punishment = null;
      _punishMeTo(s, 3);
      expect(s.communityBlocked, isTrue);
      s.advanceDemoClock(const Duration(days: 6));
      expect(s.punishment, isNotNull, reason: '未到期不得解除');
      s.advanceDemoClock(const Duration(days: 2));
      expect(s.punishment, isNull);
      expect(s.communityBlocked, isFalse);
    });

    test('封鎖判定為純函式，不在讀取時改狀態', () {
      final s = AppState()..punishment = null;
      _punishMeTo(s, 3);
      var notified = 0;
      s.addListener(() => notified++);
      // 讀取本身不得改狀態 —— 這個 getter 於 build 期間被讀，
      // 在此觸發 notifyListeners 會在畫面繪製途中重入。
      for (var i = 0; i < 5; i++) {
        s.communityBlockedReason;
        s.trainingBlockedReason;
      }
      expect(notified, 0);
      expect(s.punishment, isNotNull);
    });

    test('已到期但尚未跑到排程時，封鎖判定視同無處罰', () {
      final s = AppState()..punishment = null;
      _punishMeTo(s, 3);
      s.demoClockOffset += const Duration(days: 8); // 只推時鐘，不跑排程
      expect(s.communityBlockedReason, isNull);
      expect(s.punishment, isNotNull, reason: '讀取不負責解除');
      s.expirePunishmentIfDue();
      expect(s.punishment, isNull);
    });

    test('永久停權無到期解除', () {
      final s = AppState()..punishment = null;
      _punishMeTo(s, 7);
      s.advanceDemoClock(const Duration(days: 400));
      expect(s.punishment, isNotNull);
      expect(s.punishment!.kind, PunishmentKind.permanent);
    });

    test('警告為一次性記錄，亦無到期解除', () {
      final s = AppState()..punishment = null;
      _punishMeTo(s, 1);
      s.advanceDemoClock(const Duration(days: 400));
      expect(s.punishment, isNotNull);
    });
  });

  group('管理員已下架違規內容', () {
    test('貼文類檢舉成立 → 該貼文軟刪除，資料保留', () {
      final s = AppState();
      final c = s.reports.firstWhere((r) => r.targetKey == 'post:me-1');
      final p = s.posts.firstWhere((p) => p.id == 'me-1');
      expect(p.deleted, isFalse);
      s.reviewReport(c);
      s.upholdReport(c);
      expect(p.deleted, isTrue);
      expect(s.posts.any((x) => x.id == 'me-1'), isTrue,
          reason: '軟刪除 —— 內容本身是案件證據，硬刪會使申訴無從調閱');
    });

    test('私訊類檢舉成立 → 只下架被檢舉的那一則', () {
      final s = AppState();
      final c = s.reports.firstWhere((r) => r.target == ReportTarget.message);
      final conv = s.conversations.firstWhere((x) => x.id == 'c3');
      s.reviewReport(c);
      s.upholdReport(c);
      final down = conv.messages.where((m) => m.deleted).toList();
      expect(down.length, 1);
      expect(down.single.text, c.content);
      expect(conv.messages.any((m) => !m.deleted), isTrue,
          reason: '一句違規不該連帶抹掉雙方所有往來');
    });

    test('帳號類檢舉成立不走下架路徑', () {
      final s = AppState();
      final demo = s.reports.firstWhere((r) => r.target == ReportTarget.account);
      // **示範案件沒有 uid**，而 2026-09-28（暱稱重構階段二）起
      // 沒有 uid 就不記點 —— 記到暱稱底下等於記到「叫那個名字的人」身上。
      // 這一條要驗的是「帳號類不下架但照樣記次」，所以給它一個有 uid 的案件。
      final c = ReportCase(
        id: demo.id,
        targetKey: demo.targetKey,
        reporters: demo.reporters,
        target: ReportTarget.account,
        origin: demo.origin,
        content: demo.content,
        reason: demo.reason,
        reporterCount: demo.reporterCount,
        accused: demo.accused,
        accusedUid: 'u-被檢舉的人',
        accusedViolations: demo.accusedViolations,
        enteredAt: demo.enteredAt,
      );
      s.reports
        ..remove(demo)
        ..add(c);

      s.reviewReport(c);
      s.upholdReport(c);
      expect(s.posts.any((p) => p.deleted), isFalse);
      expect(s.violationsOf(c.accusedUid, name: c.accused),
          c.accusedViolations + 1,
          reason: '不下架，但照樣記次並觸發處罰');
    });

    test('檢舉駁回不下架任何內容', () {
      final s = AppState();
      final c = s.reports.firstWhere((r) => r.targetKey == 'post:me-1');
      s.reviewReport(c);
      s.dismissReport(c);
      expect(s.posts.firstWhere((p) => p.id == 'me-1').deleted, isFalse);
    });

    test('併入既有案件時新增一筆檢舉者紀錄，不覆蓋既有紀錄', () {
      final s = AppState();
      final c = s.reports.firstWhere((r) => r.targetKey == 'post:me-1');
      final before = c.reporters.length;
      final merged = s.fileReport(
          target: ReportTarget.post,
          targetKey: 'post:me-1',
          content: 'x',
          accused: s.displayName,
          reason: '假訊息');
      expect(merged, isFalse);
      expect(c.reporters.length, before + 1,
          reason: '檢舉者紀錄正是判斷是否為有組織惡意檢舉的依據');
      expect(c.reporterCount, 2);
    });

    test('同一則貼文自不同入口檢舉，併為同一案件', () {
      final s = AppState();
      final n = s.reports.length;
      final key = reportKey(ReportTarget.post, 'p1');
      expect(
          s.fileReport(
              target: ReportTarget.post,
              targetKey: key,
              content: 'x',
              accused: '深蹲王',
              reason: '假訊息'),
          isTrue);
      expect(
          s.fileReport(
              target: ReportTarget.post,
              targetKey: key,
              content: 'x',
              accused: '深蹲王',
              reason: '廣告垃圾'),
          isFalse,
          reason: '兩個入口拼出同一把鍵，才不會分裂成兩案');
      expect(s.reports.length, n + 1);
    });
  });

  group('教官資格一併撤銷', () {
    test('停權以上撤銷教官資格', () {
      final s = AppState()..punishment = null;
      s.isInstructor = true;
      _punishMeTo(s, 3);
      expect(s.isInstructor, isFalse);
      expect(s.instructorStage, InstructorStage.rejected);
    });

    test('警告不撤銷教官資格', () {
      final s = AppState()..punishment = null;
      s.isInstructor = true;
      _punishMeTo(s, 1);
      expect(s.isInstructor, isTrue);
    });
  });

  group('教官初始聲望', () {
    /// 一路走到成為教官。
    ///
    /// **最後一步是管理員的**：申請人只能推進到「待人工審核」，
    /// 原本這裡寫 `while (!s.isInstructor) advance...`，
    /// 假設申請人可以自己走到「已通過」。
    AppState becomeInstructor() {
      final s = AppState();
      expect(s.isInstructor, isFalse);
      var guard = 0;
      while (s.instructorStage != InstructorStage.pendingReview &&
          guard++ < 10) {
        s.advanceInstructorApplication();
      }
      expect(s.instructorStage, InstructorStage.pendingReview);
      final c = s.instructorCases
          .firstWhere((c) => c.applicant == s.displayName);
      s.runAsAdmin(s.otherReviewer, () => s.decideInstructor(c, true));
      expect(s.isInstructor, isTrue);
      return s;
    }

    test('成為教官時給予 15，不是 0', () {
      final s = becomeInstructor();
      expect(s.instructorReputation, kInstructorInitialReputation);
      expect(s.peakReputation, greaterThanOrEqualTo(15));
    });

    test('初始 15 使新教官頭幾次差評不觸及地板 0', () {
      final s = becomeInstructor();
      // 差評來自**我的學徒**。原本用 rateWeeklyInteraction ——
      // 那是我評我的教官，扣的是他的分。
      s.apprentices
        ..clear()
        ..addAll([
          const Apprentice(
              name: '小明', rank: 12, ability: {}, recentWorkouts: []),
        ]);
      s.apprenticeRatesMe('小明', 1, weekly: true); // −2
      expect(s.instructorReputation, 13);
      expect(s.instructorReputation, greaterThan(0));
    });
  });

  group('師徒週期計數器每週一 04:00 歸零', () {
    test('跨週後五個計數器全部回零', () {
      final s = AppState();
      // 評分需要有教官 —— 沒有對象就沒有「該週互動」可評。
      s.myInstructor = s.instructors.first;
      s.confirmMentorDisclaimer();
      s.askQuestion('這週的問題');
      s.assignMentorTask('本週任務', '細節');
      s.rateWeeklyInteraction(4);
      expect(s.weeklyQuestionCount, greaterThan(0));
      expect(s.ratedThisWeek, isTrue);

      s.advanceDemoClock(const Duration(days: 8));
      expect(s.weeklyQuestionCount, 0);
      expect(s.weeklyAssigned, 0);
      expect(s.ratedThisWeek, isFalse);
      expect(s.taskRatingsThisWeek, 0);
      expect(s.mentorRewardsThisWeek, 0);
    });

    test('同一週內推進時鐘不歸零', () {
      final s = AppState();
      s.myInstructor = s.instructors.first;
      s.confirmMentorDisclaimer();
      s.rateWeeklyInteraction(4);
      s.advanceDemoClock(const Duration(hours: 1));
      expect(s.ratedThisWeek, isTrue);
    });

    test('每週 3 次的獎勵上限不是終身上限', () {
      final s = AppState();
      s.confirmMentorDisclaimer();
      for (var i = 0; i < kMentorTaskRewardWeeklyCap; i++) {
        s.assignMentorTask('任務$i', '');
        final t = s.mentorTasks.firstWhere(
            (t) => t.state == MentorTaskState.assigned);
        s.completeMentorTask(t);
        s.claimMentorTask(t);
      }
      expect(s.mentorRewardCapReached, isTrue);
      s.assignMentorTask('第四個', '');
      var t = s.mentorTasks
          .firstWhere((t) => t.state == MentorTaskState.assigned);
      s.completeMentorTask(t);
      expect(s.claimMentorTask(t)!.coins, 0, reason: '本週已達上限');

      s.advanceDemoClock(const Duration(days: 8));
      s.assignMentorTask('下週的任務', '');
      t = s.mentorTasks.firstWhere((t) => t.state == MentorTaskState.assigned);
      s.completeMentorTask(t);
      expect(s.claimMentorTask(t)!.coins, greaterThan(0),
          reason: '跨週後上限重置 —— 否則週上限靜靜變成終身上限');
    });

    test('週互動評分的前提含私訊往來', () {
      final s = AppState();
      s.advanceDemoClock(const Duration(days: 8)); // 清掉假資料的本週互動
      expect(s.rateWeeklyInteraction(4), isFalse,
          reason: '該週無任何互動，不得評分');
      final conv = s.conversations.firstWhere((c) => c.peerIsInstructor);
      final mentor = s.instructors.firstWhere((i) => i.name == conv.peer);
      s.applyMentor(mentor);
      s.acceptMentorApplication(mentor);
      expect(s.myInstructor, isNotNull);
      s.sendMessage(conv, '教練這週的課表我做完了');
      expect(s.rateWeeklyInteraction(4), isTrue);
    });
  });
}
