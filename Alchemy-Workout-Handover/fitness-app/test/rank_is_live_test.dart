// 階級一律顯示**現值**，不是任何時點的快照（2026-09-23）。
//
// 使用者回報：「這個人在階級 11 發文時，若他已經升級到 40，該文章還是
// 顯示他發文時的階級。」
//
// 根因不是「沒串好」，是一個刻意寫死的設計用錯了地方 ——
// `posts/{id}.authorRank` 在發文當下抄一份存進 Firestore，讀回來直接顯示。
// 那段程式碼的註解在講**暱稱**：舊貼文顯示發文當時的名字是對的，因為
// 暱稱是歷史紀錄。階級不是 —— 它是「這個人現在多強」。`authorRank`
// 是搭著 `authorName` 順手加上去的，沒有經過自己那一輪判斷。
//
// 同一個毛病共九處：貼文（動態牆＋詳情）、私訊、團隊名冊、團隊詳情、
// 待審申請、收件匣、教官、學徒。這個檔案釘的是修好之後的三條規則：
//
//   1. 顯示的是現值，手上那份快照只在查不到人時墊底
//   2. 查詢以 **uid** 為鍵，不是暱稱 —— 暱稱可以改
//   3. 自己升階要當場寫回雲端，別人不必等我下次登入

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/mentor_data.dart';
import 'package:fitness_app/data/public_profile.dart';
import 'package:fitness_app/domain/ability.dart';
import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/domain/rank.dart';
import 'package:fitness_app/screens/social/feed_screen.dart';
import 'package:fitness_app/state/app_state.dart';

/// 假的雲端公開檔案。記下每一次寫入與每一次按 uid 的查詢。
class _FakeProfiles implements PublicProfileSource {
  final Map<String, PublicProfile> cloud;
  final List<PublicProfile> published = [];
  final List<List<String>> uidQueries = [];
  bool throwOnByUids = false;

  _FakeProfiles([Map<String, PublicProfile>? seed]) : cloud = seed ?? {};

  @override
  Future<void> publish(PublicProfile me) async => published.add(me);

  @override
  Future<List<PublicProfile>> others({int limit = kProfileFetchLimit}) async =>
      cloud.values.take(limit).toList();

  @override
  Future<List<PublicProfile>> byUids(List<String> uids) async {
    uidQueries.add(uids);
    if (throwOnByUids) throw StateError('離線');
    return [
      for (final u in uids)
        if (cloud[u] != null) cloud[u]!,
    ];
  }

  @override
  Future<void> remove() async {}
}

PublicProfile _profile(String uid, String name, int rank) => PublicProfile(
      uid: uid,
      displayName: name,
      rank: rank,
      grade: 'B',
      ability: {for (final d in Dim.values) d: 30},
      followers: 7,
    );

Post _postBy(String uid, String name, int rankWhenPosted) => Post(
      id: 'p1',
      author: name,
      authorUid: uid,
      authorRank: rankWhenPosted,
      text: '今天練腿',
      at: DateTime(2026, 3, 1),
    );

/// 開動態牆。這一層要證明的是**畫面真的去查了現值** ——
/// `rankOf` 對了但畫面還是讀 `post.authorRank` 的話，使用者看到的
/// 仍然是舊的那個數字。
Future<void> _openFeed(WidgetTester t, AppState s) async {
  t.view.physicalSize = const Size(393 * 3, 852 * 3);
  t.view.devicePixelRatio = 3.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(AppScope(
    state: s,
    child: const MaterialApp(home: Scaffold(body: FeedScreen())),
  ));
  await t.pumpAndSettle();
}

void main() {
  group('貼文上的階級是作者現在的，不是發文當下的', () {
    testWidgets('動態牆上印出來的是 40 階，不是貼文裡那個 11', (t) async {
      final s = AppState(demo: false)..myUid = 'u-me';
      s.following.add('阿甲');
      s.posts.add(_postBy('u-阿甲', '阿甲', 11));
      s.applyPublicProfiles([_profile('u-阿甲', '阿甲', 40)]);

      await _openFeed(t, s);

      expect(find.textContaining('40 階'), findsWidgets);
      expect(find.textContaining('11 階'), findsNothing,
          reason: '發文當下那個階級不該出現在畫面上');
    });

    test('使用者回報的那一幕：11 階發的文，升到 40 階後顯示 40', () {
      final s = AppState(demo: false);
      // 他發文當下是 11 階，貼文上凍結著 11。
      final post = _postBy('u-阿甲', '阿甲', 11);
      s.posts.add(post);
      expect(post.authorRank, 11, reason: '前提：快照確實停在發文當下');

      // 他現在已經 40 階了（公開檔案是「他現在多強」的事實來源）。
      s.applyPublicProfiles([_profile('u-阿甲', '阿甲', 40)]);

      expect(
        s.rankOf(post.author, uid: post.authorUid, fallback: post.authorRank),
        40,
        reason: '顯示現值，不是發文當下那個 11',
      );
    });

    test('查不到這個人時才退回用快照 —— 不是顯示 1 階', () {
      final s = AppState(demo: false);
      final post = _postBy('u-沒撈到', '久未上線的人', 33);

      // 這個 uid 不在公開檔案快取裡（登入只撈得到最近活躍的前 200 位）。
      expect(
        s.rankOf(post.author, uid: post.authorUid, fallback: post.authorRank),
        33,
        reason: '墊底值是他真的曾經有過的階級，比預設的 1 階誠實',
      );

      // 連墊底值都沒有才會是 1。
      expect(s.rankOf('完全不認識的人'), 1);
    });

    test('看自己的貼文顯示自己的現值，不管貼文上寫幾階', () {
      final s = AppState(demo: false)..myUid = 'u-me';
      final post = _postBy('u-me', s.displayName, 3);
      s.posts.add(post);

      expect(
        s.rankOf(post.author, uid: post.authorUid, fallback: post.authorRank),
        s.rank,
      );
      expect(post.authorRank, isNot(s.rank), reason: '前提：兩者本來就不同');
    });
  });

  group('查詢以 uid 為鍵，不是暱稱', () {
    test('對方改了暱稱，用 uid 仍查得到他的階級與六維', () {
      final s = AppState(demo: false);
      s.applyPublicProfiles([_profile('u-阿乙', '舊名字', 52)]);

      // 他改名了 —— 雲端同一個 uid，displayName 換了。
      s.applyPublicProfiles([_profile('u-阿乙', '新名字', 52)]);

      expect(s.rankOf('新名字', uid: 'u-阿乙'), 52);
      expect(s.abilityOf('新名字', uid: 'u-阿乙'), isNotNull);

      // 他以前用舊名字發的那篇貼文，帶著 uid 照樣查得到現值。
      expect(s.rankOf('舊名字', uid: 'u-阿乙'), 52);

      // **一個人只留一份。** 以暱稱為鍵的話這裡會是兩份 —— 舊名字那份
      // 永遠留著，而且還查得到，於是「他改名了」在快取裡看不出來。
      expect(s.publicProfiles.length, 1);
      expect(s.publicProfiles.keys.single, 'u-阿乙');
    });

    test('只有暱稱、而對方改過名時，退回墊底值而不是硬湊一個', () {
      final s = AppState(demo: false);
      s.applyPublicProfiles([_profile('u-阿乙', '新名字', 52)]);

      // 沒有 uid 可用，舊名字在反查表裡已經不存在。
      expect(s.rankOf('舊名字', fallback: 11), 11);
    });
  });

  group('已經在清單裡的人也要更新', () {
    test('第二次讀到同一個人時，階級與綜合等級要跟著換', () {
      final s = AppState(demo: false);
      s.applyPublicProfiles([_profile('u-阿丙', '阿丙', 11)]);
      expect(s.userOf('阿丙').rank, 11);

      s.applyPublicProfiles([_profile('u-阿丙', '阿丙', 40)]);

      // 原本這裡是 `if (socialUsers.any(...)) continue;` —— 只有第一次
      // 見到這個人才寫入，之後每次登入讀回來的新階級全被丟掉。於是
      // 「找人」與關注／粉絲清單顯示的是我**第一次見到他時**的階級。
      expect(s.userOf('阿丙').rank, 40);
      expect(s.socialUsers.where((u) => u.name == '阿丙').length, 1,
          reason: '是更新不是再加一筆');
      expect(s.rankOf('阿丙'), 40);
    });
  });

  group('按 uid 隨用隨取', () {
    test('補得回登入時沒撈到的人', () async {
      final src = _FakeProfiles({'u-遠方': _profile('u-遠方', '遠方的人', 61)});
      final s = AppState(demo: false)
        ..myUid = 'u-me'
        ..profileSource = src;

      // 登入時沒撈到他 —— 只拿得到貼文上那份快照。
      expect(s.rankOf('遠方的人', uid: 'u-遠方', fallback: 8), 8);

      await s.ensureProfiles(['u-遠方']);

      expect(s.rankOf('遠方的人', uid: 'u-遠方', fallback: 8), 61);
    });

    test('已經有的、自己的都不再查一次', () async {
      final src = _FakeProfiles({'u-甲': _profile('u-甲', '甲', 20)});
      final s = AppState(demo: false)
        ..myUid = 'u-me'
        ..profileSource = src;

      await s.ensureProfiles(['u-甲']);
      expect(src.uidQueries, [
        ['u-甲']
      ]);

      // 第二次：已經在快取裡，不該再打一次網路。自己也不必查。
      await s.ensureProfiles(['u-甲', 'u-me']);
      expect(src.uidQueries.length, 1);
    });

    test('查不到就維持現狀，不把畫面上的階級洗成預設值', () async {
      final src = _FakeProfiles({'u-甲': _profile('u-甲', '甲', 20)})
        ..throwOnByUids = true;
      final s = AppState(demo: false)
        ..myUid = 'u-me'
        ..profileSource = src;

      await s.ensureProfiles(['u-甲']); // 不該拋出來
      expect(s.rankOf('甲', uid: 'u-甲', fallback: 15), 15);

      // 失敗之後不該把這個 uid 永遠鎖在「查詢中」——下次要再試一次。
      src.throwOnByUids = false;
      await s.ensureProfiles(['u-甲']);
      expect(s.rankOf('甲', uid: 'u-甲', fallback: 15), 20);
    });

    test('沒接後端就什麼都不做', () async {
      final s = AppState(demo: false);
      await s.ensureProfiles(['u-甲']); // 不該拋出來
      expect(s.publicProfiles, isEmpty);
    });

    test('雲端讀回貼文時順手補齊作者', () async {
      final src = _FakeProfiles({'u-阿甲': _profile('u-阿甲', '阿甲', 40)});
      final s = AppState(demo: false)
        ..myUid = 'u-me'
        ..profileSource = src;

      s.applyCloudPosts([_postBy('u-阿甲', '阿甲', 11)]);
      // applyCloudPosts 不 await（動態牆不該為了階級等網路），
      // 所以這裡要讓那趟非同步跑完。
      await Future<void>.delayed(Duration.zero);

      expect(src.uidQueries, [
        ['u-阿甲']
      ]);
      expect(s.rankOf('阿甲', uid: 'u-阿甲', fallback: 11), 40);
    });
  });

  group('粉絲數', () {
    test('關注某人之後，他的粉絲數當場 +1（不被雲端快照蓋掉）', () {
      final s = AppState(demo: false);
      s.applyPublicProfiles([_profile('u-阿丁', '阿丁', 30)]);
      final before = s.followersOf('阿丁', uid: 'u-阿丁');
      expect(before, 7, reason: '前提：雲端那份寫著 7');

      s.toggleFollow('阿丁');

      // 公開檔案上那個 7 是我按下去之前的值。取它就等於把我剛做的事丟掉。
      expect(s.followersOf('阿丁', uid: 'u-阿丁'), before + 1);
    });

    test('重新載入公開檔案時以雲端為準', () {
      final s = AppState(demo: false);
      s.applyPublicProfiles([_profile('u-阿丁', '阿丁', 30)]);
      s.applyPublicProfiles([
        PublicProfile(
            uid: 'u-阿丁', displayName: '阿丁', rank: 30, followers: 99),
      ]);
      expect(s.followersOf('阿丁', uid: 'u-阿丁'), 99);
    });
  });

  group('教官身分與聲望也是現值（B 類的漏網）', () {
    test('被撤銷教官身分的人，舊貼文上不該還掛著徽章', () {
      final s = AppState(demo: false);
      // 他發文當下是教官，聲望 320，貼文上凍結著。
      const wasInstructor = 320;
      s.applyPublicProfiles([
        PublicProfile(
            uid: 'u-阿甲', displayName: '阿甲', rank: 40, isInstructor: false),
      ]);

      // **檔案在手上就以它為準，不可以退回快照。**
      expect(
        s.reputationOf('阿甲', uid: 'u-阿甲', fallback: wasInstructor),
        isNull,
      );
      expect(s.isInstructorOf('阿甲', uid: 'u-阿甲', fallback: true), isFalse);
    });

    test('發文後才當上教官的人，徽章要出現', () {
      final s = AppState(demo: false);
      s.applyPublicProfiles([
        PublicProfile(
          uid: 'u-阿乙',
          displayName: '阿乙',
          rank: 40,
          isInstructor: true,
          reputation: 610,
        ),
      ]);

      // 貼文上沒有聲望（發文當下還不是教官），現值有。
      expect(s.reputationOf('阿乙', uid: 'u-阿乙'), 610);
      expect(s.isInstructorOf('阿乙', uid: 'u-阿乙'), isTrue);
    });

    test('完全查不到這個人時才退回快照', () {
      final s = AppState(demo: false);
      expect(s.reputationOf('沒撈到的人', uid: 'u-沒撈到', fallback: 320), 320);
      expect(s.isInstructorOf('沒撈到的人', uid: 'u-沒撈到', fallback: true), isTrue);
    });
  });

  group('自己升階要當場寫回雲端', () {
    test('跨過階級門檻就重寫一次公開檔案', () {
      final src = _FakeProfiles();
      final s = AppState(demo: false)
        ..myUid = 'u-me'
        ..profileSource = src;

      final before = s.rank;
      // 推到剛好跨過下一階的門檻。
      s.totalExp = expThresholdForRank(before + 1);

      expect(s.rank, before + 1, reason: '前提：真的升階了');
      expect(src.published.length, 1);
      expect(src.published.single.rank, before + 1);
    });

    test('沒升階就不寫 —— 每加一次經驗值都打一次網路太貴', () {
      final src = _FakeProfiles();
      final s = AppState(demo: false)
        ..myUid = 'u-me'
        ..profileSource = src;

      final stillSameRank = expThresholdForRank(s.rank + 1) - 1;
      s.totalExp = stillSameRank;

      expect(s.rank, rankForExp(stillSameRank));
      expect(src.published, isEmpty);
    });

    test('沒接後端不會炸', () {
      final s = AppState(demo: false);
      s.totalExp = expThresholdForRank(s.rank + 5); // 不該拋出來
    });
  });

  group('從雲端載入的教官不再寫死 1 階', () {
    test('師徒關係載入時查得到教官的現值', () {
      final s = AppState(demo: false)..myUid = 'u-me';
      s.applyPublicProfiles([_profile('u-教官', '老王', 66)]);

      s.applyCloudBonds([
        CloudBond(
          id: 'b1',
          mentorUid: 'u-教官',
          apprenticeUid: 'u-me',
          mentorName: '老王',
          apprenticeName: s.displayName,
          state: MentorBondState.active,
          bondedAt: DateTime(2026, 5, 1),
        ),
      ]);

      // 非示範帳號的 `instructors` 是空的，所以在此之前這裡一律是 1 ——
      // 那不是過期，是根本沒查。
      expect(s.myInstructor?.rank, 66);
      expect(s.myInstructor?.uid, 'u-教官');
    });
  });
}
