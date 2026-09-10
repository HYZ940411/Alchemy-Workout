import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/admin.dart';
import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/state/app_state.dart';

/// 建立師徒關係 —— 封鎖的連動要有東西可解除。
Instructor bindMentor(AppState s) {
  final i = s.instructors.first;
  s.applyMentor(i);
  s.acceptMentorApplication(i);
  expect(s.myInstructor, isNotNull);
  return i;
}

void main() {
  group('封鎖自動解除關注關係', () {
    test('我關注的人被封鎖 → 關注取消，對方粉絲數 −1', () {
      final s = AppState();
      const who = '深蹲王';
      expect(s.following, contains(who));
      final before = s.otherFollowerCounts[who] ?? 0;
      expect(s.blockUser(who), isTrue);
      expect(s.following, isNot(contains(who)));
      expect(s.otherFollowerCounts[who], before - 1,
          reason: '粉絲數為儲存欄位，非即時彙總，得逐處維護');
    });

    test('關注我的人被封鎖 → 也自粉絲清單移除（雙方皆解除）', () {
      final s = AppState();
      // 隊友不能封鎖，挑一個不在隊上的粉絲。
      final mates = s.myTeam!.members.map((m) => m.name).toSet();
      final who = s.followers.firstWhere((f) => !mates.contains(f));
      expect(s.blockUser(who), isTrue);
      expect(s.followers, isNot(contains(who)));
    });

    test('解除封鎖不自動恢復關注', () {
      final s = AppState();
      const who = '深蹲王';
      s.blockUser(who);
      s.unblockUser(who);
      expect(s.isBlocked(who), isFalse);
      expect(s.following, isNot(contains(who)),
          reason: '模型明訂解除封鎖不自動恢復任何已解除的關係');
    });
  });

  group('封鎖自動解除師徒關係', () {
    test('封鎖教官 → 師徒關係解除，解除原因為封鎖', () {
      final s = AppState();
      final mentor = bindMentor(s);
      expect(s.blockUser(mentor.name), isTrue);
      expect(s.mentorReleased, isTrue);
      expect(s.mentorReleaseReason, MentorReleaseReason.blocked);
    });

    test('未完成的師徒任務一併作廢', () {
      final s = AppState();
      final mentor = bindMentor(s);
      s.confirmMentorDisclaimer();
      s.assignMentorTask('本週任務', '細節');
      expect(
          s.mentorTasks.any((t) => t.state == MentorTaskState.assigned), isTrue);
      s.blockUser(mentor.name);
      expect(s.mentorTasks.any((t) => t.state == MentorTaskState.assigned),
          isFalse);
    });

    test('封鎖中不得恢復師徒關係', () {
      final s = AppState();
      final mentor = bindMentor(s);
      s.blockUser(mentor.name);
      expect(s.canRestoreMentor, isFalse,
          reason: '跟一個被自己封鎖的人維持師徒關係自相矛盾');
    });

    test('解除封鎖後仍不自動恢復，只是重新可提出', () {
      final s = AppState();
      final mentor = bindMentor(s);
      s.blockUser(mentor.name);
      s.unblockUser(mentor.name);
      expect(s.mentorReleased, isTrue, reason: '關係不會自己回來');
      expect(s.canRestoreMentor, isTrue, reason: '冷卻期內仍可雙方同意後恢復');
    });

    test('封鎖非教官的人不動師徒關係', () {
      final s = AppState();
      bindMentor(s);
      s.blockUser('Ashley');
      expect(s.mentorReleased, isFalse);
    });
  });

  group('同隊的人不能封鎖', () {
    test('隊友被擋下，且說得出理由', () {
      final s = AppState();
      final mate = s.myTeam!.members.firstWhere((m) => m.name != s.displayName);
      final reason = s.blockBlockedReason(mate.name);
      expect(reason, isNotNull);
      expect(reason, contains('退出'));
      expect(s.blockUser(mate.name), isFalse);
      expect(s.isBlocked(mate.name), isFalse);
    });

    test('退出團隊後即可封鎖', () {
      final s = AppState();
      final mate = s.myTeam!.members.firstWhere((m) => m.name != s.displayName);
      s.leaveTeam();
      expect(s.myTeam, isNull);
      expect(s.blockBlockedReason(mate.name), isNull);
      expect(s.blockUser(mate.name), isTrue);
    });

    test('沒有團隊的人不受此限', () {
      final s = AppState();
      s.leaveTeam();
      expect(s.blockUser('誰都不是'), isTrue);
    });

    test('重複封鎖同一人不產生第二筆', () {
      final s = AppState();
      expect(s.blockUser('Ashley'), isTrue);
      final n = s.blockedUsers.length;
      expect(s.blockUser('Ashley'), isFalse);
      expect(s.blockedUsers.length, n);
    });
  });

  group('封鎖不受社群功能停權限制', () {
    test('停權中仍封鎖得了 —— 那是自保，不是對外互動', () {
      final s = AppState()..punishment = null;
      for (var i = 0; i < 3; i++) {
        s.fileReport(
          target: ReportTarget.post,
          targetKey: 'post:v$i',
          content: '違規 $i',
          accused: s.displayName,
          reason: '騷擾辱罵',
        );
        final c = s.reports.first;
        s.reviewReport(c);
        s.upholdReport(c);
      }
      expect(s.communityBlocked, isTrue);
      expect(s.publishPost('停權中', PostVisibility.public),
          FilterVerdict.blocked);
      expect(s.blockUser('Ashley'), isTrue);
    });
  });
}
