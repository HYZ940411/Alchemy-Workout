// 個人排行榜的名次要是真的（使用者裁決 B，2026-09-28）。
//
// ## 根因
//
// `AppState.leaderboardWindow()` 第一行原本是 `if (!demo) return const [];`
// —— 名次那一整套是**示範資料做的**，真帳號從來沒有過。
// 畫面因此顯示「排行榜尚未開放」，而使用者回報「個人排行榜沒有排名顯示」。
//
// ## 裁決 B：用公開檔案做輕量排行榜
//
// 公開檔案是這個模型裡唯一「登入者皆可讀」的集合，所以分數放那裡，
// 用 `where(組別) + orderBy(分數)` 查同組的人。
//
// **這不能防作弊** —— 分數仍由裝置算出來再自己寫上去。真正的把關要等
// `[BE-07]` 把評分搬上 Cloud Functions。裁決當下已知並接受。

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/public_profile.dart';
import 'package:fitness_app/data/public_profile_firestore.dart';
import 'package:fitness_app/state/app_state.dart';

/// 一位在組別 [group] 裡、週分數為 [score] 的人。
Future<void> seed(FakeFirebaseFirestore db, String uid, int score,
        {int group = 0, String? name}) =>
    FirestorePublicProfile(uid: uid, firestore: db).publish(PublicProfile(
      uid: uid,
      displayName: name ?? uid,
      rank: 1,
      weeklyScore: score,
      weeklyGroup: group,
      monthlyScore: score,
      monthlyGroup: group,
    ));

void main() {
  late FakeFirebaseFirestore db;
  setUp(() => db = FakeFirebaseFirestore());

  FirestorePublicProfile as(String uid) =>
      FirestorePublicProfile(uid: uid, firestore: db);

  group('存讀邊界：名次怎麼算出來的', () {
    test('名次 ＝ 同組裡分數比我高的人數 ＋ 1', () async {
      await seed(db, 'a', 300);
      await seed(db, 'b', 200);
      await seed(db, 'me', 100);
      await seed(db, 'd', 50);

      final page =
          await as('me').leaderboard(weekly: true, group: 0, myScore: 100);

      expect(page!.place, 3);
    });

    test('同分並列同一名次', () async {
      await seed(db, 'a', 300);
      await seed(db, 'b', 100);
      await seed(db, 'me', 100);

      final page =
          await as('me').leaderboard(weekly: true, group: 0, myScore: 100);

      expect(page!.place, 2, reason: '並列第 2，不是第 3');
    });

    test('只跟同組別比', () async {
      await seed(db, 'a', 9999, group: 5);
      await seed(db, 'me', 100, group: 0);

      final page =
          await as('me').leaderboard(weekly: true, group: 0, myScore: 100);

      expect(page!.place, 1, reason: '別組的高分不該把我擠下去');
    });

    test('視窗含我上下各一段，由高到低', () async {
      for (var i = 0; i < 5; i++) {
        await seed(db, 'u$i', 100 - i * 10);
      }
      final page = await as('u2')
          .leaderboard(weekly: true, group: 0, myScore: 80, window: 2);

      final scores = [for (final p in page!.rows) p.weeklyScore];
      expect(scores, [100, 90, 80, 70, 60]);
    });

    test('月榜看的是另一組欄位', () async {
      await FirestorePublicProfile(uid: 'a', firestore: db).publish(
        PublicProfile(
            uid: 'a',
            displayName: 'A',
            rank: 1,
            weeklyScore: 999,
            weeklyGroup: 0,
            monthlyScore: 10,
            monthlyGroup: 0),
      );
      await seed(db, 'me', 50);

      final wk =
          await as('me').leaderboard(weekly: true, group: 0, myScore: 50);
      final mo =
          await as('me').leaderboard(weekly: false, group: 0, myScore: 50);

      expect(wk!.place, 2, reason: '週榜他 999 分，在我前面');
      expect(mo!.place, 1, reason: '月榜他只有 10 分');
    });
  });

  group('接到 AppState 上', () {
    Future<AppState> joined({int myScore = 100}) async {
      final s = AppState(demo: false)
        ..myUid = 'me'
        ..displayName = '我'
        ..profileSource = as('me')
        ..weeklyScore = myScore
        ..lockedRankGroup = 0
        ..lockedMonthlyGroup = 0;
      return s;
    }

    test('讀之前：名次視窗是空的，而且說得出「還沒讀到」', () async {
      final s = await joined();
      expect(s.leaderboardWindow(weekly: true), isEmpty);
      expect(s.leaderboardReady, isFalse,
          reason: '「還沒讀到」與「讀到了但只有我一個」要分得開');
    });

    test('讀完之後有名次，而且自己那一列標得出來', () async {
      await seed(db, 'a', 300);
      await seed(db, 'b', 200);
      await seed(db, 'me', 100, name: '我');

      final s = await joined();
      await s.ensureLeaderboard(weekly: true);

      final rows = s.leaderboardWindow(weekly: true);
      expect(rows.map((e) => e.position), [1, 2, 3]);
      expect(s.myPlace(weekly: true), 3);
      expect(rows.where((e) => e.isSelf).length, 1);
    });

    test('自己那一列用本機的分數，不用雲端那份舊的', () async {
      await seed(db, 'me', 10, name: '我'); // 雲端還是舊分數
      final s = await joined(myScore: 777);
      await s.ensureLeaderboard(weekly: true);

      final me = s.leaderboardWindow(weekly: true).firstWhere((e) => e.isSelf);
      expect(me.score, 777, reason: '剛練完還沒同步上去，畫面不該顯示舊的');
    });

    test('一個榜只讀一次', () async {
      await seed(db, 'me', 100, name: '我');
      final s = await joined();
      await s.ensureLeaderboard(weekly: true);
      final first = s.leaderboardWindow(weekly: true).length;

      await seed(db, 'newcomer', 500);
      await s.ensureLeaderboard(weekly: true);
      expect(s.leaderboardWindow(weekly: true).length, first,
          reason: '畫面每次重建都讀的話，捲一下就是好幾十次查詢');

      await s.ensureLeaderboard(weekly: true, force: true);
      expect(s.leaderboardWindow(weekly: true).length, first + 1);
    });

    test('沒接雲端就不讀 —— 既有測試走這條', () async {
      final s = AppState(demo: false)..myUid = 'me';
      await s.ensureLeaderboard(weekly: true);
      expect(s.leaderboardWindow(weekly: true), isEmpty);
    });
  });
}
