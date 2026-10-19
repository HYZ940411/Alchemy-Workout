import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/ability.dart';
import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/domain/models.dart';
import 'package:fitness_app/domain/novice_wrapup.dart';
import 'package:fitness_app/main.dart';
import 'package:fitness_app/screens/me/more_screen.dart';
import 'package:fitness_app/state/app_state.dart';

/// 我是教官，手上有一位學徒 —— 會動到**我的**聲望的那一側。
AppState withApprentice() {
  final s = AppState()..isInstructor = true;
  s.apprentices
    ..clear()
    ..addAll([
      const Apprentice(name: '小明', rank: 12, ability: {}, recentWorkouts: []),
    ]);
  return s;
}

AppState withMentor() {
  final s = AppState()..myUid = 'u-me';
  final ins = s.instructors.first;
  s.applyMentor(ins);
  s.acceptMentorApplication(ins);
  s.confirmMentorDisclaimer();
  return s;
}

void main() {
  group('教官聲望與帶徒上限', () {
    test('聲望地板為 0，扣分不使其低於 0', () {
      expect(applyReputation(1, -5), 0);
      expect(applyReputation(10, -3), 7);
    });

    test('帶徒上限由聲望門檻推導，最大 5 人', () {
      expect(apprenticeCapFor(0), kApprenticeCapInitial);
      expect(apprenticeCapFor(75), 3);
      expect(apprenticeCapFor(150), 4);
      expect(apprenticeCapFor(300), kApprenticeCapMax);
      expect(apprenticeCapFor(9999), kApprenticeCapMax,
          reason: '達最大值後聲望再高也不增加');
    });

    test('上限單調遞增 —— 聲望掉下來不跟著降', () {
      // 動到**我的**聲望的只有「我的學徒評我」。
      // 這裡原本用 rateWeeklyInteraction —— 那是我以學徒身分評我的教官，
      // 加到的是他的數字，不是我的。
      final s = withApprentice();
      for (var i = 0; i < 10; i++) {
        s.apprenticeWeeklyRated.clear();
        s.apprenticeRatesMe('小明', 5, weekly: true); // +12
      }
      final cap = s.apprenticeCap;
      expect(cap, greaterThan(kApprenticeCapInitial));
      for (var i = 0; i < 60; i++) {
        s.apprenticeWeeklyRated.clear();
        s.apprenticeRatesMe('小明', 1, weekly: true); // -2
      }
      expect(s.instructorReputation, 0);
      expect(s.apprenticeCap, cap, reason: '模型沒有「帶徒上限已降低」這個 Event');
    });

    test('每週互動評分的幅度遠大於單次任務評分', () {
      expect(kWeeklyInteractionReputationDelta[4], 12);
      expect(kMentorTaskReputationDelta[4], 3);
    });

    test('每週最多評一次互動；未評不算差評', () {
      final s = withMentor();
      // 我評的是我的教官，動的是他的聲望。
      final before = s.myInstructor!.reputation;
      expect(s.rateWeeklyInteraction(5), isTrue);
      expect(s.rateWeeklyInteraction(1), isFalse, reason: '每週只評得了一次');
      expect(s.myInstructor!.reputation, greaterThan(before));
    });

    test('任務評分每週最多 2 次計入聲望，超出仍可評只是不計分', () {
      final s = withMentor();
      final tasks = s.mentorTasks;
      for (final t in tasks) {
        t.state = MentorTaskState.done;
      }
      var rep = s.instructorReputation;
      var counted = 0;
      for (final t in tasks) {
        s.rateMentorTask(t, 5);
        if (s.instructorReputation > rep) counted++;
        rep = s.instructorReputation;
      }
      expect(counted, lessThanOrEqualTo(kMentorTaskRatingWeeklyCap));
      for (final t in tasks) {
        expect(t.rating, 5, reason: '該擋的是計分，不是評分行為');
      }
    });
  });

  group('師徒任務獎勵每週上限', () {
    test('超過 3 次後任務照常完成，只是不再發獎', () {
      final s = withMentor();
      for (var i = 0; i < 5; i++) {
        s.mentorTasks.add(MentorTask(title: 't$i', detail: ''));
      }
      var paid = 0;
      for (final t in s.mentorTasks) {
        s.completeMentorTask(t);
        t.state = MentorTaskState.done; // 教官發放獎勵是另一端的動作；這裡要驗的是領取上限，直接放行。
        final r = s.claimMentorTask(t);
        if (r != null && r.exp > 0) paid++;
        expect(t.state, MentorTaskState.claimed);
      }
      expect(paid, kMentorTaskRewardWeeklyCap);
    });
  });

  group('師徒關係的終止與恢復', () {
    test('解除為單方面，未完成的任務作廢', () {
      final s = withMentor();
      s.mentorTasks.add(MentorTask(title: '未做完', detail: ''));
      s.releaseMentor(MentorReleaseReason.byApprentice);
      expect(s.mentorReleased, isTrue);
      expect(
        s.mentorTasks.every((t) => t.state != MentorTaskState.assigned),
        isTrue,
      );
    });

    test('恢復需雙方同意 —— 我不能自己同意自己提出的', () {
      // 2026-09-30：在此之前 `mentorRestorePending` 是本機布林值，
      // 「提出」與「同意」出現在同一台裝置上，自己按兩下就恢復了。
      final s = withMentor()..releaseMentor(MentorReleaseReason.byApprentice);
      expect(s.proposeRestore(), isTrue);
      expect(s.mentorReleased, isTrue, reason: '還沒同意就還沒恢復');

      expect(s.acceptRestore(), isFalse,
          reason: '提出的是我 —— 這一顆不該按得動，否則就是單方面恢復');
      expect(s.mentorReleased, isTrue);
    });

    test('對方提出，我才同意得了', () {
      final s = withMentor()..releaseMentor(MentorReleaseReason.byApprentice);
      // 雲端讀回來：提出的是對方。
      s.mentorRestoreProposedBy = s.myInstructor!.uid ?? 'u-對方';
      expect(s.mentorRestoreAwaitingMe, isTrue);

      expect(s.acceptRestore(), isTrue);
      expect(s.mentorReleased, isFalse);
    });

    test('已經有人提出了就不重複提 —— 否則會蓋掉對方那筆', () {
      final s = withMentor()..releaseMentor(MentorReleaseReason.byApprentice);
      s.mentorRestoreProposedBy = 'u-對方';
      expect(s.proposeRestore(), isFalse);
      expect(s.mentorRestoreProposedBy, 'u-對方');
    });

    test('拒絕後該筆提議失效，3 天內可再次提出', () {
      final s = withMentor()..releaseMentor(MentorReleaseReason.byApprentice);
      s.mentorRestoreProposedBy = 'u-對方';
      s.rejectRestore();
      expect(s.mentorRestorePending, isFalse);
      expect(s.proposeRestore(), isTrue, reason: '失效的是那筆提議，不是整段關係');
    });

    test('冷卻期滿即不可恢復，關係就此結束', () {
      final s = withMentor()..releaseMentor(MentorReleaseReason.byApprentice);
      s.advanceDemoClock(kMentorReleaseCooldown + const Duration(hours: 1));
      expect(s.canRestoreMentor, isFalse);
      expect(s.proposeRestore(), isFalse);
      s.finalizeMentorRelease();
      expect(s.myInstructor, isNull);
    });

    test('恢復是同一筆關係轉回生效中，不新建一筆', () {
      final s = withMentor();
      final ins = s.myInstructor;
      s.releaseMentor(MentorReleaseReason.byApprentice);
      s.mentorRestoreProposedBy = 'u-對方';
      s.acceptRestore();
      expect(s.myInstructor, same(ins));
      expect(s.mentorReleaseReason, isNull, reason: '清空解除時戳與原因');
    });
  });

  group('教官測驗與指導責任聲明', () {
    test('作答後停在待人工審核 —— 簡答題不是當場放行', () {
      final s = AppState()..instructorStage = InstructorStage.screenPassed;
      expect(s.submitExam(18), isTrue);
      expect(s.instructorStage, InstructorStage.pendingReview);
      expect(s.examMcPassed, isTrue);
    });

    test('重考間隔 14 天，無次數上限', () {
      final s = AppState()..instructorStage = InstructorStage.screenPassed;
      s.submitExam(10);
      s.instructorStage = InstructorStage.testing;
      expect(s.submitExam(20), isFalse, reason: '14 天內不得重考');
      s.advanceDemoClock(const Duration(days: 15));
      expect(s.submitExam(20), isTrue);
    });

    test('未確認指導責任聲明者不得指派師徒任務', () {
      final s = AppState()..isInstructor = true;
      expect(s.instructorDutyNeeded, isTrue);
      final n = s.mentorTasks.length;
      s.assignMentorTask('先做這個', '三組');
      expect(s.mentorTasks.length, n, reason: '擋的是教官端的 Command');

      s.confirmInstructorDuty();
      s.assignMentorTask('先做這個', '三組');
      expect(s.mentorTasks.length, n + 1);
    });

    test('撤銷教官資格會一併解除既有師徒關係', () {
      final s = withMentor()..isInstructor = true;
      s.confirmInstructorDuty();
      s.revokeInstructor();
      expect(s.isInstructor, isFalse);
      expect(s.mentorReleaseReason, MentorReleaseReason.revoked);
      expect(s.instructorDutyVersion, isNull, reason: '再次成為教官須重新確認');
    });
  });

  group('貼文與留言的編修', () {
    test('編輯保留完整歷史版本，並標記已編輯', () {
      final s = AppState();
      final p = s.posts.firstWhere((x) => x.author == s.displayName,
          orElse: () => s.posts.first);
      p.text = '原文';
      final mine = Post(
          id: 'x', author: s.displayName, authorRank: 1, text: '原文',
          at: DateTime.now());
      s.posts.add(mine);
      expect(s.editPost(mine, '改過的'), isTrue);
      expect(mine.text, '改過的');
      expect(mine.edited, isTrue);
      expect(mine.edits.single.$1, '原文');
    });

    test('別人的貼文編輯不動', () {
      final s = AppState();
      final other = s.posts.firstWhere((x) => x.author != s.displayName);
      expect(s.editPost(other, '亂改'), isFalse);
    });

    test('刪除為軟刪除：動態牆看不到，但資料還在', () async {
      final s = AppState();
      final mine = Post(
          id: 'y', author: s.displayName, authorRank: 1, text: 'hi',
          at: DateTime.now());
      s.posts.add(mine);
      final n = s.visiblePosts.length;
      expect(await s.deletePost(mine), isNull);
      expect(s.visiblePosts.length, n - 1);
      expect(s.posts.contains(mine), isTrue,
          reason: '貼文可被檢舉，硬刪除會使案件失去證據');
    });

    test('留言刪除同樣是軟刪除，且隱藏但保留', () async {
      final s = AppState();
      final p = s.posts.first;
      s.addComment(p, '我的留言');
      final c = p.comments.last;
      final n = p.visibleComments.length;
      expect(await s.deleteComment(c), isNull);
      expect(p.visibleComments.length, n - 1);
      expect(p.comments.contains(c), isTrue);
    });

    test('取消按讚不倒扣任務進度 —— 已發放的獎勵不回收', () {
      final s = AppState();
      final p = s.posts.firstWhere((x) => !x.likedByMe);
      final task = s.dailyTasks.firstWhere(
          (t) => t.sourceEvent == '使用者已按讚',
          orElse: () => s.dailyTasks.first);
      s.toggleLike(p);
      final progress = task.progress;
      s.toggleLike(p);
      expect(p.likedByMe, isFalse);
      expect(task.progress, progress);
    });
  });

  group('刪除對話', () {
    test('單方刪除：我這側看不到，資料仍在', () {
      final s = AppState();
      final c = s.conversations.first;
      final n = s.visibleConversations.length;
      s.deleteConversation(c);
      expect(s.visibleConversations.length, n - 1);
      expect(s.conversations.contains(c), isTrue,
          reason: '對方仍看得到這段對話');
      expect(c.messages, isNotEmpty, reason: '單則訊息一經發送即不可刪除');
    });
  });

  group('兩個系統排程', () {
    test('日快照每個業務日一筆，同一天不重複產生', () {
      final s = AppState();
      final n = s.snapshots.length;
      expect(s.takeAbilitySnapshot(), isFalse, reason: '同一天不再產生');
      s.advanceDemoClock(const Duration(days: 1));
      expect(s.snapshots.length, n + 1);
      s.takeAbilitySnapshot();
      expect(s.snapshots.length, n + 1);
    });

    test('快照存的是當下的六維值', () {
      final s = AppState();
      s.points[Dim.chest] = 777;
      s.advanceDemoClock(const Duration(days: 1));
      final newest = s.snapshots.keys.reduce((a, b) => a < b ? a : b);
      expect(s.snapshots[newest]![Dim.chest], 777);
    });

    test('月度重置只動月度額度，永久點數不動', () {
      final s = AppState();
      final permanent = s.aiPermanent;
      s.aiMonthly = 3;
      s.advanceDemoClock(const Duration(days: 40));
      expect(s.aiPermanent, permanent, reason: '永久點數不重置不過期');
      expect(s.aiMonthly, isNot(3));
    });

    test('非會員重置後月度額度為 0', () {
      final s = AppState();
      expect(s.isMember, isFalse);
      s.advanceDemoClock(const Duration(days: 40));
      expect(s.aiMonthly, 0);
    });
  });

  group('訓練計畫的體驗評分', () {
    test('每人每份計畫終身一次，換一份計畫才會再問', () {
      final s = AppState();
      s.rateExperience(RatingTarget.trainingPlan, 'plan-a', 4);
      s.rateExperience(RatingTarget.trainingPlan, 'plan-a', 2);
      expect(s.experienceRatings.length, 1);
      s.rateExperience(RatingTarget.trainingPlan, 'plan-b', 5);
      expect(s.experienceRatings.length, 2);
    });
  });

  group('自建動作', () {
    test('建立後進得了「我的動作」—— 原本只回傳給呼叫端，從沒寫回任何地方', () {
      final s = AppState();
      final n = s.myExercises.length;
      final e = Exercise(
        id: 'c_new',
        name: '彈力帶側平舉',
        dim: Dim.shoulders,
        relativeIntensity: 0,
        isCustom: true,
        equipment: '彈力繩',
      );
      expect(s.createCustomExercise(e), isTrue);
      expect(s.myExercises.length, n + 1);
      expect(s.myExercises.first.name, '彈力帶側平舉');
    });

    test('同名的自建動作不重複建立', () {
      final s = AppState();
      final dup = Exercise(
        id: 'c_dup',
        name: s.myExercises.first.name,
        dim: Dim.core,
        relativeIntensity: 0,
        isCustom: true,
      );
      expect(s.createCustomExercise(dup), isFalse);
    });
  });

  group('自建動作走一遍', () {
    testWidgets('「我的動作」分頁讀的是狀態，不是那份 const 清單', (t) async {
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
          of: find.byType(MoreScreen), matching: find.text('動作庫'));
      await t.scrollUntilVisible(entry, 120, scrollable: more);
      await t.pumpAndSettle();
      await t.tap(entry);
      await t.pumpAndSettle();

      // 從清單本身建得起來 —— 原本只有訓練中與課表編輯器兩個入口。
      expect(find.byIcon(Icons.add), findsWidgets);

      AppScope.of(t.element(find.byType(Scaffold).first)).createCustomExercise(
        Exercise(
          id: 'c_probe',
          name: '彈力帶臉拉',
          dim: Dim.shoulders,
          relativeIntensity: 0,
          isCustom: true,
          equipment: '啞鈴',
        ),
      );
      await t.pumpAndSettle();

      await t.tap(find.text('我的動作'));
      await t.pumpAndSettle();
      expect(find.text('彈力帶臉拉'), findsOneWidget);
    });
  });
}
