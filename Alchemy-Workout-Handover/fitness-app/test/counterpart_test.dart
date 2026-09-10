// 需要第二個人的流程，另一半也要走得完。
//
// 先前每一條這樣的流程都只實作了「我送出」那一半：申請加入團隊之後
// 那筆申請永遠掛著，拜師之後只有「接受」一個結局，隊長邀請這條路徑
// 整個不存在。這支測試釘住的是**另一半**。

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/admin.dart';
import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/domain/inbound.dart';
import 'package:fitness_app/state/app_state.dart';

InboundRequest teamInvite(AppState s, PublicTeam t) => InboundRequest(
      id: 'i1',
      kind: InboundKind.teamInvite,
      from: '隊長甲',
      fromRank: 40,
      subject: t.name,
      sentAt: s.now,
    );

/// 一支我還沒加入、也沒滿的公開團隊。
PublicTeam openTeam(AppState s) =>
    s.publicTeams.firstWhere((t) => t.isPublic && !t.isFull);

void main() {
  group('團隊：隊長邀請這條路徑', () {
    test('接受邀請就真的進了那支隊', () {
      final s = AppState();
      s.leaveTeam();
      s.teamLeftAt = null; // 冷卻期不是這個測試要驗的東西
      final t = openTeam(s);
      final before = t.members.length;

      expect(s.receiveInbound(teamInvite(s, t)), isTrue);
      expect(s.inboxCount, 1);
      expect(s.acceptInbound(s.liveInbox.single), isTrue);

      expect(s.myTeam?.name, t.name);
      expect(s.myTeam!.members.length, before + 1,
          reason: '既有成員要留著 —— 接受邀請是加入一支隊，不是重開一支');
      expect(s.myTeam!.members.any((m) => m.name == s.displayName), isTrue);
      expect(s.inbox, isEmpty, reason: '已處理的請求不留在收件匣');
      expect(s.publicTeams.any((x) => x.name == t.name), isFalse,
          reason: '已經是我的隊了，不該還列在「可加入的公開團隊」裡');
      expect(s.myTeam!.dailyScore, t.dailyScore,
          reason: '這支隊已經掙到的分數不該因為我加入就歸零');
      expect(s.myTeam!.contributions.values.fold<int>(0, (a, b) => a + b),
          t.dailyScore,
          reason: '逐人貢獻的加總必須等於團隊分數');
    });

    test('接受一支之後，其餘團隊邀請一併作廢', () {
      final s = AppState();
      s.leaveTeam();
      s.teamLeftAt = null;
      final a = s.publicTeams[0];
      final b = s.publicTeams[1];
      s.receiveInbound(teamInvite(s, a));
      s.receiveInbound(InboundRequest(
        id: 'i2',
        kind: InboundKind.teamInvite,
        from: '隊長乙',
        fromRank: 30,
        subject: b.name,
        sentAt: s.now,
      ));
      expect(s.inboxCount, 2);

      s.acceptInbound(s.liveInbox.firstWhere((r) => r.subject == a.name));
      expect(s.liveInbox.where((r) => r.kind == InboundKind.teamInvite), isEmpty,
          reason: '一次只能屬於一個團隊，另一封邀請不可能還能接受');
    });

    test('拒絕就是拒絕 —— 沒加入，也不留在收件匣', () {
      final s = AppState();
      s.leaveTeam();
      s.teamLeftAt = null;
      final t = openTeam(s);
      s.receiveInbound(teamInvite(s, t));
      s.declineInbound(s.liveInbox.single);
      expect(s.myTeam, isNull);
      expect(s.inbox, isEmpty);
    });

    test('已經在隊裡就接不了 —— 而且說得出為什麼', () {
      final s = AppState();
      expect(s.myTeam, isNotNull, reason: '前提：預設狀態確實已在某支隊裡');
      final t = openTeam(s);
      s.receiveInbound(teamInvite(s, t));
      final r = s.liveInbox.single;
      expect(s.inboundBlockedReason(r), contains('一次只能屬於一個團隊'));
      expect(s.acceptInbound(r), isFalse);
      expect(s.myTeam!.name, isNot(t.name));
    });

    test('換隊冷卻中接不了', () {
      final s = AppState();
      s.leaveTeam();
      expect(s.switchCooldownLeft, greaterThan(Duration.zero),
          reason: '前提：剛退隊確實在冷卻中');
      s.receiveInbound(teamInvite(s, openTeam(s)));
      expect(s.inboundBlockedReason(s.liveInbox.single), contains('冷卻'));
      expect(s.acceptInbound(s.liveInbox.single), isFalse);
    });

    test('接受滿編的隊會被擋下 —— 待回應不佔名額，超收由這一刻擋', () {
      final s = AppState();
      s.leaveTeam();
      s.teamLeftAt = null;
      final full = s.publicTeams.firstWhere((t) => t.isFull,
          orElse: () => throw StateError('假資料需要一支滿編的公開團隊'));
      s.receiveInbound(teamInvite(s, full));
      expect(s.inboundBlockedReason(s.liveInbox.single), contains('已滿'));
      expect(s.acceptInbound(s.liveInbox.single), isFalse);
      expect(s.myTeam, isNull);
    });

    test('同一封邀請不會變成兩筆', () {
      final s = AppState();
      s.leaveTeam();
      final t = openTeam(s);
      expect(s.receiveInbound(teamInvite(s, t)), isTrue);
      expect(s.receiveInbound(teamInvite(s, t)), isFalse);
      expect(s.inboxCount, 1);
    });
  });

  group('團隊：我送出的加入申請，隊長會回應', () {
    AppState applied() {
      final s = AppState();
      s.leaveTeam();
      s.teamLeftAt = null;
      final t = openTeam(s);
      expect(s.applyToTeam(t), isTrue, reason: '前提：申請確實送得出去');
      return s;
    }

    test('核准就加入', () {
      final s = applied();
      final name = s.sentApplications.single.name;
      expect(s.resolveTeamApplication(name, RequestVerdict.accepted), isTrue);
      expect(s.myTeam?.name, name);
      expect(s.sentApplications, isEmpty, reason: '已定案的申請不該還掛著');
    });

    test('拒絕就失效，而且可以再申請一次', () {
      final s = applied();
      final name = s.sentApplications.single.name;
      s.resolveTeamApplication(name, RequestVerdict.rejected);
      expect(s.myTeam, isNull);
      expect(s.sentApplications, isEmpty);
      final t = s.publicTeams.firstWhere((x) => x.name == name);
      expect(s.joinBlockedReason(t), isNull, reason: '拒絕後無冷卻期');
      expect(s.applyToTeam(t), isTrue);
    });

    test('7 天沒人回應就逾期 —— 由時鐘推動，不是誰按的', () {
      final s = applied();
      expect(s.sentApplications, hasLength(1));
      s.advanceDemoClock(const Duration(days: 8));
      expect(s.sentApplications, isEmpty,
          reason: '168 小時的逾期判定要真的跑，否則申請永遠掛著');
      expect(s.myTeam, isNull);
    });

    test('還沒到期就不逾期', () {
      final s = applied();
      s.advanceDemoClock(const Duration(days: 6));
      expect(s.sentApplications, hasLength(1));
    });
  });

  group('師徒：三個終止狀態都走得到', () {
    AppState applied() {
      final s = AppState();
      s.myInstructor = null;
      final i = s.instructors.firstWhere((x) => x.apprentices < x.apprenticeCap);
      expect(s.applyMentor(i), isTrue);
      return s;
    }

    test('接受 → 師徒關係成立', () {
      final s = applied();
      final name = s.mentorApplications.single.name;
      s.resolveMentorApplication(name, RequestVerdict.accepted);
      expect(s.myInstructor?.name, name);
      expect(s.mentorApplications, isEmpty);
    });

    test('拒絕 → 關係不成立，申請釋放', () {
      final s = applied();
      final name = s.mentorApplications.single.name;
      s.resolveMentorApplication(name, RequestVerdict.rejected);
      expect(s.myInstructor, isNull);
      expect(s.mentorApplications, isEmpty,
          reason: '拒絕要釋放所佔用的帶徒名額，掛著就等於沒釋放');
    });

    test('逾期 → 同樣釋放', () {
      final s = applied();
      s.advanceDemoClock(const Duration(days: 8));
      expect(s.mentorApplications, isEmpty);
      expect(s.myInstructor, isNull);
    });

    test('教官主動邀我當學徒 —— 模型明載申請雙向皆可', () {
      final s = AppState();
      s.myInstructor = null;
      final i = s.instructors.first;
      s.receiveInbound(InboundRequest(
        id: 'm1',
        kind: InboundKind.mentorInvite,
        from: i.name,
        fromRank: i.rank,
        subject: i.name,
        sentAt: s.now,
      ));
      expect(s.acceptInbound(s.liveInbox.single), isTrue);
      expect(s.myInstructor?.name, i.name);
    });

    test('已經有教官就接不了新的邀請', () {
      final s = AppState();
      final i = s.instructors.first;
      s.myInstructor = i;
      final other = s.instructors[1];
      s.receiveInbound(InboundRequest(
        id: 'm2',
        kind: InboundKind.mentorInvite,
        from: other.name,
        fromRank: other.rank,
        subject: other.name,
        sentAt: s.now,
      ));
      expect(s.inboundBlockedReason(s.liveInbox.single),
          contains('只能有一位教官'));
      expect(s.acceptInbound(s.liveInbox.single), isFalse);
      expect(s.myInstructor?.name, i.name);
    });
  });

  group('師徒：我是教官那一側', () {
    InboundRequest apply(AppState s, String who) => InboundRequest(
          id: 'a-$who',
          kind: InboundKind.apprenticeApply,
          from: who,
          fromRank: 12,
          subject: who,
          sentAt: s.now,
        );

    test('不是教官就收不了徒', () {
      final s = AppState();
      s.isInstructor = false;
      s.receiveInbound(apply(s, '小明'));
      expect(s.inboundBlockedReason(s.liveInbox.single), contains('不是教官'));
      expect(s.acceptInbound(s.liveInbox.single), isFalse);
    });

    test('接受就多一位學徒', () {
      final s = AppState();
      s.isInstructor = true;
      s.apprentices.clear();
      s.receiveInbound(apply(s, '小明'));
      expect(s.acceptInbound(s.liveInbox.single), isTrue);
      expect(s.apprentices.map((a) => a.name), contains('小明'));
    });

    test('帶徒名額滿了就收不了', () {
      final s = AppState();
      s.isInstructor = true;
      s.apprentices
        ..clear()
        ..addAll([
          for (var i = 0; i < s.apprenticeCap; i++)
            Apprentice(
                name: '徒$i', rank: 10, ability: const {}, recentWorkouts: const [])
        ]);
      s.receiveInbound(apply(s, '小明'));
      expect(s.inboundBlockedReason(s.liveInbox.single), contains('名額已滿'));
      expect(s.acceptInbound(s.liveInbox.single), isFalse);
    });
  });

  group('收件匣本身的逾期', () {
    test('7 天沒回應就從收件匣消失', () {
      final s = AppState();
      s.leaveTeam();
      s.receiveInbound(teamInvite(s, openTeam(s)));
      expect(s.inboxCount, 1);
      s.advanceDemoClock(const Duration(days: 8));
      expect(s.inbox, isEmpty);
    });

    test('逾期的請求接不了，而且說得出為什麼', () {
      final s = AppState();
      s.leaveTeam();
      s.teamLeftAt = null;
      final r = teamInvite(s, openTeam(s));
      s.receiveInbound(r);
      // 只推時鐘，不跑掃描 —— 檢查的是「接受」自己會不會擋逾期。
      s.demoClockOffset += const Duration(days: 8);
      expect(s.inboundBlockedReason(r), contains('逾期'));
      expect(s.acceptInbound(r), isFalse);
      expect(s.myTeam, isNull);
    });
  });

  group('別人那一側的其餘動作', () {
    test('對方回訊息，會落在對話的另一邊', () {
      final s = AppState();
      final c = s.conversations.first;
      final n = c.messages.length;
      s.peerReplies(c, '收到，明天見');
      expect(c.messages.length, n + 1);
      expect(c.messages.last.fromMe, isFalse,
          reason: '對方的訊息不能記成我發的');
    });

    test('對方的違規訊息自動開案，被記名的是對方', () {
      final s = AppState();
      final c = s.conversations.first;
      final before = s.reports.length;
      expect(s.peerReplies(c, '朋友有在用類固醇'), FilterVerdict.flagged);
      expect(s.reports.length, before + 1);
      expect(s.reports.first.accused, c.peer,
          reason: '對方傳的訊息，被告的不該是我');
    });

    test('對方按讚只加讚數，不替我發獎勵', () {
      final s = AppState();
      final p = s.visiblePosts.first;
      final likes = p.likes;
      final coins = s.coins;
      final exp = s.totalExp;
      s.peerLikesPost(p);
      expect(p.likes, likes + 1);
      expect(s.coins, coins, reason: '獎勵發給按讚的人，不是被按讚的我');
      expect(s.totalExp, exp);
    });

    test('隊友完成限時任務，分數記在本隊帳上', () {
      final s = AppState();
      final t = s.myTeam!;
      // 假資料裡早鳥訓練與 Yuki 今天已經完成了 —— 挑一個還沒完成的。
      final m = t.members.firstWhere(
          (x) => x.name != s.displayName && !s.timedTask.doneBy(x.name));
      final done = s.timedTally.doneCount;
      expect(s.teammateCompletesTimedTask(m.name), isTrue);
      expect(s.timedTally.doneCount, done + 1);
      expect(s.teammateCompletesTimedTask(m.name), isFalse,
          reason: '同一個人不能完成兩次');
    });

    test('不是隊友就不能替本隊加分', () {
      final s = AppState();
      expect(s.teammateCompletesTimedTask('路人'), isFalse);
    });

    test('有人檢舉我 —— 被檢舉的那一端也走得到', () {
      final s = AppState();
      // 假資料裡我唯一那篇貼文已經掛著一件待審的案子，拿它來驗會直接走
      // 併案分支。自己發一篇乾淨的，這個測試才驗得到「開新案」。
      expect(s.publishPost('今天練腿', PostVisibility.public),
          FilterVerdict.pass);
      final p = s.visiblePosts.firstWhere((x) => x.text == '今天練腿');
      final before = s.reports.length;
      expect(s.peerReportsMe(p, '路人甲', '不實訊息'), isTrue);
      expect(s.reports.length, before + 1);
      final c = s.reports.first;
      expect(c.accused, s.displayName, reason: '被檢舉的是我');
      expect(c.reporters.single.name, '路人甲',
          reason: '檢舉者是別人 —— 記成我自己就等於我檢舉了我自己');
      expect(c.state, CaseState.pending);

      // 第二個人檢舉同一篇要併案，不是開兩案。
      expect(s.peerReportsMe(p, '路人乙', '不實訊息'), isFalse);
      expect(s.reports.length, before + 1);
      expect(s.reports.first.reporterCount, 2);
    });

    test('有人申請加入我的隊，進待處理清單', () {
      final s = AppState();
      if (!s.iAmLeader) {
        s.transferLeader(s.myTeam!.members
            .firstWhere((m) => m.name == s.displayName));
      }
      final t = s.myTeam!;
      if (t.isFull) return;
      final n = t.applications.length;
      expect(s.peerAppliesToMyTeam('小新', 20), isTrue);
      expect(t.applications.length, n + 1);
      expect(s.peerAppliesToMyTeam('小新', 20), isFalse,
          reason: '同一人重複申請不該疊加');
    });
  });

  group('檢舉 → 審核 → 處罰 → 申訴，一條走到底', () {
    test('別人檢舉我，另一位管理員判成立，我就真的被罰了', () {
      final s = AppState();
      expect(s.punishment, isNull, reason: '前提：一開始沒有處罰');
      expect(s.publishPost('今天練腿', PostVisibility.public),
          FilterVerdict.pass);
      final p = s.visiblePosts.firstWhere((x) => x.text == '今天練腿');
      s.peerReportsMe(p, '路人甲', '不實訊息');
      final c = s.reports.firstWhere((x) => x.targetKey == 'post:${p.id}');

      final who = s.otherReviewer;
      s.runAsAdmin(who, () {
        s.reviewReport(c);
        s.upholdReport(c);
      });

      expect(c.state, CaseState.upheld);
      expect(s.punishment, isNotNull, reason: '檢舉成立就該有處罰落到我身上');
      expect(s.myViolations, greaterThan(0));
      expect(p.deleted, isTrue, reason: '違規內容要下架');
    });

    test('判不成立就什麼都不發生', () {
      final s = AppState();
      expect(s.publishPost('今天練腿', PostVisibility.public),
          FilterVerdict.pass);
      final p = s.visiblePosts.firstWhere((x) => x.text == '今天練腿');
      s.peerReportsMe(p, '路人甲', '不實訊息');
      final c = s.reports.firstWhere((x) => x.targetKey == 'post:${p.id}');
      final v = s.myViolations;

      s.runAsAdmin(s.otherReviewer, () {
        s.reviewReport(c);
        s.dismissReport(c);
      });
      expect(s.punishment, isNull);
      expect(s.myViolations, v);
      expect(p.deleted, isFalse);
    });

    test('申訴成立 → 處罰撤銷、違規次數回復', () {
      final s = AppState();
      expect(s.publishPost('今天練腿', PostVisibility.public),
          FilterVerdict.pass);
      final p = s.visiblePosts.firstWhere((x) => x.text == '今天練腿');
      s.peerReportsMe(p, '路人甲', '不實訊息');
      final c = s.reports.firstWhere((x) => x.targetKey == 'post:${p.id}');
      s.runAsAdmin(s.otherReviewer, () {
        s.reviewReport(c);
        s.upholdReport(c);
      });
      final punished = s.myViolations;
      s.fileAppeal('那不是我寫的');
      final ap = s.appeals.firstWhere((x) => x.appellant == s.displayName);

      s.runAsAdmin(s.otherReviewer, () {
        s.reviewAppeal(ap);
        s.upholdAppeal(ap);
      });
      expect(s.punishment, isNull);
      expect(s.myViolations, punished - 1);
    });
  });

  group('存讀與歸零', () {
    test('收件匣跨啟動保留 —— 期限要跨啟動才算得準', () {
      final s = AppState();
      s.leaveTeam();
      s.receiveInbound(teamInvite(s, openTeam(s)));
      final snap = s.toSnapshot();

      final back = AppState();
      expect(back.applySnapshot(snap), isTrue);
      expect(back.inbox, hasLength(1));
      expect(back.inbox.single.kind, InboundKind.teamInvite);
      expect(back.inbox.single.subject, s.inbox.single.subject);
      expect(back.inbox.single.sentAt, s.inbox.single.sentAt);
    });

    test('新帳號的收件匣是空的', () {
      final s = AppState();
      s.leaveTeam();
      s.receiveInbound(teamInvite(s, openTeam(s)));
      s.resetToNewAccount();
      expect(s.inbox, isEmpty);
    });
  });
}
