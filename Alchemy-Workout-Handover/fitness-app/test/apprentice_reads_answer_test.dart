// 教官的回答要到得了學徒手上（使用者 2026-09-29 實測）。
//
// ## 症狀
//
// A 提問 → B 收得到（訊號那一半已修，見 `mentor_realtime_subcollection_test`）
// → B 回答 → **A 收不到**，重整幾次都一樣。
//
// ## 為什麼
//
// `loadMentorSide()` 跑的是「**我帶的每位學徒**」：
//
// ```dart
// for (final a in apprentices) { ... loadMentorSideOf(a.uid) }
// ```
//
// 一位學徒的 `apprentices` 是空的，所以它什麼都不做 ——
// **學徒從來不會重讀自己那一段的問答**。他提的問題只有本機那一份，
// 而教官的回答寫在雲端，兩者之間沒有橋。
//
// 與「教官資格的裁決回不到申請人」「教官身分沒發布出去」同一家族：
// **一邊接上了，另一邊沒有。**

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/mentor_data.dart';
import 'package:fitness_app/data/mentor_data_firestore.dart';
import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/state/app_state.dart';

void main() {
  late FakeFirebaseFirestore db;
  const mentorUid = 'u-mentor';
  const myUid = 'u-me';
  const bondId = '${mentorUid}_$myUid';

  setUp(() async {
    db = FakeFirebaseFirestore();
    await db.collection('mentor_bonds').doc(bondId).set({
      'mentorUid': mentorUid,
      'apprenticeUid': myUid,
      'state': 'active',
    });
  });

  /// 我這一側：已經拜了師的學徒。
  AppState me() => AppState(demo: false)
    ..myUid = myUid
    ..markMentorUnlocked()
    ..myInstructor = Instructor(
      name: 'B 教官',
      uid: mentorUid,
      rank: 13,
      reputation: 100,
      apprentices: 1,
      apprenticeCap: 5,
      ability: const {},
      specialties: const [],
      avgRating: 0,
      ratingCount: 0,
    )
    ..mentorSource = FirestoreMentor(uid: myUid, firestore: db);

  Future<void> askThenAnswer({String? answer}) async {
    await FirestoreMentor(uid: myUid, firestore: db).ask(
      bondId,
      CloudQuestion(
          id: 'q1', fromUid: myUid, text: '深蹲膝蓋會痛', at: DateTime(2026, 9, 29)),
    );
    if (answer != null) {
      await FirestoreMentor(uid: mentorUid, firestore: db)
          .answer(bondId, 'q1', answer, DateTime(2026, 9, 29));
    }
  }

  test('教官回答之後，學徒讀得到', () async {
    await askThenAnswer(answer: '先降重量，看是哪個角度開始痛。');

    final s = me();
    expect(s.questions, isEmpty, reason: '前提：本機什麼都沒有');

    await s.loadMyApprenticeSide();

    expect(s.questions, hasLength(1));
    expect(s.questions.first.text, '深蹲膝蓋會痛');
    expect(s.questions.first.answer, '先降重量，看是哪個角度開始痛。',
        reason: '這正是重整幾次都看不到的那一句');
  });

  test('還沒回答時，那一則就是還沒回答 —— 不要編一個出來', () async {
    await askThenAnswer();
    final s = me();
    await s.loadMyApprenticeSide();
    expect(s.questions, hasLength(1));
    expect(s.questions.first.answer, isNull);
  });

  test('讀回來的提問標成「我問的」', () async {
    await askThenAnswer(answer: '好');
    final s = me();
    await s.loadMyApprenticeSide();
    // `apprenticeUid == null` 代表這是我自己問的（見 `isMyQuestion`）。
    expect(s.isMyQuestion(s.questions.first), isTrue,
        reason: '標錯的話畫面會把我的提問畫成別人的');
  });

  test('教官指派的任務也讀得到', () async {
    await FirestoreMentor(uid: mentorUid, firestore: db).putTask(
      bondId,
      const CloudMentorTask(
        id: 't1',
        title: '本週三次深蹲',
        detail: '每次五組',
        rewardCoins: 10,
      ),
    );
    final s = me();
    await s.loadMyApprenticeSide();
    expect(s.mentorTasks.map((t) => t.title), contains('本週三次深蹲'));
  });

  test('重複讀不會變成兩則', () async {
    await askThenAnswer(answer: '好');
    final s = me();
    await s.loadMyApprenticeSide();
    await s.loadMyApprenticeSide();
    expect(s.questions, hasLength(1));
  });

  test('自己問的那一則，重讀之後不會變成兩則', () async {
    // 本機那筆與送上雲那筆原本用**兩個不同的 id**
    // （`MentorQuestion` 的預設 `q${微秒}` vs `newId('q')`）。
    // 在學徒那側從來不重讀的時候看不出來；一旦重讀，
    // 雲端那筆就會因為 id 對不上而被當成新的一則加進來。
    final s = me()..confirmMentorDisclaimer();
    s.askQuestion('我剛問的');
    await Future<void>.delayed(Duration.zero);
    expect(s.questions, hasLength(1));

    await s.loadMyApprenticeSide();
    expect(s.questions, hasLength(1), reason: '每問一次就變成兩則');
    expect(s.questions.single.text, '我剛問的');
  });

  test('沒有教官的人不受影響', () async {
    final s = AppState(demo: false)
      ..myUid = myUid
      ..mentorSource = FirestoreMentor(uid: myUid, firestore: db);
    await s.loadMyApprenticeSide();
    expect(s.questions, isEmpty);
  });

  test('讀不到就維持現狀 —— 一次網路失敗不該把問答清空', () async {
    await askThenAnswer(answer: '好');
    final s = me();
    await s.loadMyApprenticeSide();
    expect(s.questions, hasLength(1));

    // 換成一個查不到東西的來源，再讀一次。
    s.mentorSource = FirestoreMentor(uid: myUid, firestore: FakeFirebaseFirestore());
    await s.loadMyApprenticeSide();
    expect(s.questions, hasLength(1), reason: '畫面上那一則不該消失');
  });
}
