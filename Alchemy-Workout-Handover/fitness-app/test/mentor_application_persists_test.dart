// 拜師申請送出之後，重新整理還要在（使用者 2026-09-29 實測）。
//
// ## 症狀
//
// 按「申請師徒關係」→ 變成「已申請」→ **重新整理又回到「申請師徒關係」**。
// 而雲端那筆其實在 —— 按了四次就有四筆。
//
// ## 兩個缺口
//
// 1. **登入時只讀「別人送給我的」**（`requestsFor` 查 `toUid`），
//    自己送出去的那個方向從來沒有被查過。
//    `mentorApplications` 不進存檔，於是重整之後是空的。
// 2. **文件 ID 是帶時間戳的流水號**，所以同一個人對同一位教官
//    按幾次就寫幾筆。本機的「已送出」守衛擋不住它，因為那份清單是空的
//    —— 兩個缺口互相掩護。

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/mentor_data.dart';
import 'package:fitness_app/data/mentor_data_firestore.dart';
import 'package:fitness_app/data/public_profile.dart';
import 'package:fitness_app/domain/ability.dart';
import 'package:fitness_app/state/app_state.dart';

void main() {
  late FakeFirebaseFirestore db;

  setUp(() => db = FakeFirebaseFirestore());

  /// 一位學徒，教官清單裡已經有 B。
  AppState apprentice() {
    final s = AppState(demo: false)
      ..myUid = 'u-a'
      ..mentorSource = FirestoreMentor(uid: 'u-a', firestore: db);
    s.applyPublicProfiles([
      PublicProfile(
        uid: 'u-b',
        displayName: 'B 教官',
        rank: 13,
        grade: 'B',
        ability: {for (final d in Dim.values) d: 30},
        followers: 0,
        isInstructor: true,
        reputation: 100,
        apprentices: 0,
        apprenticeCap: 5,
      ),
    ]);
    return s;
  }

  test('送出之後，雲端有那一筆', () async {
    final s = apprentice();
    expect(s.applyMentor(s.instructors.first), isTrue);
    await Future<void>.delayed(Duration.zero);

    final snap = await db.collection('mentor_requests').get();
    expect(snap.docs, hasLength(1));
    expect(snap.docs.first.data()['toUid'], 'u-b');
    expect(snap.docs.first.data()['fromMentor'], isFalse);
  });

  test('連按四次只會有一筆 —— 文件 ID 就是「誰送給誰」', () async {
    final s = apprentice();
    final b = s.instructors.first;
    for (var i = 0; i < 4; i++) {
      // 第二次之後本機守衛會擋，所以直接清掉本機那份再按 ——
      // 模擬的正是「重整之後守衛失效」那個狀態。
      s.mentorApplications.clear();
      s.applyMentor(b);
      await Future<void>.delayed(Duration.zero);
    }
    final snap = await db.collection('mentor_requests').get();
    expect(snap.docs, hasLength(1),
        reason: '使用者按了四次，雲端就有四筆 —— 主鍵要擋住它');
  });

  test('重新整理之後，申請還在', () async {
    final send = apprentice();
    send.applyMentor(send.instructors.first);
    await Future<void>.delayed(Duration.zero);

    // **全新的 AppState** —— 模擬重新整理瀏覽器。
    final fresh = apprentice();
    expect(fresh.mentorApplications, isEmpty, reason: '前提：本機什麼都沒留');

    final src = FirestoreMentor(uid: 'u-a', firestore: db);
    fresh.applyMySentMentorRequests(await src.sentRequests());

    expect(fresh.mentorApplications, hasLength(1));
    expect(fresh.mentorApplications.first.name, 'B 教官',
        reason: '顯示的要是對方的名字，不是我自己的');
    expect(fresh.mentorApplications.first.uid, 'u-b');
    // 而且「已送出」的守衛回來了。
    expect(fresh.mentorApplyBlockedReason(fresh.instructors.first),
        contains('已送出'));
  });

  test('逾期的申請不算 —— 那一筆在對方那側也沒有效力了', () async {
    final fresh = apprentice();
    fresh.applyMySentMentorRequests([
      MentorRequest(
        id: 'x',
        fromUid: 'u-a',
        toUid: 'u-b',
        fromName: '我',
        fromRank: 1,
        fromMentor: false,
        at: DateTime(2026, 1, 1),
        expiresAt: DateTime(2026, 1, 8),
      ),
    ]);
    expect(fresh.mentorApplications, isEmpty);
  });

  test('教官送出的邀請不會被當成我的拜師申請', () async {
    final fresh = apprentice();
    fresh.applyMySentMentorRequests([
      MentorRequest(
        id: 'x',
        fromUid: 'u-a',
        toUid: 'u-b',
        fromName: '我',
        fromRank: 1,
        fromMentor: true, // ← 這是邀請，不是拜師
        at: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(days: 7)),
      ),
    ]);
    expect(fresh.mentorApplications, isEmpty);
  });
}
