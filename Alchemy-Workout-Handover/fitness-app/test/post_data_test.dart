// 貼文、留言、按讚上雲（[BE-11] 批次 3）。
//
// 這批第一次讓「兩個人看到同一份內容」成立，所以測試的重點是
// **兩個不同使用者看到的東西對不對**，而不是單一使用者存讀得回來。
// 尤其是按讚：`likedByMe` 是每位讀者各自不同的狀態，
// 存錯地方的話所有人會共用同一個「我按過了」。

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/post_data_firestore.dart';
import 'package:fitness_app/domain/community.dart';

void main() {
  late FakeFirebaseFirestore db;

  setUp(() => db = FakeFirebaseFirestore());

  FirestorePosts as(String uid) => FirestorePosts(uid: uid, firestore: db);

  /// **使用者最後看到的那份** —— 貼文本體＋留言＋「我按過讚沒有」。
  ///
  /// `recent()` 現在只查本體（`[BE-17]` 讓動態牆先畫出來，細節隨後補），
  /// 所以下面每一條驗「看得到什麼」的測試都要走完整兩段。
  /// 只驗 `recent()` 的話，會把「留言根本沒被補上」當成綠的。
  Future<List<Post>> feed(String uid) async {
    final src = as(uid);
    final posts = await src.recent();
    await src.fillDetails(posts);
    return posts;
  }

  Post draft({
    String id = 'p1',
    String author = '阿昶',
    String text = '今天練完了。',
    DateTime? at,
    PostVisibility visibility = PostVisibility.public,
    bool pendingReview = false,
    String? workout,
  }) =>
      Post(
        id: id,
        author: author,
        authorRank: 45,
        text: text,
        at: at ?? DateTime(2026, 9, 13, 10),
        visibility: visibility,
        pendingReview: pendingReview,
        attachedWorkout: workout,
      );

  group('發布與讀取', () {
    test('發布之後別人讀得到', () async {
      await as('a').publish(draft(), authorUid: 'a');

      final seen = await feed('b');
      expect(seen, hasLength(1));
      expect(seen.first.text, '今天練完了。');
      expect(seen.first.author, '阿昶');
    });

    test('文件 ID 就是本地的貼文 ID', () async {
      // 不讓 Firestore 配自動 ID —— 本地、雲端、檢舉案件握的是同一個識別碼。
      await as('a').publish(draft(id: 'share-99'), authorUid: 'a');
      expect((await feed('b')).first.id, 'share-99');
    });

    test('依時間由新到舊', () async {
      await as('a').publish(
          draft(id: 'old', text: '舊的', at: DateTime(2026, 9, 1)),
          authorUid: 'a');
      await as('a').publish(
          draft(id: 'new', text: '新的', at: DateTime(2026, 9, 13)),
          authorUid: 'a');

      expect([for (final p in await feed('b')) p.text], ['新的', '舊的']);
    });

    test('可見範圍與送審旗標原樣帶回來', () async {
      await as('a').publish(
          draft(visibility: PostVisibility.followersOnly, pendingReview: true),
          authorUid: 'a');

      final p = (await feed('b')).first;
      expect(p.visibility, PostVisibility.followersOnly);
      expect(p.pendingReview, isTrue);
    });

    test('分享類貼文帶得回訓練成果', () async {
      await as('a')
          .publish(draft(workout: '胸推日　·　500 kg　·　12 組'), authorUid: 'a');
      expect((await feed('b')).first.attachedWorkout,
          '胸推日　·　500 kg　·　12 組');
    });

    test('沒有任何貼文時回傳空清單，不是錯誤', () async {
      expect(await feed('a'), isEmpty);
    });

    test('壞掉的一筆不會把整個動態牆弄掉', () async {
      await as('a').publish(draft(), authorUid: 'a');
      await db.collection('posts').doc('broken').set({'text': '沒有作者也沒有時間'});

      expect(await feed('b'), hasLength(1));
    });
  });

  group('按讚', () {
    test('按讚後計數增加，別人也看得到', () async {
      await as('a').publish(draft(), authorUid: 'a');
      await as('b').setLike('p1', liked: true);

      expect((await feed('c')).first.likes, 1);
    });

    test('取消按讚後計數減回去', () async {
      await as('a').publish(draft(), authorUid: 'a');
      await as('b').setLike('p1', liked: true);
      await as('b').setLike('p1', liked: false);

      expect((await feed('c')).first.likes, 0);
    });

    test('likedByMe 是每位讀者各自的狀態', () async {
      // 這條鎖住的是「按讚紀錄存在 likes/{uid} 子集合，不是貼文欄位」。
      // 存錯地方的話所有人會共用同一個「我按過了」。
      await as('a').publish(draft(), authorUid: 'a');
      await as('b').setLike('p1', liked: true);

      expect((await feed('b')).first.likedByMe, isTrue,
          reason: 'b 按過');
      expect((await feed('c')).first.likedByMe, isFalse,
          reason: 'c 沒按過，不該因為別人按了就顯示已按');
    });

    test('同一人重複按讚只算一次', () async {
      await as('a').publish(draft(), authorUid: 'a');
      await as('b').setLike('p1', liked: true);

      final likes = await db
          .collection('posts')
          .doc('p1')
          .collection('likes')
          .get();
      expect(likes.docs, hasLength(1));
      expect(likes.docs.first.id, 'b', reason: '文件 ID 就是按讚者的 uid');
    });

    test('多人按讚各自計入', () async {
      await as('a').publish(draft(), authorUid: 'a');
      await as('b').setLike('p1', liked: true);
      await as('c').setLike('p1', liked: true);

      expect((await feed('d')).first.likes, 2);
    });
  });

  group('留言', () {
    test('留言後別人讀得到', () async {
      await as('a').publish(draft(), authorUid: 'a');
      await as('b').addComment(
          'p1', Comment('小美', '厲害！', DateTime(2026, 9, 13, 11)),
          authorUid: 'b');

      final p = (await feed('c')).first;
      expect(p.comments, hasLength(1));
      expect(p.comments.first.author, '小美');
      expect(p.comments.first.text, '厲害！');
    });

    test('多則留言依時間排序', () async {
      await as('a').publish(draft(), authorUid: 'a');
      await as('b').addComment(
          'p1', Comment('B', '先留的', DateTime(2026, 9, 13, 11)),
          authorUid: 'b');
      await as('c').addComment(
          'p1', Comment('C', '後留的', DateTime(2026, 9, 13, 12)),
          authorUid: 'c');

      final p = (await feed('d')).first;
      expect([for (final c in p.comments) c.text], ['先留的', '後留的']);
    });
  });

  // 使用者回報「貼文載入的有點慢」。原本 `recent()` 一趟查詢撈 30 篇，
  // 然後**每一篇各再兩趟**（留言、我按過讚沒有）—— 61 趟全部回來才
  // 回傳，動態牆要等最慢的那一趟才畫得出第一個字。
  //
  // 拆成兩段之後，一趟回來就能先畫，其餘 60 趟在背景補。
  group('兩段式載入（`[BE-17]`）', () {
    test('recent() 只給貼文本體 —— 不含留言與讚', () async {
      await as('a').publish(draft(), authorUid: 'a');
      await as('b').addComment(
          'p1', Comment('小美', '厲害！', DateTime(2026, 9, 13, 11)),
          authorUid: 'b');
      await as('b').setLike('p1', liked: true);

      final p = (await as('b').recent()).first;

      // 這不是遺漏，是這一段刻意不做的事。補的人是 fillDetails()。
      expect(p.comments, isEmpty);
      expect(p.likedByMe, isFalse);
      expect(p.text, '今天練完了。', reason: '本體要有');
      expect(p.likes, 1, reason: '總讚數在貼文文件上，本來就一起回來');
    });

    test('fillDetails() 補得上，而且是就地改那幾個物件', () async {
      await as('a').publish(draft(), authorUid: 'a');
      await as('b').addComment(
          'p1', Comment('小美', '厲害！', DateTime(2026, 9, 13, 11)),
          authorUid: 'b');
      await as('b').setLike('p1', liked: true);

      final src = as('b');
      final posts = await src.recent();
      final p = posts.first; // 呼叫端已經把這個物件放進畫面了

      await src.fillDetails(posts);

      expect(p.comments, hasLength(1), reason: '要改到同一個物件上');
      expect(p.likedByMe, isTrue);
    });

    test('補兩次留言不會變兩份', () async {
      await as('a').publish(draft(), authorUid: 'a');
      await as('b').addComment(
          'p1', Comment('小美', '厲害！', DateTime(2026, 9, 13, 11)),
          authorUid: 'b');

      final src = as('b');
      final posts = await src.recent();
      await src.fillDetails(posts);
      await src.fillDetails(posts);

      expect(posts.first.comments, hasLength(1));
    });
  });

  group('編輯與刪除', () {
    test('編輯後內容更新，且編輯歷史留著', () async {
      await as('a').publish(draft(text: '原本的'), authorUid: 'a');

      final p = draft(text: '改過的');
      p.edits.add(('原本的', DateTime(2026, 9, 13, 12)));
      await as('a').updatePostText('p1', p);

      final back = (await feed('b')).first;
      expect(back.text, '改過的');
      expect(back.edits, hasLength(1));
      expect(back.edits.first.$1, '原本的');
      expect(back.edited, isTrue, reason: '讀者要看得到「已編輯」');
    });

    test('刪除是軟刪除 —— 文件還在，只是標記為已刪', () async {
      // 貼文可被檢舉，硬刪除會讓案件失去證據。
      await as('a').publish(draft(), authorUid: 'a');
      await as('a').markPostDeleted('p1');

      final doc = await db.collection('posts').doc('p1').get();
      expect(doc.exists, isTrue, reason: '文件不可以真的消失');
      expect(doc.data()!['deleted'], isTrue);
      expect((await feed('b')).first.deleted, isTrue);
    });
  });
}
