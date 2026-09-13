// 私訊上雲（[BE-11] 批次 5）。
//
// 這批有兩個「每位讀者各自不同」的欄位：`fromMe`（這則是不是我送的）
// 與 `deletedByMe`（我這一側刪掉了）。存錯地方的話兩個人會共用同一份狀態
// —— 對話框整段左右顛倒，或是我刪掉對話連對方那一側也消失。
// 與貼文的 `likedByMe` 是同一個陷阱，所以這裡逐條釘住。

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/chat_data.dart';
import 'package:fitness_app/data/chat_data_firestore.dart';
import 'package:fitness_app/domain/community.dart';

void main() {
  late FakeFirebaseFirestore db;

  setUp(() => db = FakeFirebaseFirestore());

  FirestoreChats as(String uid) => FirestoreChats(uid: uid, firestore: db);

  CloudMessage msg(
    String sender,
    String text, {
    String? id,
    DateTime? at,
    MessageCategory category = MessageCategory.normal,
  }) =>
      CloudMessage(
        id: id ?? 'm-$text',
        senderUid: sender,
        text: text,
        at: at ?? DateTime(2026, 9, 13, 10),
        category: category,
      );

  Future<void> aSendsB(String text, {String? id, DateTime? at}) => as('a').send(
        'b',
        msg('a', text, id: id, at: at),
        myName: '阿昶',
        peerName: '小美',
      );

  group('對話的建立', () {
    test('送出之後雙方都看得到這段對話', () async {
      await aSendsB('嗨');

      expect(await as('a').conversations(), hasLength(1));
      expect(await as('b').conversations(), hasLength(1));
    });

    test('同一對人永遠只有一段對話', () async {
      // 對話 ID 由兩個 uid 排序後合成，a_b 與 b_a 算出同一個。
      // 沒有這一層的話，兩人同時開啟對話會產生兩段、各自看到一半訊息。
      await aSendsB('我先講');
      await as('b')
          .send('a', msg('b', '我回你'), myName: '小美', peerName: '阿昶');

      final all = await db.collection('conversations').get();
      expect(all.docs, hasLength(1));
    });

    test('不相干的人看不到別人的對話', () async {
      await aSendsB('嗨');
      expect(await as('z').conversations(), isEmpty);
    });

    test('沒有任何對話時回傳空清單，不是錯誤', () async {
      expect(await as('a').conversations(), isEmpty);
    });
  });

  group('fromMe 是每位讀者各自的狀態', () {
    test('同一則訊息，發送者看到是自己送的，收件者看到不是', () async {
      await aSendsB('嗨');

      final fromA = (await as('a').conversations()).first.messages.first;
      final fromB = (await as('b').conversations()).first.messages.first;

      expect(fromA.fromMeFor('a'), isTrue);
      expect(fromB.fromMeFor('b'), isFalse,
          reason: 'b 收到的訊息不是 b 送的，存成欄位的話對話框會左右顛倒');
    });

    test('peer 也是每位讀者各自的', () async {
      await aSendsB('嗨');

      final forA = (await as('a').conversations()).first;
      final forB = (await as('b').conversations()).first;

      expect(forA.peerOf('a'), 'b');
      expect(forB.peerOf('b'), 'a');
    });
  });

  group('訊息內容與順序', () {
    test('依時間排序', () async {
      await aSendsB('先講的', id: 'm1', at: DateTime(2026, 9, 13, 10));
      await aSendsB('後講的', id: 'm2', at: DateTime(2026, 9, 13, 11));

      final msgs = (await as('b').conversations()).first.messages;
      expect([for (final m in msgs) m.text], ['先講的', '後講的']);
    });

    test('訊息分類於發送當下寫入，不回溯改寫', () async {
      // 規格：分類依發送當下的雙方關係判定，其後關係變化不影響既有訊息。
      await as('a').send(
        'b',
        msg('a', '陌生人的訊息', category: MessageCategory.stranger),
        myName: '阿昶',
        peerName: '小美',
      );

      final m = (await as('b').conversations()).first.messages.first;
      expect(m.category, MessageCategory.stranger);
    });
  });

  group('已讀', () {
    test('自己送的訊息自己算已讀', () async {
      await aSendsB('嗨');
      final m = (await as('a').conversations()).first.messages.first;
      expect(m.readBy.containsKey('a'), isTrue);
    });

    test('收件者讀過之後發送者看得到', () async {
      await aSendsB('嗨');
      final convId = as('b').conversationIdOf('a', 'b');
      await as('b').markRead(convId);

      final m = (await as('a').conversations()).first.messages.first;
      expect(m.readBy.containsKey('b'), isTrue);
    });

    test('沒讀過之前不帶對方的已讀時戳', () async {
      await aSendsB('嗨');
      final m = (await as('a').conversations()).first.messages.first;
      expect(m.readBy.containsKey('b'), isFalse);
    });
  });

  group('單方刪除', () {
    test('我刪掉之後我這一側看不到，對方仍看得到', () async {
      // 規格明訂刪除只發生在對話層級，且只改自己那一側。
      await aSendsB('嗨');
      final convId = as('a').conversationIdOf('a', 'b');
      await as('a').deleteForMe(convId);

      expect(await as('a').conversations(), isEmpty);
      expect(await as('b').conversations(), hasLength(1),
          reason: '對方沒刪，他那一側的對話不該跟著消失');
    });

    test('刪除不會讓文件消失', () async {
      await aSendsB('嗨');
      final convId = as('a').conversationIdOf('a', 'b');
      await as('a').deleteForMe(convId);

      final doc = await db.collection('conversations').doc(convId).get();
      expect(doc.exists, isTrue);
    });

    test('刪掉之後對方再傳新訊息，對話會重新出現', () async {
      // 刪除的是「這段對話的歷史」，不是「拒收未來的訊息」—— 那是封鎖。
      await aSendsB('嗨');
      final convId = as('a').conversationIdOf('a', 'b');
      await as('a').deleteForMe(convId);
      expect(await as('a').conversations(), isEmpty);

      await as('b')
          .send('a', msg('b', '你還在嗎'), myName: '小美', peerName: '阿昶');
      expect(await as('a').conversations(), hasLength(1));
    });
  });
}
