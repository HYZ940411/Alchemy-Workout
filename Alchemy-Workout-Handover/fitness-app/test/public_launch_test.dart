// 開放給不特定多數人之前的三個缺口。
//
// 這三件事在幾個測試帳號的規模下完全看不出來，一開放註冊就會出事：
//
//   1. `others()` 依**階級**排序取前 50 —— 而新註冊的人階級最低，
//      所以永遠在名單外。那份清單不只是「推薦誰給你看」：暱稱→uid
//      的對照表、找人、別人的階級與六維全靠它，撈不到的人在 App 裡
//      是隱形的。
//   2. 檢舉**完全沒有上雲**，只進本機記憶體，沒有任何人看得到。
//   3. 帳號刪除只設了一個本機欄位，冷靜期過了什麼都不會發生。

import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/public_profile.dart';
import 'package:fitness_app/data/public_profile_firestore.dart';
import 'package:fitness_app/data/report_data_firestore.dart';
import 'package:fitness_app/domain/admin.dart';
import 'package:fitness_app/state/app_state.dart';

void main() {
  late FakeFirebaseFirestore db;

  setUp(() => db = FakeFirebaseFirestore());

  group('公開檔案：新來的人不能是隱形的', () {
    FirestorePublicProfile as(String uid) =>
        FirestorePublicProfile(uid: uid, firestore: db);

    Future<void> join(String uid, String name, int rank) =>
        as(uid).publish(PublicProfile(
          uid: uid,
          displayName: name,
          rank: rank,
        ));

    test('publish 會寫下活躍時間', () async {
      await join('u1', '阿甲', 3);
      final doc = await db.collection('public_profiles').doc('u1').get();
      // 少了它，這個人不會出現在依活躍排序的查詢裡。
      expect(doc.data()!['lastActiveAt'], isNotNull);
    });

    test('階級最低的新人照樣讀得到', () async {
      await join('u1', '老手', 45);
      await join('u2', '新人', 1); // 最後登入 ＝ 最近活躍

      final seen = await as('u3').others(limit: 10);
      expect(seen.map((p) => p.displayName), containsAll(['老手', '新人']));
    });

    test('自己不算「別人」', () async {
      await join('u1', '我', 10);
      expect(await as('u1').others(limit: 10), isEmpty);
    });

    test('一次認得幾個人這件事有個明確的數字', () {
      // 這不是隨手填的常數 —— 它就是「這個 App 一次認得幾個人」的上限。
      expect(kProfileFetchLimit, 200);
    });

    test('remove 之後別人就看不到他了', () async {
      await join('u1', '離開的人', 10);
      await as('u1').remove();
      expect(await as('u2').others(limit: 10), isEmpty);
    });
  });

  group('檢舉要送得出去', () {
    AppState reporter() => AppState(demo: false)
      ..displayName = '檢舉的人'
      ..myUid = 'uid-r'
      ..reportSource = FirestoreReports(uid: 'uid-r', firestore: db);

    test('使用者檢舉會寫進雲端', () async {
      final s = reporter();
      s.fileReport(
        target: ReportTarget.post,
        targetKey: 'post:p1',
        content: '有問題的內容',
        accused: '被檢舉的人',
        reason: '不實資訊',
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final snap = await db.collection('reports').get();
      expect(snap.docs, hasLength(1));
      final d = snap.docs.single.data();
      expect(d['targetKey'], 'post:p1');
      expect(d['reporterUid'], 'uid-r');
      expect(d['accused'], '被檢舉的人');
      // 管理端要靠它掃出還沒處理的。
      expect(d['state'], 'pending');
    });

    test('同一人對同一標的重複檢舉只有一筆', () async {
      final s = reporter();
      for (var i = 0; i < 3; i++) {
        s.fileReport(
          target: ReportTarget.post,
          targetKey: 'post:p1',
          content: '有問題的內容',
          accused: '被檢舉的人',
          reason: '不實資訊',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect((await db.collection('reports').get()).docs, hasLength(1));
    });

    test('不同人檢舉同一標的各留一筆 —— 併案在管理端做', () async {
      final a = reporter();
      final b = AppState(demo: false)
        ..displayName = '另一個人'
        ..myUid = 'uid-b'
        ..reportSource = FirestoreReports(uid: 'uid-b', firestore: db);

      for (final s in [a, b]) {
        s.fileReport(
          target: ReportTarget.post,
          targetKey: 'post:p1',
          content: '有問題的內容',
          accused: '被檢舉的人',
          reason: '不實資訊',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect((await db.collection('reports').get()).docs, hasLength(2));
    });

    test('沒接雲端時照常運作 —— 既有測試全部走這條', () {
      final s = AppState(demo: false)..displayName = '我';
      expect(
        () => s.fileReport(
          target: ReportTarget.post,
          targetKey: 'post:p1',
          content: 'x',
          accused: '他',
          reason: '不實資訊',
        ),
        returnsNormally,
      );
    });
  });

  // ===========================================================================

  group('帳號刪除要真的刪', () {
    // 這一段讀原始碼，不執行 —— 要跑真的 AuthGate 得先有 AuthService，
    // 而那個包著 FirebaseAuth（同 auth_gate_wiring_test.dart 的理由）。
    final src = File('lib/screens/auth_gate.dart').readAsStringSync();

    test('冷靜期屆滿後有人真的動手', () {
      expect(src, contains('_executeDeletionIfDue'),
          reason: '在此之前 requestDeletion() 只設了一個欄位，'
              '冷靜期過了什麼都不會發生');
      expect(src, contains('deletionDaysLeft'));
    });

    test('順序：先刪 Firestore，最後才刪 Auth 帳號', () {
      final body = src.substring(src.indexOf('_executeDeletionIfDue(String'));
      final profile = body.indexOf('.remove()');
      final store = body.indexOf('.clear()');
      final account = body.indexOf('deleteAccount()');
      expect(profile, isNot(-1));
      expect(store, isNot(-1));
      expect(account, isNot(-1));
      // 帳號一沒，安全規則就認不得他是誰，剩下的資料誰也刪不掉。
      expect(account, greaterThan(profile),
          reason: '先刪帳號的話，公開檔案會永遠留在那裡');
      expect(account, greaterThan(store),
          reason: '先刪帳號的話，Firestore 上的資料會永遠留在那裡');
    });

    test('雲端資料沒刪成功就不刪帳號', () {
      final body = src.substring(src.indexOf('_executeDeletionIfDue(String'));
      final fail = body.indexOf('刪除雲端資料失敗');
      final account = body.indexOf('deleteAccount()');
      expect(fail, isNot(-1));
      expect(account, greaterThan(fail));
      expect(body.substring(fail, account), contains('return'),
          reason: '刪了帳號就再也回不去清那些資料');
    });

    test('畫面上不再說「由排程執行」 —— 沒有排程', () {
      // **只看給使用者看的字，不看註解。**
      // 這條測試原本讀整份原始碼，於是被檔案裡那句「不要寫『由排程執行』」
      // 的註解自己絆倒 —— 測試讀的東西要跟它斷言的東西是同一種。
      final ui = File('lib/screens/me/account_delete_screen.dart')
          .readAsStringSync()
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(ui, isNot(contains('由排程執行')),
          reason: '排程需要 Cloud Functions，目前是在下次登入時執行的');
      expect(ui, contains('下次登入'));
    });
  });
}
