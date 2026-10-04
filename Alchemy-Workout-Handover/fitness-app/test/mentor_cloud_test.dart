// 師徒不再是單機的（2026-09-24）。
//
// 2026-09-24 掃描 `lib/data/` 的 31 支介面方法時查出 `MentorSource` 有
// 四支寫好了卻沒有人呼叫。後果是**整個師徒功能只存在於本機**：
//   · 接受拜師／收徒後，雲端完全沒有這筆關係，兩邊重整就消失
//   · 三天內恢復關係只在自己這側生效，對方看到的仍是已解除
//   · 學徒提問進不到教官那裡，而雙方都不會看到任何錯誤
//
// 而使用者回報的是更前面一層：**連要拜誰為師都看不到**。
// `instructors` 是 `demo ? buildInstructors() : []` —— 真實帳號一律空清單，
// 而拜師頁就是跑這份清單。師徒功能從入口就是斷的。
//
// `answer` 不在這個檔案裡：那不是漏接，是教官側的本機模型還沒做
// （`answerQuestion()` 只有一個計數器）。見 `[BE-15]`。

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/clock.dart';
import 'package:fitness_app/data/mentor_data.dart';
import 'package:fitness_app/data/public_profile.dart';
import 'package:fitness_app/domain/ability.dart';
import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/domain/inbound.dart';
import 'package:fitness_app/state/app_state.dart';

/// 假的雲端師徒層。只記下寫了什麼。
class _FakeMentor implements MentorSource {

  /// 恢復提議。只記下來，需要的測試自己讀。
  final List<(String bond, String? by)> restoreCalls = [];

  @override
  Future<void> proposeRestore(String bondId, String byUid) async =>
      restoreCalls.add((bondId, byUid));

  @override
  Future<void> dropRestore(String bondId) async =>
      restoreCalls.add((bondId, null));


  /// 週互動評分。這支測試不碰它 —— 記下來就好。
  final List<(String bond, String week, int stars)> weekRatings = [];

  @override
  Future<void> rateWeek(String bondId, String week, int stars) async =>
      weekRatings.add((bondId, week, stars));

  final List<CloudBond> bonded = [];
  final List<String> recovered = [];
  final List<(String bond, String text)> asked = [];

  @override
  Future<void> bond(CloudBond b) async => bonded.add(b);

  @override
  Future<void> recover(String bondId, DateTime now) async =>
      recovered.add(bondId);

  @override
  Future<void> ask(String bondId, CloudQuestion q) async =>
      asked.add((bondId, q.text));

  @override
  Future<List<CloudBond>> bonds() async => const [];
  @override
  Future<void> release(
      String bondId, MentorReleaseReason reason, DateTime at) async {}
  @override
  Future<List<CloudMentorTask>> tasks(String bondId) async => const [];
  @override
  Future<void> putTask(String bondId, CloudMentorTask t) async {}
  @override
  Future<List<CloudQuestion>> questions(String bondId) async => const [];
  @override
  Future<void> answer(
      String bondId, String questionId, String text, DateTime at) async {}
  @override
  Future<List<MentorRequest>> requestsFor(String uid) async => const [];

  /// 我自己送出去的申請。預設沒有 —— 需要的測試自己覆寫。
  @override
  Future<List<MentorRequest>> sentRequests() async => sent;
  List<MentorRequest> sent = const [];
  @override
  Future<void> sendRequest(MentorRequest r) async {}
  @override
  Future<void> dropRequest(String requestId) async {}
  @override
  Stream<void> watchMentor() => const Stream.empty();
}

PublicProfile _instructorProfile(
  String uid,
  String name, {
  int apprentices = 0,
  int cap = 1,
  bool isInstructor = true,
}) =>
    PublicProfile(
      uid: uid,
      displayName: name,
      rank: 40,
      grade: 'B',
      ability: {for (final d in Dim.values) d: 30},
      isInstructor: isInstructor,
      reputation: 600,
      apprentices: apprentices,
      apprenticeCap: cap,
      specialties: const ['增肌'],
    );

InboundRequest _req(InboundKind kind, String from, String uid) =>
    InboundRequest(
      id: 'r1',
      kind: kind,
      from: from,
      fromUid: uid,
      fromRank: 30,
      subject: from,
      // **相對於現在，不寫死日期。** 原本是 2026-09-24 —— 請求七天逾期，
      // 10-01 之後信箱就不收它，這幾條測試在日曆翻過去那天一起紅。
      sentAt: appNow().subtract(const Duration(hours: 1)),
    );

void main() {
  group('教官清單：真實帳號也要看得到人', () {
    test('公開檔案裡的教官會出現在清單上', () {
      final s = AppState(demo: false);
      expect(s.instructors, isEmpty, reason: '前提：真實帳號原本一個都沒有');

      s.applyPublicProfiles([_instructorProfile('u-老王', '老王')]);

      expect(s.instructors.map((i) => i.name), ['老王']);
      expect(s.instructors.single.uid, 'u-老王');
      expect(s.instructors.single.reputation, 600);
    });

    test('帶徒人數與名額跟著檔案來 —— 「名額已滿」才擋得住', () {
      final s = AppState(demo: false);
      s.applyPublicProfiles([
        _instructorProfile('u-滿了', '滿了', apprentices: 3, cap: 3),
      ]);

      final full = s.instructors.single;
      expect(full.apprentices, 3);
      expect(full.apprenticeCap, 3);
      // 少了這兩個數字，拜師頁只能假設每位教官都還有空位 ——
      // 使用者申請下去才發現滿了，而且是在雲端那一側才擋。
      expect(s.mentorApplyBlockedReason(full), isNotNull);
    });

    test('非教官不會混進清單', () {
      final s = AppState(demo: false);
      s.applyPublicProfiles([
        _instructorProfile('u-路人', '路人', isInstructor: false),
      ]);
      expect(s.instructors, isEmpty);
    });

    test('教官身分被撤銷後要從清單移除，不是留著', () {
      final s = AppState(demo: false);
      s.applyPublicProfiles([_instructorProfile('u-老王', '老王')]);
      expect(s.instructors, hasLength(1));

      s.applyPublicProfiles([
        _instructorProfile('u-老王', '老王', isInstructor: false),
      ]);

      // 留著的話他會一直出現在拜師頁上，而申請送出去對方那側會被擋下 ——
      // 使用者只看到一次無聲的失敗。
      expect(s.instructors, isEmpty);
    });

    test('同一個人不會重複加入', () {
      final s = AppState(demo: false);
      s.applyPublicProfiles([_instructorProfile('u-老王', '老王')]);
      s.applyPublicProfiles([
        _instructorProfile('u-老王', '老王', apprentices: 2, cap: 3),
      ]);
      expect(s.instructors, hasLength(1));
      expect(s.instructors.single.apprentices, 2, reason: '而且要更新');
    });
  });

  group('我自己的教官資料要發布出去', () {
    test('帶徒人數與名額寫進公開檔案', () {
      final s = AppState(demo: false)
        ..isInstructor = true
        ..instructorReputation = 300;
      s.apprentices.add(const Apprentice(
          name: '小明', rank: 5, ability: {}, recentWorkouts: []));

      final me = s.myPublicProfile('u-me');
      expect(me.apprentices, 1);
      expect(me.apprenticeCap, s.apprenticeCap);
    });

    test('非教官不公開這兩個數字', () {
      final s = AppState(demo: false)..isInstructor = false;
      final me = s.myPublicProfile('u-me');
      expect(me.apprentices, 0);
      expect(me.apprenticeCap, 0);
      expect(me.toJson().containsKey('apprentices'), isFalse);
    });

    test('存得下、讀得回', () {
      final s = AppState(demo: false)
        ..isInstructor = true
        ..instructorReputation = 300;
      s.apprentices.add(const Apprentice(
          name: '小明', rank: 5, ability: {}, recentWorkouts: []));

      final back = PublicProfile.fromJson('u-me', s.myPublicProfile('u-me').toJson());
      expect(back!.apprentices, 1);
      expect(back.apprenticeCap, s.apprenticeCap);
    });
  });

  group('建立師徒關係要寫上雲端', () {
    test('接受收徒邀請：我是學徒，對方是教官', () {
      final src = _FakeMentor();
      final s = AppState(demo: false)
        ..myUid = 'u-me'
        ..mentorSource = src;
      final r = _req(InboundKind.mentorInvite, '老王', 'u-老王');
      s.receiveInbound(r);

      expect(s.acceptInbound(r), isTrue);

      final b = src.bonded.single;
      // **方向搞反的話**，下次登入 `applyCloudBonds` 只看
      // `apprenticeUid == me`，教官會把自己載入成學徒。
      expect(b.mentorUid, 'u-老王');
      expect(b.apprenticeUid, 'u-me');
      expect(b.id, 'u-老王_u-me');
      expect(b.state, MentorBondState.active);
    });

    test('接受拜師申請：我是教官，對方是學徒', () {
      final src = _FakeMentor();
      final s = AppState(demo: false)
        ..myUid = 'u-me'
        ..mentorSource = src
        ..isInstructor = true;
      final r = _req(InboundKind.apprenticeApply, '小明', 'u-小明');
      s.receiveInbound(r);

      expect(s.acceptInbound(r), isTrue);

      final b = src.bonded.single;
      expect(b.mentorUid, 'u-me');
      expect(b.apprenticeUid, 'u-小明');
      expect(b.id, 'u-me_u-小明');
    });

    test('團隊邀請不寫師徒關係', () {
      final src = _FakeMentor();
      final s = AppState(demo: false)
        ..myUid = 'u-me'
        ..mentorSource = src;
      final r = _req(InboundKind.teamInvite, '隊長', 'u-隊長');
      s.receiveInbound(r);
      s.acceptInbound(r);
      expect(src.bonded, isEmpty);
    });

    test('沒接後端不會炸', () {
      final s = AppState(demo: false)..myUid = 'u-me';
      final r = _req(InboundKind.mentorInvite, '老王', 'u-老王');
      s.receiveInbound(r);
      expect(s.acceptInbound(r), isTrue);
    });
  });

  group('學徒提問要送到教官那裡', () {
    test('寫上雲端，掛在正確的關係下', () {
      final src = _FakeMentor();
      final s = AppState(demo: false)
        ..myUid = 'u-me'
        ..mentorSource = src
        ..mentorDisclaimerVersion = 'v1'
        ..myInstructor = Instructor(
          name: '老王',
          uid: 'u-老王',
          rank: 40,
          reputation: 600,
          apprentices: 1,
          apprenticeCap: 3,
          ability: const {},
          specialties: const [],
          avgRating: 0,
          ratingCount: 0,
        );

      s.askQuestion('深蹲膝蓋會痛怎麼辦');

      expect(src.asked, [('u-老王_u-me', '深蹲膝蓋會痛怎麼辦')]);
    });

    test('關係 ID 以教官身上的 uid 為準，不靠暱稱反查', () {
      final src = _FakeMentor();
      final s = AppState(demo: false)
        ..myUid = 'u-me'
        ..mentorSource = src
        ..mentorDisclaimerVersion = 'v1'
        ..myInstructor = Instructor(
          name: '改過名字的老王',
          uid: 'u-老王',
          rank: 40,
          reputation: 600,
          apprentices: 1,
          apprenticeCap: 3,
          ability: const {},
          specialties: const [],
          avgRating: 0,
          ratingCount: 0,
        );

      s.askQuestion('問題');

      // 反查是拿暱稱去翻 `nameByUid`，而這個名字不在裡面 ——
      // 靠反查的話這則提問會靜靜地送不出去。
      expect(src.asked.single.$1, 'u-老王_u-me');
    });
  });

  group('恢復師徒關係要寫上雲端', () {
    test('同一筆轉回生效中', () {
      final src = _FakeMentor();
      final s = AppState(demo: false)
        ..myUid = 'u-me'
        ..mentorSource = src
        ..myInstructor = Instructor(
          name: '老王',
          uid: 'u-老王',
          rank: 40,
          reputation: 600,
          apprentices: 1,
          apprenticeCap: 3,
          ability: const {},
          specialties: const [],
          avgRating: 0,
          ratingCount: 0,
        );

      s.releaseMentor(MentorReleaseReason.byApprentice);
      expect(s.proposeRestore(), isTrue);
      // 提出的是我，所以同意不了 —— 換成對方提出的那一筆。
      expect(s.acceptRestore(), isFalse);
      s.mentorRestoreProposedBy = 'u-老王';
      expect(s.acceptRestore(), isTrue);

      // 少了這行，恢復只在本機生效 —— 我這邊回到生效中，
      // 對方重整之後那段關係還是已解除。
      expect(src.recovered, ['u-老王_u-me']);
    });
  });
}
