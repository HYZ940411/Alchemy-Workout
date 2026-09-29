// 即時訂閱（`[BE-16]`，2026-09-24）。
//
// 在此之前 `lib/data/` 底下**沒有任何 `.snapshots()`** —— 貼文、團隊、
// 私訊、師徒、關注全都只在登入那一刻讀一次（`AuthGate._syncProfile`）。
// 所以 B 已經登入著、A 這時傳訊息給他，B 要把 App 完全重新載入才看得到。
// 使用者實際撞到的說法是「發出之後沒有上雲，刷新後就不見了」——
// 其實雲端好端端的，是這一側從來不再讀第二次。
//
// 2026-09-18 先補了下拉重新整理當代償，這次做真的。
//
// ## 這一版的三個取捨
//
//   · **訊號不帶內容**：收到「有東西變了」之後跑既有的 `refreshInbound()`，
//     不在訂閱裡再解析一次文件。解析與併入那一層已經被測過，複製一份
//     只會讓兩份慢慢長不一樣 —— 這個專案有一整排 bug 就是這樣來的。
//   · **查詢條件逐字照抄既有的 `.get()`**：那組條件已通過線上的安全規則
//     與索引。`bond()` 那次就是自己湊了一組查詢，被規則整個拒絕，
//     而呼叫端即發即忘吞掉錯誤 —— 畫面成功、雲端什麼都沒發生。
//   · **貼文與關注刻意不訂**：按讚會改到貼文文件，任何人按一個讚就讓
//     所有在線的人重抓 50 篇貼文連同留言。動態牆已經有下拉重新整理。

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/chat_data.dart';
import 'package:fitness_app/data/cloud_watch.dart';
import 'package:fitness_app/data/mentor_data.dart';
import 'package:fitness_app/data/team_data.dart';
import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/state/app_state.dart';

/// 比防抖動間隔長一點 —— 等重讀真的被觸發。
Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 600));

// ── 假來源 ───────────────────────────────────────────────

class _FakeChats implements ChatSource {
  /// 每呼叫一次 `watchConversations()` 就發一條新的 —— 這樣才看得出
  /// 「重新訂閱時舊的那條有沒有被收掉」。共用一條的話兩種寫法
  /// 長得一模一樣。
  final issued = <StreamController<void>>[];
  int reads = 0;

  bool get watched => issued.isNotEmpty;
  StreamController<void> get ping => issued.last;

  @override
  Stream<void> watchConversations() {
    final c = StreamController<void>.broadcast();
    issued.add(c);
    return c.stream;
  }

  @override
  Future<List<CloudConversation>> conversations({int limit = 50}) async {
    reads++;
    return const [];
  }

  @override
  String conversationIdOf(String a, String b) => ([a, b]..sort()).join('_');
  @override
  Future<void> send(String peerUid, CloudMessage m,
      {required String myName, required String peerName}) async {}
  @override
  Future<void> markRead(String conversationId) async {}
  @override
  Future<void> deleteForMe(String conversationId) async {}
}

class _FakeTeams implements TeamSource {
  @override
  Future<void> addScore(String teamId, String uid, int delta) async {}
  @override
  Future<void> creditTimed(String teamId, String uid, String day) async {}

  final issued = <StreamController<void>>[];
  String? watchedTeamId;
  int reads = 0;

  bool get watched => issued.isNotEmpty;
  StreamController<void> get ping => issued.last;

  @override
  Stream<void> watchTeams({String? myTeamId}) {
    watchedTeamId = myTeamId;
    final c = StreamController<void>.broadcast();
    issued.add(c);
    return c.stream;
  }

  @override
  Future<CloudTeam?> myTeam() async {
    reads++;
    return null;
  }

  @override
  Future<List<TeamRequest>> requestsFor(String uid,
          {String? myTeamId, List<String>? errors}) async =>
      const [];
  @override
  Future<List<CloudTeam>> openTeams({int limit = 30}) async => const [];
  @override
  Future<void> create(CloudTeam t) async {}
  @override
  Future<void> putMember(String teamId, String uid, CloudMember m) async {}
  @override
  Future<void> removeMember(String teamId, String uid) async {}
  @override
  Future<void> setVisibility(String teamId, bool isPublic) async {}
  @override
  Future<void> disband(String teamId) async {}
  @override
  Future<void> sendRequest(TeamRequest r) async {}
  @override
  Future<void> dropRequest(String teamId, String uid) async {}
}

class _FakeMentor implements MentorSource {
  final issued = <StreamController<void>>[];
  int bondReads = 0;
  List<CloudBond> cloudBonds = const [];

  bool get watched => issued.isNotEmpty;
  StreamController<void> get ping => issued.last;

  @override
  Stream<void> watchMentor() {
    final c = StreamController<void>.broadcast();
    issued.add(c);
    return c.stream;
  }

  @override
  Future<List<CloudBond>> bonds() async {
    bondReads++;
    return cloudBonds;
  }

  @override
  Future<List<MentorRequest>> requestsFor(String uid) async => const [];

  @override
  Future<List<MentorRequest>> sentRequests() async => const [];
  @override
  Future<void> bond(CloudBond b) async {}
  @override
  Future<void> release(
      String bondId, MentorReleaseReason reason, DateTime at) async {}
  @override
  Future<void> recover(String bondId, DateTime now) async {}
  @override
  Future<List<CloudMentorTask>> tasks(String bondId) async => const [];
  @override
  Future<void> putTask(String bondId, CloudMentorTask t) async {}
  @override
  Future<List<CloudQuestion>> questions(String bondId) async => const [];
  @override
  Future<void> ask(String bondId, CloudQuestion q) async {}
  @override
  Future<void> answer(
      String bondId, String questionId, String text, DateTime at) async {}
  @override
  Future<void> sendRequest(MentorRequest r) async {}
  @override
  Future<void> dropRequest(String requestId) async {}
}

({AppState s, _FakeChats chats, _FakeTeams teams, _FakeMentor mentor}) _wired() {
  final chats = _FakeChats();
  final teams = _FakeTeams();
  final mentor = _FakeMentor();
  final s = AppState(demo: false)
    ..myUid = 'u-me'
    ..chatSource = chats
    ..teamSource = teams
    ..mentorSource = mentor;
  addTearDown(() {
    s.stopCloudWatch();
    for (final c in [...chats.issued, ...teams.issued, ...mentor.issued]) {
      c.close();
    }
  });
  return (s: s, chats: chats, teams: teams, mentor: mentor);
}

void main() {
  group('mergeWatches', () {
    test('丟掉每條來源的第一筆 —— 那是掛上訂閱時的現況快照', () async {
      final a = StreamController<void>();
      final got = <void>[];
      final sub = mergeWatches([a.stream]).listen(got.add);

      a.add(null); // 現況快照
      await Future<void>.delayed(Duration.zero);
      expect(got, isEmpty, reason: '第一筆是登入時已經讀過的資料');

      a.add(null); // 真的變了
      await Future<void>.delayed(Duration.zero);
      expect(got, hasLength(1));

      await sub.cancel();
      await a.close();
    });

    test('每條來源各自丟第一筆，不是整體只丟一筆', () async {
      final a = StreamController<void>();
      final b = StreamController<void>();
      final got = <void>[];
      final sub = mergeWatches([a.stream, b.stream]).listen(got.add);

      a.add(null);
      b.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(got, isEmpty);

      a.add(null);
      b.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(got, hasLength(2));

      await sub.cancel();
      await a.close();
      await b.close();
    });

    test('一條壞掉，其他條照常', () async {
      final a = StreamController<void>();
      final b = StreamController<void>();
      final got = <void>[];
      final sub = mergeWatches([a.stream, b.stream]).listen(got.add);

      a.add(null);
      b.add(null);
      await Future<void>.delayed(Duration.zero);

      // 安全規則擋下其中一條查詢就長這樣。
      a.addError(Exception('permission-denied'));
      b.add(null);
      await Future<void>.delayed(Duration.zero);

      expect(got, hasLength(1), reason: 'b 那條要還活著');

      // **出錯的那條自己也要還活著**（`cancelOnError: false`）。
      // Firestore 的訂閱在權限被拒時會直接結束，但斷線重連那類的
      // 錯誤不會 —— 收掉訂閱的話那條就再也醒不過來了，而畫面上
      // 看起來只是「對方傳的訊息沒出現」。
      a.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(got, hasLength(2), reason: '出錯過的來源要繼續收訊號');

      await sub.cancel();
      await a.close();
      await b.close();
    });

    test('來源丟出錯誤不會炸到呼叫端', () async {
      final a = StreamController<void>();
      final sub = mergeWatches([a.stream]).listen((_) {});
      a.add(null);
      await Future<void>.delayed(Duration.zero);

      // 沒有 onError 的話這個錯誤會漏到 zone 去 —— 在 App 裡就是
      // 一個沒人接的例外，而它的來源是「某條監聽被規則擋下」，
      // 跟使用者當下在做的事毫無關係。
      a.addError(Exception('permission-denied'));
      await Future<void>.delayed(Duration.zero);

      await sub.cancel();
      await a.close();
    });

    test('取消時所有來源一起收掉', () async {
      final a = StreamController<void>();
      final b = StreamController<void>();
      final sub = mergeWatches([a.stream, b.stream]).listen((_) {});
      await Future<void>.delayed(Duration.zero);
      expect(a.hasListener, isTrue);
      expect(b.hasListener, isTrue);

      await sub.cancel();
      expect(a.hasListener, isFalse, reason: '漏收的訂閱會一直燒讀取額度');
      expect(b.hasListener, isFalse);

      await a.close();
      await b.close();
    });
  });

  group('開始與停止訂閱', () {
    test('三條都訂起來', () {
      final w = _wired();
      w.s.startCloudWatch();

      expect(w.chats.watched, isTrue);
      expect(w.teams.watched, isTrue);
      expect(w.mentor.watched, isTrue);
      expect(w.s.isWatchingCloud, isTrue);
    });

    test('團隊那條帶著我的隊伍 ID —— 別人的申請掛在隊伍底下', () {
      final w = _wired();
      w.s.applyCloudTeam(CloudTeam(
        id: 't1',
        name: '鐵血',
        members: {
          'u-me': CloudMember(
              name: '我', rank: 1, role: TeamRole.leader, joinedAt: DateTime(2026)),
        },
      ));

      w.s.startCloudWatch();

      // null 的話隊長永遠看不到有人申請加入 —— 那批請求不掛在我身上。
      expect(w.teams.watchedTeamId, 't1');
    });

    test('沒接來源就不訂，也不會爆', () {
      final s = AppState(demo: false)..myUid = 'u-me';
      s.startCloudWatch();
      expect(s.isWatchingCloud, isFalse);
      addTearDown(s.stopCloudWatch);
    });

    test('重新訂閱時舊的那條要先收掉', () {
      final w = _wired();
      w.s.startCloudWatch();
      // `myTeam` 換了就得重訂（團隊那條要帶新的隊伍 ID），
      // 所以這支本來就會被叫第二次。
      w.s.startCloudWatch();

      expect(w.chats.issued, hasLength(2));
      // 不收的話 Firestore 那一側會掛著兩個監聽，各自燒讀取額度，
      // 而且停一次停不完。
      expect(w.chats.issued.first.hasListener, isFalse,
          reason: '第一次訂的那條要被收掉');
      expect(w.chats.issued.last.hasListener, isTrue);
    });

    test('停掉之後一條都不剩', () {
      final w = _wired();
      w.s.startCloudWatch();
      w.s.stopCloudWatch();
      for (final c in [...w.chats.issued, ...w.teams.issued, ...w.mentor.issued]) {
        expect(c.hasListener, isFalse);
      }
    });

    test('停掉之後訊號不再引發重讀', () async {
      final w = _wired();
      w.s.startCloudWatch();
      w.s.stopCloudWatch();

      w.chats.ping.add(null);
      await _settle();

      expect(w.chats.reads, 0);
      expect(w.s.isWatchingCloud, isFalse);
    });

    test('dispose 會收掉訂閱', () {
      final w = _wired();
      w.s.startCloudWatch();
      w.s.dispose();
      expect(w.chats.ping.hasListener, isFalse);
    });
  });

  group('訊號會觸發重讀', () {
    test('私訊有變動 → 重新讀一次對話', () async {
      final w = _wired();
      w.s.startCloudWatch();
      expect(w.chats.reads, 0, reason: '前提：訂閱本身不該先讀一次');

      w.chats.ping.add(null);
      await _settle();

      expect(w.chats.reads, 1);
    });

    test('師徒有變動 → 關係本身也重讀，不只是申請', () async {
      final w = _wired();
      w.s.startCloudWatch();

      w.mentor.ping.add(null);
      await _settle();

      // `refreshInbound()` 原本只讀 `requestsFor()`。B 按下「接受拜師」
      // 之後 A 要看到的是一段新關係 —— 那在 `bonds()` 裡，
      // 而那筆申請反而被刪掉了。少這一段，訊號來了畫面也不會變。
      expect(w.mentor.bondReads, 1);
    });

    test('接受拜師之後，另一側收得到那段關係', () async {
      final w = _wired();
      w.s.startCloudWatch();
      expect(w.s.myInstructor, isNull, reason: '前提：本來沒有教官');

      w.mentor.cloudBonds = [
        CloudBond(
          id: 'u-師父_u-me',
          mentorUid: 'u-師父',
          apprenticeUid: 'u-me',
          mentorName: '老王',
          apprenticeName: '我',
          state: MentorBondState.active,
          bondedAt: DateTime(2026, 9, 24),
        ),
      ];
      w.mentor.ping.add(null);
      await _settle();

      expect(w.s.myInstructor?.name, '老王');
    });

    test('連續三次變動只重讀一趟 —— 一個動作常常連帶好幾筆文件', () async {
      final w = _wired();
      w.s.startCloudWatch();

      w.chats.ping.add(null);
      w.chats.ping.add(null);
      w.chats.ping.add(null);
      await _settle();

      expect(w.chats.reads, 1);
    });

    test('隔得夠開的兩次變動要各重讀一次', () async {
      final w = _wired();
      w.s.startCloudWatch();

      w.chats.ping.add(null);
      await _settle();
      w.chats.ping.add(null);
      await _settle();

      expect(w.chats.reads, 2, reason: '防抖動不該把後來的變動吃掉');
    });

    test('開發者模式看得到訂了什麼、醒過幾次', () async {
      final w = _wired();
      w.s.startCloudWatch();
      expect(w.s.cloudWatchReport.keys, containsAll(['私訊', '團隊', '師徒']));

      w.chats.ping.add(null);
      await _settle();

      // 「完全沒有訊號」與「根本沒訂上」在畫面上長得一模一樣。
      expect(w.s.cloudWatchReport['私訊'], contains('1 次'));
    });
  });
}
