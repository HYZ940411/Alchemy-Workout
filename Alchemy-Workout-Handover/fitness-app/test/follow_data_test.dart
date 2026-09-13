// 關注關係上雲（[BE-11] 批次 2）。
//
// 這批的重點是**兩個方向**：我關注誰（following）與誰關注我（followers）。
// 規格把粉絲數列為使用者 Aggregate 的儲存欄位，其不變條件是
// 「粉絲數 ＝ 關注關係中被關注者為本人的筆數」——
// 兩個方向查錯一個，那個不變條件就不成立了。

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/follow_data_firestore.dart';

void main() {
  late FakeFirebaseFirestore db;

  setUp(() => db = FakeFirebaseFirestore());

  FirestoreFollows as(String uid) =>
      FirestoreFollows(uid: uid, firestore: db);

  group('關注與取消', () {
    test('關注之後出現在我的 following', () async {
      await as('a').follow('b');
      expect(await as('a').following(), {'b'});
    });

    test('取消之後就不在了', () async {
      await as('a').follow('b');
      await as('a').unfollow('b');
      expect(await as('a').following(), isEmpty);
    });

    test('重複關注同一人只會有一筆', () async {
      // 文件 ID 是 {follower}_{followee}，重複寫入是覆寫同一份。
      // 「同一組關係只有一筆」由主鍵保證，不靠程式碼記得檢查。
      await as('a').follow('b');
      await as('a').follow('b');

      final all = await db.collection('follows').get();
      expect(all.docs, hasLength(1));
    });

    test('沒關注過也能取消，不丟錯', () async {
      await expectLater(as('a').unfollow('b'), completes);
    });

    test('自己不能關注自己', () async {
      await as('a').follow('a');
      expect(await db.collection('follows').get().then((s) => s.docs), isEmpty);
    });
  });

  group('兩個方向', () {
    test('B 看得到 A 關注了自己', () async {
      await as('a').follow('b');
      expect(await as('b').followers(), {'a'});
    });

    test('關注是單向的 —— A 關注 B 不等於 B 關注 A', () async {
      await as('a').follow('b');
      expect(await as('b').following(), isEmpty);
      expect(await as('a').followers(), isEmpty);
    });

    test('互相關注時兩邊都看得到', () async {
      await as('a').follow('b');
      await as('b').follow('a');

      expect(await as('a').following(), {'b'});
      expect(await as('a').followers(), {'b'});
      expect(await as('b').following(), {'a'});
      expect(await as('b').followers(), {'a'});
    });

    test('粉絲數就是被關注筆數', () async {
      await as('a').follow('z');
      await as('b').follow('z');
      await as('c').follow('z');
      // d 關注別人，不該算進 z 的粉絲。
      await as('d').follow('a');

      expect((await as('z').followers()), hasLength(3));
    });

    test('取消關注會讓對方的粉絲少一個', () async {
      await as('a').follow('z');
      await as('b').follow('z');
      await as('a').unfollow('z');

      expect(await as('z').followers(), {'b'});
    });
  });

  group('互不干擾', () {
    test('別人的關注關係不會混進我的清單', () async {
      await as('a').follow('b');
      await as('c').follow('d');

      expect(await as('a').following(), {'b'});
      expect(await as('c').following(), {'d'});
    });
  });
}
