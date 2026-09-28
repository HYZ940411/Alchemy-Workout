// 訓練體驗評分獨立成自己的集合（`[BE-18]`，2026-09-28）。
//
// ## 為什麼這份資料在今天之前等於沒有用途
//
// 規格（`02_Aggregate定義.md`〈訓練體驗評分 Aggregate〉）把它列為獨立
// Aggregate，理由是「〈管理員評分彙總〉需要逐筆下鑽查詢」，並明言
// **管理員是本評分的唯一讀者**，用途是回答「哪一份訓練計畫該改」。
//
// 而在此之前評分存在 `users/{uid}` 的存檔裡 —— 那棵樹依 `firestore.rules`
// **只有本人讀得到**。於是：問了使用者、存了下來、**唯一的讀者讀不到**。
// 管理端的彙總表永遠是空的。
//
// ## 唯一鍵由主鍵保證
//
// 文件 ID 是 `{raterUid}_{對象類型}_{對象 ID}`，所以「同一人對同一對象
// 終身僅一筆」寫不出第二筆 —— 不是靠程式碼記得檢查。同關注關係的做法。

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/rating_data.dart';
import 'package:fitness_app/data/rating_data_firestore.dart';
import 'package:fitness_app/domain/admin.dart';
import 'package:fitness_app/domain/novice_wrapup.dart';
import 'package:fitness_app/state/app_state.dart';

ExperienceRating _r(String uid, RatingTarget t, String id, int stars,
        {String? feedback, DateTime? at}) =>
    ExperienceRating(
      target: t,
      targetId: id,
      rater: '',
      raterUid: uid,
      stars: stars,
      feedback: feedback,
      at: at ?? DateTime(2026, 9, 28),
    );

/// 一律拒絕的來源（模擬安全規則擋下）。
class _Refuses implements RatingSource {
  @override
  Future<void> put(ExperienceRating r) async =>
      throw StateError('permission-denied');
  @override
  Future<List<ExperienceRating>> mine() async => const [];
  @override
  Future<List<ExperienceRating>> all({int limit = 500}) async => const [];
}

void main() {
  late FakeFirebaseFirestore db;
  setUp(() => db = FakeFirebaseFirestore());

  FirestoreRatings as(String uid) =>
      FirestoreRatings(uid: uid, firestore: db);

  group('存讀邊界', () {
    test('寫得進去，也讀得回來', () async {
      await as('u1')
          .put(_r('u1', RatingTarget.trainingPlan, 'p_push', 4, feedback: '不錯'));

      final mine = await as('u1').mine();
      expect(mine.length, 1);
      expect(mine.first.stars, 4);
      expect(mine.first.feedback, '不錯');
      expect(mine.first.targetId, 'p_push');
      expect(mine.first.target, RatingTarget.trainingPlan);
    });

    test('同一人對同一對象只會有一筆 —— 再評一次是覆寫', () async {
      await as('u1').put(_r('u1', RatingTarget.trainingPlan, 'p_push', 1));
      await as('u1').put(_r('u1', RatingTarget.trainingPlan, 'p_push', 5));

      final mine = await as('u1').mine();
      expect(mine.length, 1, reason: '唯一鍵由文件 ID 直接保證');
      expect(mine.first.stars, 5);
    });

    test('同一個 ID 在兩種對象類型下是兩筆 —— 鍵含對象類型', () async {
      // 新手任務的範本 ID 與某份課表的 ID 撞在一起並非不可能，
      // 而不變條件是「評分者 ＋ **對象類型** ＋ 對象 ID」三者。
      await as('u1').put(_r('u1', RatingTarget.trainingPlan, 'x', 1));
      await as('u1').put(_r('u1', RatingTarget.noviceTask, 'x', 5));

      final mine = await as('u1').mine();
      expect(mine.length, 2, reason: '少了對象類型就會蓋掉其中一筆');
      expect(mine.map((r) => r.stars).toSet(), {1, 5});
    });

    test('對象 ID 含底線也不會拆錯 —— 欄位讀文件內容，不從 ID 反解', () async {
      await as('u1').put(_r('u1', RatingTarget.trainingPlan, 'p_push_pull', 3));
      final mine = await as('u1').mine();
      expect(mine.first.targetId, 'p_push_pull');
    });

    test('`mine()` 只拿自己的', () async {
      await as('u1').put(_r('u1', RatingTarget.trainingPlan, 'p_push', 4));
      await as('u2').put(_r('u2', RatingTarget.trainingPlan, 'p_push', 2));

      expect((await as('u1').mine()).length, 1);
      expect((await as('u1').all()).length, 2, reason: '管理員拿得到全部');
    });

    test('不存評分者的暱稱 —— 下鑽欄位裡沒有「誰評的」', () async {
      await as('u1').put(ExperienceRating(
        target: RatingTarget.noviceTask,
        targetId: kNoviceTaskId,
        rater: '小明',
        raterUid: 'u1',
        stars: 2,
        at: DateTime(2026, 9, 28),
      ));
      final doc = await db
          .collection('experience_ratings')
          .doc(ratingDocId('u1', RatingTarget.noviceTask, kNoviceTaskId))
          .get();
      expect(doc.data()!.containsKey('rater'), isFalse,
          reason: '存了就等於把「這個人給了 2 星」交給管理員看');
    });

    test('沒有 uid 就不寫 —— 示範資料不該汙染雲端', () async {
      await as('u1').put(ExperienceRating(
        target: RatingTarget.noviceTask,
        targetId: kNoviceTaskId,
        rater: '示範',
        stars: 5,
        at: DateTime(2026, 9, 28),
      ));
      expect((await as('u1').all()).length, 0);
    });
  });

  group('彙總（〈Read Model：管理員評分彙總〉）', () {
    String nameOf(RatingTarget t, String id) =>
        t == RatingTarget.noviceTask ? '新手任務' : id;

    test('每個對象一列，含平均、則數、星等分布', () {
      final rows = summarizeRatings([
        _r('a', RatingTarget.trainingPlan, 'p1', 5),
        _r('b', RatingTarget.trainingPlan, 'p1', 3),
        _r('c', RatingTarget.noviceTask, kNoviceTaskId, 4),
      ], nameOf);

      expect(rows.length, 2);
      final p1 = rows.firstWhere((r) => r.name == 'p1');
      expect(p1.count, 2);
      expect(p1.average, 4);
      expect(p1.distribution, [0, 0, 1, 0, 1]);
    });

    test('由差到好排 —— 一打開就看到最該改的那一份', () {
      final rows = summarizeRatings([
        _r('a', RatingTarget.trainingPlan, '好課表', 5),
        _r('b', RatingTarget.trainingPlan, '爛課表', 1),
        _r('c', RatingTarget.trainingPlan, '普通', 3),
      ], nameOf);

      expect(rows.map((r) => r.name), ['爛課表', '普通', '好課表']);
    });

    test('平均相同時樣本多的在前', () {
      final rows = summarizeRatings([
        _r('a', RatingTarget.trainingPlan, '少', 3),
        _r('b', RatingTarget.trainingPlan, '多', 3),
        _r('c', RatingTarget.trainingPlan, '多', 3),
      ], nameOf);

      expect(rows.first.name, '多');
    });

    test('逐筆清單新的在前', () {
      final rows = summarizeRatings([
        _r('a', RatingTarget.trainingPlan, 'p1', 1, at: DateTime(2026, 1, 1)),
        _r('b', RatingTarget.trainingPlan, 'p1', 5, at: DateTime(2026, 9, 1)),
      ], nameOf);

      expect(rows.first.entries.first.$1, 5);
    });

    test('星等超出 1–5 的資料略過，不讓平均失真', () {
      final rows = summarizeRatings([
        _r('a', RatingTarget.trainingPlan, 'p1', 4),
        _r('b', RatingTarget.trainingPlan, 'p1', 99),
      ], nameOf);

      expect(rows.single.count, 1);
      expect(rows.single.average, 4);
    });
  });

  group('接到 AppState 上', () {
    test('評分會送上雲', () async {
      final s = AppState(demo: false)
        ..myUid = 'u1'
        ..ratingSource = as('u1');

      expect(s.rateExperience(RatingTarget.trainingPlan, 'p_push', 4,
              feedback: '很好'),
          isTrue);
      // 即發即忘 —— 等它一輪。
      await Future<void>.delayed(Duration.zero);

      final cloud = await as('u1').mine();
      expect(cloud.length, 1);
      expect(cloud.first.stars, 4);
    });

    test('登入時以雲端為準對齊', () {
      final s = AppState(demo: false)..myUid = 'u1';
      s.rateExperience(RatingTarget.trainingPlan, 'p_push', 5);
      s.applyCloudRatings([_r('u1', RatingTarget.trainingPlan, 'p_push', 2)]);

      expect(s.ratingFor(RatingTarget.trainingPlan, 'p_push')?.stars, 2,
          reason: '同一個對象以雲端那一份為準');
      expect(s.experienceRatings.length, 1, reason: '不該變成兩筆');
    });

    test('雲端沒有的本機評分要留著，而且補送上去', () async {
      final s = AppState(demo: false)
        ..myUid = 'u1'
        ..ratingSource = as('u1');
      // `[BE-18]` 之前的評分只存在本機存檔裡，雲端一筆都沒有。
      s.experienceRatings
          .add(_r('u1', RatingTarget.trainingPlan, '舊課表', 3));

      s.applyCloudRatings(const []);

      expect(s.ratingFor(RatingTarget.trainingPlan, '舊課表')?.stars, 3,
          reason: '整份換掉的話，上傳失敗或還沒遷移的評分會被登入洗掉 '
              '—— 使用者回報的「評分不見了」就是這樣來的');
      await Future<void>.delayed(Duration.zero);
      expect((await as('u1').all()).length, 1, reason: '順手補送上去');
    });

    test('寫不上去要留下痕跡，不能吞掉', () async {
      final s = AppState(demo: false)
        ..myUid = 'u1'
        ..ratingSource = _Refuses();

      s.rateExperience(RatingTarget.trainingPlan, 'p_push', 4);
      await Future<void>.delayed(Duration.zero);

      expect(s.ratingSyncError, isNotNull,
          reason: '畫面說「已送出評分」而雲端一筆都沒有，'
              '只能靠翻雲端才查得出來 —— 那是第三次犯同一個錯');
    });

    test('管理員讀得到全平台的，一般使用者讀不到', () async {
      await as('u2').put(_r('u2', RatingTarget.trainingPlan, 'p_push', 1));

      final normal = AppState(demo: false)
        ..myUid = 'u1'
        ..ratingSource = as('u1');
      await normal.loadAdminRatings();
      expect(normal.adminRatings, isEmpty, reason: '不是管理員就不去讀');

      final boss = AppState(demo: false)
        ..myUid = 'u1'
        ..ratingSource = as('u1')
        ..adminClaim = true;
      await boss.loadAdminRatings();
      expect(boss.adminRatings.length, 1);
      expect(boss.ratingSummaries.length, 1,
          reason: '在此之前真的管理員永遠看到一張空表');
    });

    test('沒接雲端時彙總表退回示範資料 —— 既有測試走這條', () {
      expect(AppState().ratingSummaries, isNotEmpty);
      expect(AppState(demo: false).ratingSummaries, isEmpty);
    });
  });
}
