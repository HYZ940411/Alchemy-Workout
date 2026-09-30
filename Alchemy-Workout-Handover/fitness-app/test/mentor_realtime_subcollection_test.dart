// 師徒的問答與任務要觸發對方的即時訂閱（使用者 2026-09-29 實測 T3 = B）。
//
// ## 症狀
//
// A 提問，B 要**重新整理**才看得到。而 T1（接受拜師）是好的。
//
// ## 為什麼
//
// 任務與問答寫在 `mentor_bonds/{id}` 的**子集合**裡，而 `watchMentor()`
// 監看的是 bond **文件本身**：
//
// ```dart
// _col.where('mentorUid', isEqualTo: uid).snapshots()
// _col.where('apprenticeUid', isEqualTo: uid).snapshots()
// ```
//
// **子集合的寫入不會改動父文件**，所以那條訂閱一次都不會觸發。
// T1 會動是因為接受拜師真的改到了 bond 文件。
//
// ## 為什麼不改成監看子集合
//
// collection group 查詢要一個**不會自動建立**的索引，而那是
// 「畫面成功、雲端無聲拒絕」那一類的錯。動一下父文件是同一個效果、
// 零新索引，而且沿用已經驗過的那條訂閱。

import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/mentor_data.dart';
import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/data/mentor_data_firestore.dart';

void main() {
  late FakeFirebaseFirestore db;
  const bondId = 'u-mentor_u-app';

  setUp(() async {
    db = FakeFirebaseFirestore();
    await db.collection('mentor_bonds').doc(bondId).set({
      'mentorUid': 'u-mentor',
      'apprenticeUid': 'u-app',
      'state': 'active',
    });
  });

  /// 教官那一側的訂閱。收到幾次訊號就數幾次。
  ({StreamSubscription<void> sub, List<void> hits}) watchAsMentor() {
    final hits = <void>[];
    final sub = FirestoreMentor(uid: 'u-mentor', firestore: db)
        .watchMentor()
        .listen(hits.add);
    return (sub: sub, hits: hits);
  }

  CloudQuestion q(String id) => CloudQuestion(
        id: id,
        fromUid: 'u-app',
        text: '這樣做對嗎？',
        at: DateTime(2026, 9, 29),
      );

  test('學徒提問 → 教官那側收得到訊號', () async {
    final w = watchAsMentor();
    await Future<void>.delayed(Duration.zero);
    final before = w.hits.length;

    await FirestoreMentor(uid: 'u-app', firestore: db).ask(bondId, q('q1'));
    await Future<void>.delayed(Duration.zero);

    expect(w.hits.length, greaterThan(before),
        reason: '提問寫在子集合，不動父文件的話這條訂閱一次都不會觸發');
    await w.sub.cancel();
  });

  test('教官回答 → 學徒那側收得到訊號', () async {
    await FirestoreMentor(uid: 'u-app', firestore: db).ask(bondId, q('q1'));

    final hits = <void>[];
    final sub = FirestoreMentor(uid: 'u-app', firestore: db)
        .watchMentor()
        .listen(hits.add);
    await Future<void>.delayed(Duration.zero);
    final before = hits.length;

    await FirestoreMentor(uid: 'u-mentor', firestore: db)
        .answer(bondId, 'q1', '對，但要注意骨盆位置。', DateTime(2026, 9, 29));
    await Future<void>.delayed(Duration.zero);

    expect(hits.length, greaterThan(before));
    await sub.cancel();
  });

  test('指派任務也一樣 —— 它同樣寫在子集合裡', () async {
    final w = watchAsMentor();
    await Future<void>.delayed(Duration.zero);
    final before = w.hits.length;

    await FirestoreMentor(uid: 'u-mentor', firestore: db).putTask(
      bondId,
      CloudMentorTask(
        id: 't1',
        title: '本週三次深蹲',
        detail: '每次五組',
        state: MentorTaskState.assigned,
        rewardCoins: 10,
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(w.hits.length, greaterThan(before));
    await w.sub.cancel();
  });

  test('問答本身仍然寫得進去 —— 訊號是附加的，不是前提', () async {
    await FirestoreMentor(uid: 'u-app', firestore: db).ask(bondId, q('q1'));
    final got =
        await FirestoreMentor(uid: 'u-mentor', firestore: db).questions(bondId);
    expect(got.map((x) => x.id), ['q1']);
  });

  test('bond 文件不存在時不會炸 —— 訊號送不出去不該讓提問失敗', () async {
    // 這個情境在正式環境不該發生，但它的失敗方式必須是安靜的。
    await FirestoreMentor(uid: 'u-app', firestore: db)
        .ask('不存在的關係', q('q9'));
    final got = await FirestoreMentor(uid: 'u-app', firestore: db)
        .questions('不存在的關係');
    expect(got.map((x) => x.id), ['q9'], reason: '問題本身仍要寫進去');
  });
}
