// FirestoreStore 的儲存契約。
//
// **為什麼不共用 test/store_contract.dart**：那份契約有三條是針對
// 「一段原始文字」的（空內容視同沒存過、JSON 壞掉要丟例外、壞檔改名保留），
// 而 Firestore 存的是結構化文件，沒有「壞掉的 JSON」這種故障模式，
// 也沒有「原檔」可以改名。硬套只會寫出一堆看起來有測、其實測不到東西的案例。
// 這裡改寫成語意對等、但用 Firestore 的方式表達的一組。
//
// 用 fake_cloud_firestore 而不是 Firebase emulator：與既有 1,212 個測試
// 同一套哲學 —— 測試不碰網路、不需要外部行程。代價是驗不到安全規則與
// 網路故障，那兩者靠人工測試與 Console 的 Rules Playground。

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/store_firestore.dart';

const _uid = 'u1';

/// 一份最小但合法的快照。各測試依需要覆寫欄位。
Map<String, dynamic> snapshot([Map<String, dynamic> extra = const {}]) => {
      'v': 2,
      'savedAt': '2026-09-11T18:46:17.668',
      'displayName': '你',
      'coins': 100,
      'makeupTickets': 1,
      'aiMonthly': 20,
      'aiPermanent': 0,
      'membership': 'none',
      'points': {'chest': 10, 'back': 10},
      'checkInTotal': 1,
      'checkInLongest': 1,
      'history': const [],
      ...extra,
    };

void main() {
  late FakeFirebaseFirestore db;
  late FirestoreStore store;

  setUp(() {
    db = FakeFirebaseFirestore();
    store = FirestoreStore(uid: _uid, firestore: db);
  });

  /// 每個測試都用新的 Store 讀，才驗得到「真的從 Firestore 讀回來」，
  /// 而不是讀到同一個實例的記憶體快取。
  Future<Map<String, dynamic>?> reload() =>
      FirestoreStore(uid: _uid, firestore: db).load();

  group('FirestoreStore：基本契約', () {
    test('沒存過回傳 null，不是錯誤', () async {
      expect(await store.load(), isNull);
    });

    test('存了讀得回來，中文與巢狀結構原樣進出', () async {
      await store.save(snapshot({
        'displayName': '阿昶',
        'commonGoal': '增肌',
        'points': {'chest': 486, 'legs': 318},
      }));

      final back = (await reload())!;
      expect(back['displayName'], '阿昶');
      expect(back['commonGoal'], '增肌');
      expect(back['points'], {'chest': 486, 'legs': 318});
    });

    test('後存的蓋掉先存的', () async {
      await store.save(snapshot({'coins': 1}));
      await store.save(snapshot({'coins': 2}));
      expect((await reload())!['coins'], 2);
    });

    test('clear() 之後等同沒存過', () async {
      await store.save(snapshot());
      await store.clear();
      expect(await reload(), isNull);
    });

    test('沒存過也 clear() 得動，不丟錯', () async {
      await expectLater(store.clear(), completes);
    });
  });

  group('FirestoreStore：存檔格式版本', () {
    // 這一條是整份測試裡最要緊的。
    //
    // applySnapshot() 的第一件事是比對 `v`，對不上就整份忽略並回傳 false，
    // 而 hydrate() **沒有檢查那個回傳值**。所以 `v` 若沒被原樣帶回來，
    // 使用者會看到示範假資料、而且沒有任何錯誤訊息 —— 跟「進度全部不見」
    // 長得一模一樣，卻查不到任何線索。
    test('v 原樣讀得回來', () async {
      await store.save(snapshot());
      expect((await reload())!['v'], 2);
    });

    test('存什麼版本就讀回什麼版本，不會被改寫成現行版本', () async {
      // 舊版存檔要能被認出是舊的，applySnapshot 才有機會整份忽略。
      // 若這裡把 v 換成現行版本，等於宣稱每份存檔都是最新格式，
      // 那道防線就整個失效了（v1→v2 信箱獎勵被靜默清空就是這樣來的）。
      await store.save(snapshot({'v': 1}));
      expect((await reload())!['v'], 1);
    });
  });

  group('FirestoreStore：欄位分組', () {
    test('金幣搬進 wallet 子文件，不留在根文件', () async {
      await store.save(snapshot({'coins': 250}));

      final root = await db.collection('users').doc(_uid).get();
      expect(root.data()!.containsKey('coins'), isFalse,
          reason: '同一個欄位同時存在根文件與子文件，就是兩份會對不起來的事實');

      final wallet = await db
          .collection('users')
          .doc(_uid)
          .collection('wallet')
          .doc('coins')
          .get();
      expect(wallet.data()!['coins'], 250);
    });

    test('搬走的欄位讀回來時要回到原本的位置', () async {
      // 這條防的是「寫得出去、讀不回來」——分組搬移只要漏接一個欄位，
      // 使用者的金幣/能力值就會在登出再登入之後悄悄變回預設值。
      await store.save(snapshot({
        'coins': 250,
        'makeupTickets': 3,
        'aiMonthly': 12,
        'points': {'chest': 486},
        'checkInTotal': 7,
      }));

      final back = (await reload())!;
      expect(back['coins'], 250);
      expect(back['makeupTickets'], 3);
      expect(back['aiMonthly'], 12);
      expect(back['points'], {'chest': 486});
      expect(back['checkInTotal'], 7);
    });
  });

  group('FirestoreStore：會員權益', () {
    // 規格明訂生效狀態只有三值，沒有「未生效」——
    // 「從未訂閱過」的樣子是這份文件根本不存在。
    test('從未訂閱過就不建立 membership 文件', () async {
      await store.save(snapshot({'membership': 'none'}));

      final doc = await db
          .collection('users')
          .doc(_uid)
          .collection('membership')
          .doc('current')
          .get();
      expect(doc.exists, isFalse);
    });

    test('membership 文件不存在時讀回 none', () async {
      await store.save(snapshot({'membership': 'none'}));
      expect((await reload())!['membership'], 'none');
    });

    test('訂閱之後正常存讀', () async {
      await store.save(snapshot({
        'membership': 'active',
        'membershipExpiry': '2026-10-11T00:00:00.000',
      }));

      final back = (await reload())!;
      expect(back['membership'], 'active');
      expect(back['membershipExpiry'], '2026-10-11T00:00:00.000');
    });
  });

  group('FirestoreStore：訓練歷史', () {
    Map<String, dynamic> workout(String name, List<List<num>> sets) => {
          'date': '2026-09-11T10:00:00.000',
          'planName': name,
          'volume': 500.0,
          'minutes': 40,
          'calories': 210,
          'exercises': [
            {
              'id': 'e1',
              'name': '臥推',
              'isTimed': false,
              'sets': sets,
            },
          ],
        };

    // Firestore **不接受陣列包陣列**，而一組成績正是 [重量, 次數]。
    // 不轉形狀的話整批寫入會被拒絕 —— 而 AppState 對存檔失敗是靜默的，
    // 使用者不會看到任何錯誤，只會發現訓練紀錄沒了。
    test('一組成績 [重量, 次數] 來回轉換後不變', () async {
      await store.save(snapshot({
        'history': [
          workout('胸推日', [
            [60, 8],
            [62.5, 6],
          ]),
        ],
      }));

      final back = (await reload())!;
      final sets = back['history'][0]['exercises'][0]['sets'];
      expect(sets, [
        [60, 8],
        [62.5, 6],
      ]);
    });

    test('落地時不可以有巢狀陣列', () async {
      await store.save(snapshot({
        'history': [
          workout('胸推日', [
            [60, 8]
          ]),
        ],
      }));

      final doc = await db
          .collection('users')
          .doc(_uid)
          .collection('history')
          .doc('000000')
          .get();
      final stored = (doc.data()!['exercises'] as List)[0]['sets'] as List;
      expect(stored.first, isA<Map>(),
          reason: 'Firestore 不收陣列包陣列，必須轉成物件');
    });

    test('多場訓練照原順序讀回來', () async {
      await store.save(snapshot({
        'history': [
          workout('第一場', [
            [50, 10]
          ]),
          workout('第二場', [
            [55, 10]
          ]),
          workout('第三場', [
            [60, 10]
          ]),
        ],
      }));

      final back = (await reload())!;
      expect(
        [for (final h in back['history']) h['planName']],
        ['第一場', '第二場', '第三場'],
      );
    });

    test('歷史變短時要刪掉多出來的舊場次', () async {
      // 重設帳號會讓歷史歸零。不刪的話，下一個人登入會讀到上一個帳號的訓練。
      await store.save(snapshot({
        'history': [
          workout('舊的一', [
            [50, 10]
          ]),
          workout('舊的二', [
            [55, 10]
          ]),
        ],
      }));
      await store.save(snapshot({'history': const []}));

      expect((await reload())!['history'], isEmpty);
    });
  });

  group('FirestoreStore：連續簽到', () {
    // 規格（2026-08-23）要求這個 Aggregate 四個欄位皆為儲存值，
    // 但 AppState 只給得出其中兩個 —— 另外兩個由每日簽到紀錄推算。
    // 推算的歸屬在 FirestoreStore 這層，AppState 不必為了後端多存欄位。
    Map<String, dynamic> checkIns(List<String> days) => {
          'checkInRecords': [
            for (final d in days) {'date': '${d}T00:00:00.000', 'method': 'real'},
          ],
        };

    Future<Map<String, dynamic>> checkinDoc() async => (await db
            .collection('users')
            .doc(_uid)
            .collection('streaks')
            .doc('checkin')
            .get())
        .data()!;

    test('連續的日子逐日累加', () async {
      await store.save(snapshot(checkIns([
        '2026-09-09',
        '2026-09-10',
        '2026-09-11',
      ])));
      expect((await checkinDoc())['streakDays'], 3);
    });

    test('遇到斷點就停，不跨越', () async {
      // 9/8 之後斷了一天，所以只算得到 9/10、9/11 這兩天。
      await store.save(snapshot(checkIns([
        '2026-09-07',
        '2026-09-08',
        '2026-09-10',
        '2026-09-11',
      ])));
      expect((await checkinDoc())['streakDays'], 2);
    });

    test('上次簽到日期取最晚的那一天', () async {
      await store.save(snapshot(checkIns([
        '2026-09-11',
        '2026-09-09',
        '2026-09-10',
      ])));
      expect(
        (await checkinDoc())['lastCheckInDate'],
        startsWith('2026-09-11'),
      );
    });

    test('推算出的兩個欄位不進快照', () async {
      // applySnapshot 不認得它們，塞進去只會讓「快照裡有哪些鍵」
      // 變得不可預測。它們只服務 Firestore 上的文件形狀。
      await store.save(snapshot(checkIns(['2026-09-11'])));

      final back = (await reload())!;
      expect(back.containsKey('streakDays'), isFalse);
      expect(back.containsKey('lastCheckInDate'), isFalse);
    });
  });

  // ===========================================================================
  // 已知的覆蓋率缺口：讀取失敗要丟 StoreLoadException
  // ===========================================================================
  //
  // 「讀不出來」絕對不可以回傳 null。null 的意思是「沒存過」，
  // AppState 收到它會呼叫 resetToNewAccount() 把帳號歸零，
  // 接著下一次自動存檔就把那份空白寫回雲端 ——
  // 一次連線失敗會變成真正的、不可回復的資料清空。
  //
  // 這條**沒有自動測試**，因為 fake_cloud_firestore 沒有提供
  // 「讓這次讀取失敗」的開關，而手寫一個會拋例外的 FirebaseFirestore
  // 替身要實作整個介面，成本遠高於這一條的價值。
  //
  // **這是刻意留下的缺口，不是忘了寫。** 要補的話兩條路：
  //   1. 引入 mocktail，mock 掉 FirebaseFirestore 的 get()
  //   2. 改用 Firebase emulator，用安全規則擋住來觸發真正的 FirebaseException
  //
  // 在補上之前，這條規則只由 store_firestore.dart 裡的 try/catch
  // 與程式碼審查把關。
}
