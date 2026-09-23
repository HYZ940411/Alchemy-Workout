// 私訊送不到，以及已讀一刷新就變回未讀。
//
// 兩個都是同一種病：本機那份資料只留了**暱稱**，要寫回雲端時再拿暱稱
// 去公開檔案裡反查 uid —— 反查不到就整段跳過，而且是無聲的。
// 與團隊核准申請那個 bug 一模一樣（見 team_approve_uid_test.dart）。
//
//   · `sendMessage()` 反查不到 → 訊息只留在我的記憶體裡，對方永遠收不到
//   · `markRead()` 反查不到 → 已讀只改記憶體，下次登入從雲端讀回來還是未讀
//
// uid 是雲端資料自己帶來的，釘在對話上就好，不該丟掉再猜回來。

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/chat_data.dart';
import 'package:fitness_app/data/chat_data_firestore.dart';
import 'package:fitness_app/data/public_profile.dart';
import 'package:fitness_app/state/app_state.dart';

void main() {
  late FakeFirebaseFirestore db;

  setUp(() => db = FakeFirebaseFirestore());

  /// 阿甲先傳一則給阿乙，於是雲端有一段對話。
  Future<void> seed() async {
    await FirestoreChats(uid: 'uid-a', firestore: db).send(
      'uid-b',
      CloudMessage(
        id: 'm1',
        senderUid: 'uid-a',
        text: '晚上要一起練嗎',
        at: DateTime(2026, 9, 22, 20),
      ),
      myName: '阿甲',
      peerName: '阿乙',
    );
  }

  /// 阿乙登入後的 AppState。**一筆公開檔案都沒載入** ——
  /// `uidOf('阿甲')` 必定回傳空值，這正是真實情境。
  Future<AppState> receiver() async {
    final src = FirestoreChats(uid: 'uid-b', firestore: db);
    final s = AppState(demo: false)
      ..displayName = '阿乙'
      ..myUid = 'uid-b'
      ..chatSource = src;
    s.applyCloudConversations(await src.conversations());
    return s;
  }

  test('雲端讀來的對話帶著對方的 uid', () async {
    await seed();
    final s = await receiver();

    expect(s.conversations, hasLength(1));
    expect(s.conversations.single.peer, '阿甲');
    // 丟掉 uid 的話這裡是 null，後面兩個測試就必定失敗。
    expect(s.conversations.single.peerUid, 'uid-a');
    expect(s.conversations.single.unread, 1);
  });

  test('標記已讀會寫回雲端 —— 重新登入不會又變未讀', () async {
    await seed();
    final s = await receiver();
    expect(s.uidOf('阿甲'), isNull); // 反查必定失敗

    s.markRead(s.conversations.single);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    // 重新從雲端讀一次，模擬重新整理。
    final again = await receiver();
    expect(again.conversations.single.unread, 0);
  });

  test('回訊息會寫回雲端 —— 對方讀得到', () async {
    await seed();
    final s = await receiver();

    s.sendMessage(s.conversations.single, '好啊，七點健身房見');
    await Future<void>.delayed(const Duration(milliseconds: 50));

    // 阿甲那一側重新讀一次。
    final asA = await FirestoreChats(uid: 'uid-a', firestore: db)
        .conversations();
    expect(asA, hasLength(1));
    expect(asA.single.messages.map((m) => m.text),
        containsAll(['晚上要一起練嗎', '好啊，七點健身房見']));
  });

  test('第一則訊息也送得出去 —— 對話本體與訊息同一批寫入', () async {
    final src = FirestoreChats(uid: 'uid-a', firestore: db);
    final s = AppState(demo: false)
      ..displayName = '阿甲'
      ..myUid = 'uid-a'
      ..chatSource = src;
    // 這一段本機還沒有，靠公開檔案認出對方是誰。
    s.applyPublicProfiles([
      const PublicProfile(uid: 'uid-b', displayName: '阿乙', rank: 20),
    ]);

    final c = s.conversationWith('阿乙');
    expect(c.peerUid, 'uid-b');

    s.sendMessage(c, '哈囉');
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final asB = await FirestoreChats(uid: 'uid-b', firestore: db)
        .conversations();
    expect(asB, hasLength(1));
    expect(asB.single.messages.single.text, '哈囉');
  });
}
