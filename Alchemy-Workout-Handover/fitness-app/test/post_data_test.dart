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

      final seen = await as('b').recent();
      expect(seen, hasLength(1));
      expect(seen.first.text, '今天練完了。');
      expect(seen.first.author, '阿昶');
    });

    test('文件 ID 就是本地的貼文 ID', () async {
      // 不讓 Firestore 配自動 ID —— 本地、雲端、檢舉案件握的是同一個識別碼。
      await as('a').publish(draft(id: 'share-99'), authorUid: 'a');
      expect((await as('b').recent()).first.id, 'share-99');
    });

    test('依時間由新到舊', () async {
      await as('a').publish(
          draft(id: 'old', text: '舊的', at: DateTime(2026, 9, 1)),
          authorUid: 'a');
      await as('a').publish(
          draft(id: 'new', text: '新的', at: DateTime(2026, 9, 13)),
          authorUid: 'a');

      expect([for (final p in await as('b').recent()) p.text], ['新的', '舊的']);
    });

    test('可見範圍與送審旗標原樣帶回來', () async {
      await as('a').publish(
          draft(visibility: PostVisibility.followersOnly, pendingReview: true),
          authorUid: 'a');

      final p = (await as('b').recent()).first;
      expect(p.visibility, PostVisibility.followersOnly);
      expect(p.pendingReview, isTrue);
    });

    test('分享類貼文帶得回訓練成果', () async {
      await as('a')
          .publish(draft(workout: '胸推日　·　500 kg　·　12 組'), authorUid: 'a');
      expect((await as('b').recent()).first.attachedWorkout,
          '胸推日　·　500 kg　·　12 組');
    });

    test('沒有任何貼文時回傳空清單，不是錯誤', () async {
      expect(await as('a').recent(), isEmpty);
    });

    test('壞掉的一筆不會把整個動態牆弄掉', () async {
      await as('a').publish(draft(), authorUid: 'a');
      await db.collection('posts').doc('broken').set({'text': '沒有作者也沒有時間'});

      expect(await as('b').recent(), hasLength(1));
    });
  });

  group('按讚', () {
    test('按讚後計數增加，別人也看得到', () async {
      await as('a').publish(draft(), authorUid: 'a');
      await as('b').setLike('p1', liked: true);

      expect((await as('c').recent()).first.likes, 1);
    });

    test('取消按讚後計數減回去', () async {
      await as('a').publish(draft(), authorUid: 'a');
      await as('b').setLike('p1', liked: true);
      await as('b').setLike('p1', liked: false);

      expect((await as('c').recent()).first.likes, 0);
    });

    test('likedByMe 是每位讀者各自的狀態', () async {
      // 這條鎖住的是「按讚紀錄存在 likes/{uid} 子集合，不是貼文欄位」。
      // 存錯地方的話所有人會共用同一個「我按過了」。
      await as('a').publish(draft(), authorUid: 'a');
      await as('b').setLike('p1', liked: true);

      expect((await as('b').recent()).first.likedByMe, isTrue,
          reason: 'b 按過');
      expect((await as('c').recent()).first.likedByMe, isFalse,
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

      expect((await as('d').recent()).first.likes, 2);
    });
  });

  group('留言', () {
    test('留言後別人讀得到', () async {
      await as('a').publish(draft(), authorUid: 'a');
      await as('b').addComment(
          'p1', Comment('小美', '厲害！', DateTime(2026, 9, 13, 11)),
          authorUid: 'b');

      final p = (await as('c').recent()).first;
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

      final p = (await as('d').recent()).first;
      expect([for (final c in p.comments) c.text], ['先留的', '後留的']);
    });
  });

  group('編輯與刪除', () {
    test('編輯後內容更新，且編輯歷史留著', () async {
      await as('a').publish(draft(text: '原本的'), authorUid: 'a');

      final p = draft(text: '改過的');
      p.edits.add(('原本的', DateTime(2026, 9, 13, 12)));
      await as('a').updatePostText('p1', p);

      final back = (await as('b').recent()).first;
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
      expect((await as('b').recent()).first.deleted, isTrue);
    });
  });
}
