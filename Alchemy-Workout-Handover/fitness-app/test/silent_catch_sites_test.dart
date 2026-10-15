// 寫入失敗，畫面卻說成功 —— `app_state.dart` 剩下的那批 `catchError((_) {})`。
//
// 2X 把「說得出話」做成通用的 `_write`，但只接上四條路，其餘十處
// （追蹤、發文互動、團隊異動、拜師申請、回答提問、刪對話、標記已讀、
// 清請求、建關係）仍然吞錯。這是同一個錯第五次。
//
// 這支測試對每一類各釘兩件事：
//   · 寫失敗 → 報告寫著失敗＋原因，而且 `lastWrite()` 讓畫面分得出來
//   · 根本沒送出（有雲端來源卻缺 uid／關係 id）→ 報告寫著沒送出
// 外加一道原始碼掃描：不准再出現吞錯的 `catchError((_) {})`。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/chat_data.dart';
import 'package:fitness_app/data/follow_data.dart';
import 'package:fitness_app/data/mentor_data.dart';
import 'package:fitness_app/data/post_data.dart';
import 'package:fitness_app/data/team_data.dart';
import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/domain/inbound.dart';
import 'package:fitness_app/screens/social/team_detail_screen.dart';
import 'package:fitness_app/state/app_state.dart';

/// 每一個寫入方法都炸。只呼叫寫入方法，所以其餘（回傳非 void 的）不會被碰到。
class _BoomTeam implements TeamSource {
  @override
  dynamic noSuchMethod(Invocation i) =>
      Future<void>.error(StateError('permission-denied'));
}

class _BoomPost implements PostSource {
  @override
  dynamic noSuchMethod(Invocation i) =>
      Future<void>.error(StateError('permission-denied'));
}

class _BoomFollow implements FollowSource {
  @override
  dynamic noSuchMethod(Invocation i) =>
      Future<void>.error(StateError('permission-denied'));
}

class _BoomMentor implements MentorSource {
  @override
  dynamic noSuchMethod(Invocation i) =>
      Future<void>.error(StateError('permission-denied'));
}

class _BoomChat implements ChatSource {
  @override
  String conversationIdOf(String a, String b) => '${a}_$b';
  @override
  dynamic noSuchMethod(Invocation i) =>
      Future<void>.error(StateError('permission-denied'));
}

/// 寫入都成功的團隊來源。
class _OkTeam implements TeamSource {
  @override
  dynamic noSuchMethod(Invocation i) => Future<void>.value();
}

Future<void> settle() => Future<void>.delayed(Duration.zero);

PublicTeam _team() => const PublicTeam('鐵人小隊', 2, 5, id: 't1');

Instructor _instructor({String? uid}) => Instructor(
      name: '阿教',
      rank: 40,
      uid: uid,
      reputation: 10,
      apprentices: 0,
      apprenticeCap: 5,
      ability: const {},
      specialties: const ['增肌'],
      avgRating: 4.5,
      ratingCount: 3,
    );

void main() {
  group('團隊異動', () {
    test('寫失敗 → 報告寫著失敗＋原因，lastWrite 回報不成功', () async {
      final s = AppState(demo: false)
        ..myUid = 'u-我'
        ..teamSource = _BoomTeam();
      expect(s.applyToTeam(_team()), isTrue);
      final r = await s.lastWrite('申請加入團隊');

      expect(r.ok, isFalse);
      expect(r.why, contains('permission-denied'));
      expect(s.cloudWriteReport['申請加入團隊'], startsWith('失敗'));
      await settle();
      expect(s.sentApplications, isEmpty, reason: '沒送達的申請不能留在「已送出」');
    });

    test('有來源卻沒有 uid → 沒送出，而不是安靜略過', () async {
      final s = AppState(demo: false)..teamSource = _BoomTeam();
      s.applyToTeam(_team());
      final r = await s.lastWrite('申請加入團隊');

      expect(r.ok, isFalse);
      expect(s.cloudWriteReport['申請加入團隊'], startsWith('沒送出'));
    });

    test('寫成功 → 報告寫著成功', () async {
      final s = AppState(demo: false)
        ..myUid = 'u-我'
        ..teamSource = _OkTeam();
      s.applyToTeam(_team());
      final r = await s.lastWrite('申請加入團隊');

      expect(r.ok, isTrue);
      expect(s.cloudWriteReport['申請加入團隊'], startsWith('成功'));
    });

    test('沒接雲端（示範、測試）→ 不是失敗，也不留報告', () async {
      final s = AppState(demo: false)..myUid = 'u-我';
      s.applyToTeam(_team());
      final r = await s.lastWrite('申請加入團隊');

      expect(r.ok, isTrue);
      expect(s.cloudWriteReport.containsKey('申請加入團隊'), isFalse);
    });

    test('不同動作各用各的名字 —— 後面的成功不會蓋掉前面的失敗', () async {
      final s = AppState(demo: false)
        ..myUid = 'u-我'
        ..teamSource = _BoomTeam();
      s.applyToTeam(_team());
      await settle();
      s.createTeam('新隊');
      await settle();

      expect(s.cloudWriteReport['申請加入團隊'], startsWith('失敗'));
      expect(s.cloudWriteReport['建立團隊'], startsWith('失敗'));
    });
  });

  group('社群與追蹤', () {
    test('按讚寫失敗 → 看得見，本機照樣先改', () async {
      final s = AppState(demo: false)
        ..myUid = 'u-我'
        ..postSource = _BoomPost();
      final p = Post(
          id: 'p1',
          author: '別人',
          authorRank: 10,
          text: '嗨',
          at: DateTime(2026, 10, 1));
      s.posts.add(p);
      s.toggleLike(p);
      final r = await s.lastWrite('按讚');

      expect(p.likedByMe, isTrue, reason: '樂觀更新照舊');
      expect(r.ok, isFalse);
      expect(s.cloudWriteReport['按讚'], startsWith('失敗'));
    });

    test('追蹤寫失敗 → 看得見', () async {
      final s = AppState(demo: false)
        ..myUid = 'u-我'
        ..followSource = _BoomFollow();
      s.toggleFollow('別人', uid: 'u-別人');
      final r = await s.lastWrite('追蹤');

      expect(r.ok, isFalse);
      expect(s.cloudWriteReport['追蹤'], startsWith('失敗'));
    });
  });

  group('師徒', () {
    test('拜師申請寫失敗 → 看得見', () async {
      final s = AppState(demo: false)
        ..myUid = 'u-我'
        ..mentorSource = _BoomMentor();
      expect(s.applyMentor(_instructor(uid: 'u-教官')), isTrue);
      final r = await s.lastWrite('拜師申請');

      expect(r.ok, isFalse);
      expect(s.cloudWriteReport['拜師申請'], startsWith('失敗'));
      await settle();
      expect(s.mentorApplications, isEmpty, reason: '沒送達的申請不能留在「已送出」');
    });

    test('認不出教官是誰 → 沒送出（原本畫面照說「已送出」）', () async {
      final s = AppState(demo: false)
        ..myUid = 'u-我'
        ..mentorSource = _BoomMentor();
      s.applyMentor(_instructor()); // 沒有 uid、公開檔案裡也查不到
      final r = await s.lastWrite('拜師申請');

      expect(r.ok, isFalse);
      expect(s.cloudWriteReport['拜師申請'], startsWith('沒送出'));
    });

    test('教官自己帶著 uid 時，不靠暱稱反查也送得出去', () async {
      final s = AppState(demo: false)
        ..myUid = 'u-我'
        ..mentorSource = _BoomMentor();
      s.applyMentor(_instructor(uid: 'u-教官'));
      await settle();

      expect(s.cloudWriteReport['拜師申請'], isNot(startsWith('沒送出')),
          reason: '有 uid 就該送出去（這裡因為來源會炸而失敗，但不是「沒送出」）');
    });

    MentorQuestion q({String? uid}) => MentorQuestion(
        from: '學徒', text: '怎麼練', at: DateTime(2026, 10, 1), apprenticeUid: uid);

    test('回答寫失敗 → 看得見', () async {
      final s = AppState(demo: false)
        ..myUid = 'u-教官'
        ..mentorSource = _BoomMentor();
      expect(s.answerQuestion(q(uid: 'u-學徒'), '多喝水'), isTrue);
      final r = await s.lastWrite('回答提問');

      expect(r.ok, isFalse);
      expect(s.cloudWriteReport['回答提問'], startsWith('失敗'));
    });

    test('算不出關係 id → 沒送出，學徒永遠收不到', () async {
      final s = AppState(demo: false)
        ..myUid = 'u-教官'
        ..mentorSource = _BoomMentor();
      s.answerQuestion(q(), '多喝水'); // 提問沒有學徒 uid
      final r = await s.lastWrite('回答提問');

      expect(r.ok, isFalse);
      expect(s.cloudWriteReport['回答提問'], startsWith('沒送出'));
    });
  });

  group('師徒：接受／拒絕請求', () {
    InboundRequest invite({String? fromUid = 'u-教官'}) => InboundRequest(
          id: 'mi-1',
          kind: InboundKind.mentorInvite,
          from: '阿教',
          fromUid: fromUid,
          fromRank: 40,
          subject: '阿教',
          sentAt: DateTime.now(),
        );

    test('接受後建關係寫失敗 → 看得見', () async {
      final s = AppState(demo: false)
        ..myUid = 'u-我'
        ..mentorSource = _BoomMentor();
      final r = invite();
      s.receiveInbound(r);
      expect(s.acceptInbound(r), isTrue);
      await settle();

      expect(s.cloudWriteReport['建立師徒關係'], startsWith('失敗'));
    });

    test('接受時認不出對方 → 關係「沒送出」', () async {
      final s = AppState(demo: false)
        ..myUid = 'u-我'
        ..mentorSource = _BoomMentor();
      final r = invite(fromUid: null); // 沒有 uid、暱稱也反查不到
      s.receiveInbound(r);
      s.acceptInbound(r);
      await settle();

      expect(s.cloudWriteReport['建立師徒關係'], startsWith('沒送出'));
    });

    test('拒絕後清雲端請求寫失敗 → 看得見（否則下次登入它又跑出來）', () async {
      final s = AppState(demo: false)
        ..myUid = 'u-我'
        ..mentorSource = _BoomMentor();
      final r = invite();
      s.receiveInbound(r);
      s.declineInbound(r);
      await settle();

      expect(s.cloudWriteReport['清除師徒請求'], startsWith('失敗'));
    });
  });

  group('私訊', () {
    Conversation conv() => Conversation(
        id: 'c1', peer: '朋友', peerUid: 'u-朋友', peerRank: 10);

    test('標記已讀寫失敗 → 看得見', () async {
      final s = AppState(demo: false)
        ..myUid = 'u-我'
        ..chatSource = _BoomChat();
      s.markRead(conv());
      final r = await s.lastWrite('標記已讀');

      expect(r.ok, isFalse);
      expect(s.cloudWriteReport['標記已讀'], startsWith('失敗'));
    });

    test('刪除對話寫失敗 → 看得見；認不出對方則是沒送出', () async {
      final s = AppState(demo: false)
        ..myUid = 'u-我'
        ..chatSource = _BoomChat();
      s.deleteConversation(conv());
      expect((await s.lastWrite('刪除對話')).ok, isFalse);
      expect(s.cloudWriteReport['刪除對話'], startsWith('失敗'));

      s.deleteConversation(
          Conversation(id: 'c2', peer: '陌生人', peerRank: 5)); // 沒有 peerUid
      expect(s.cloudWriteReport['刪除對話'], startsWith('沒送出'));
    });
  });

  group('畫面看回傳值', () {
    testWidgets('申請寫失敗時，提示不能說「已送出」', (tester) async {
      final s = AppState(demo: false)
        ..myUid = 'u-我'
        ..teamSource = _BoomTeam();
      await tester.pumpWidget(AppScope(
        state: s,
        child: MaterialApp(home: TeamDetailScreen(team: _team())),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('申請加入'));
      await tester.pumpAndSettle();

      expect(find.textContaining('申請沒有送達'), findsOneWidget);
      expect(find.textContaining('已送出申請'), findsNothing,
          reason: 'toast 與頁面上的「已送出申請，等隊長回應」都不能再說謊');
      expect(s.sentApplications, isEmpty, reason: '沒送達的申請要拿掉，才能重送');
    });
  });

  test('app_state.dart 不再有吞錯的 catchError((_) {})／catchError((Object _) {})', () {
    final src = File('lib/state/app_state.dart').readAsLinesSync();
    final bad = <int>[
      for (var i = 0; i < src.length; i++)
        if ((src[i].contains('catchError((_) {})') ||
                src[i].contains('catchError((Object _) {})')) &&
            !src[i].trimLeft().startsWith('//'))
          i + 1
    ];
    expect(bad, isEmpty, reason: '第 ${bad.join('、')} 行又在吞錯了');
  });
}
