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
    // `date` 可覆寫 —— 同一個時間戳不可能有兩場訓練，而「多場」的測試
    // 若讓三場共用一個時間戳，就等於拿一個現實中不存在的狀態在測。
    Map<String, dynamic> workout(String name, List<List<num>> sets,
            {String date = '2026-09-11T10:00:00.000'}) =>
        {
          'date': date,
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
          ], date: '2026-09-11T10:00:00.000'),
          workout('第二場', [
            [55, 10]
          ], date: '2026-09-10T10:00:00.000'),
          workout('第三場', [
            [60, 10]
          ], date: '2026-09-09T10:00:00.000'),
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
          ], date: '2026-09-11T10:00:00.000'),
          workout('舊的二', [
            [55, 10]
          ], date: '2026-09-10T10:00:00.000'),
        ],
      }));
      await store.save(snapshot({'history': const []}));

      expect((await reload())!['history'], isEmpty);
    });

    // =======================================================================
    // 2026-09-26：新的一場訓練從來沒有真的落地
    // =======================================================================
    //
    // 使用者回報「訓練歷史都沒有正常紀錄，統一變成 9/24」——
    // 他練了 7 次，雲端 7 份文件裝的全是**第一場**。
    //
    // 原因是同一個順序被兩邊各自假設，只有一邊對：
    // `AppState.history` 是 `insert(0, …)`，**新的在前**；而這裡的
    // 增量寫入是 `for (i = 上次筆數; i < 現在筆數; i++)`，假設**新的在後**。
    // 第二場訓練讓長度由 1 變 2，於是它只寫 `entries[1]` ——
    // 插隊之後那一格是**第一場**。新的那場永遠是 `entries[0]`，永遠不寫。
    //
    // 這一組測試的共同點是**跨兩次 save**。原本這一群只有「歷史變短」
    // 一條跨了兩次，而它剛好只驗刪除 —— 增量寫入的主路徑一條都沒測到。
    test('第二次存檔時，新插隊到最前面的那一場要真的落地', () async {
      await store.save(snapshot({
        'history': [
          workout('第一場', [
            [50, 10]
          ], date: '2026-09-24T10:00:00.000'),
        ],
      }));

      // AppState 的做法：新的一場 insert 到 index 0。
      await store.save(snapshot({
        'history': [
          workout('第二場', [
            [55, 10]
          ], date: '2026-09-25T10:00:00.000'),
          workout('第一場', [
            [50, 10]
          ], date: '2026-09-24T10:00:00.000'),
        ],
      }));

      final back = (await reload())!;
      expect(
        [for (final h in back['history']) h['planName']],
        ['第二場', '第一場'],
        reason: '新的一場必須寫進去，且順序仍是新的在前',
      );
    });

    test('連續七場逐次存檔，七場都在且各自不同', () async {
      final acc = <Map<String, dynamic>>[];
      for (var d = 20; d <= 26; d++) {
        acc.insert(
            0,
            workout('第 $d 天', [
              [50 + d, 10]
            ], date: '2026-09-${d}T10:00:00.000'));
        await store.save(snapshot({'history': [...acc]}));
      }

      final back = (await reload())!;
      expect(back['history'].length, 7);
      expect(
        [for (final h in back['history']) h['planName']],
        ['第 26 天', '第 25 天', '第 24 天', '第 23 天', '第 22 天', '第 21 天', '第 20 天'],
        reason: '每一場都要是自己那一場，不是第一場被複製七份',
      );
    });

    test('既有場次的文件 ID 不隨新場次加入而改變', () async {
      // 文件 ID 若跟著「新的在前」的索引跑，每加一場就得重寫整份歷史；
      // 而只寫「多出來的那幾筆」就會寫錯格。ID 綁時間順序才穩定。
      await store.save(snapshot({
        'history': [
          workout('最早', [
            [50, 10]
          ], date: '2026-09-20T10:00:00.000'),
        ],
      }));
      await store.save(snapshot({
        'history': [
          workout('後來', [
            [55, 10]
          ], date: '2026-09-21T10:00:00.000'),
          workout('最早', [
            [50, 10]
          ], date: '2026-09-20T10:00:00.000'),
        ],
      }));

      final first = await db
          .collection('users')
          .doc(_uid)
          .collection('history')
          .doc('000000')
          .get();
      expect(first.data()!['planName'], '最早',
          reason: '000000 永遠是時間上最早的那一場');
    });

    // 上面那個缺陷已經在使用者的帳號上留下 7 份一模一樣的文件。
    // 修好寫入不會讓它們消失 —— 讀回來要認得出那是壞資料。
    test('內容完全相同的重複場次讀回來只算一場', () async {
      final dup = {
        'date': '2026-09-24T10:00:00.000',
        'planName': '推日：胸肩三頭',
        'volume': 500.0,
        'minutes': 40,
        'calories': 210,
        'exercises': [
          {
            'id': 'e1',
            'name': '臥推',
            'isTimed': false,
            'sets': [
              {'w': 60, 'r': 8},
            ],
          },
        ],
      };
      for (var i = 0; i < 7; i++) {
        await db
            .collection('users')
            .doc(_uid)
            .collection('history')
            .doc(i.toString().padLeft(6, '0'))
            .set({...dup, 'seq': i});
      }
      await db.collection('users').doc(_uid).set(snapshot());

      final back = (await reload())!;
      expect(back['history'].length, 1,
          reason: '同一個時間戳不可能有兩場訓練，完全相同就是壞資料');
    });

    // =======================================================================
    // 2026-09-26（同日，第二個缺陷）：壞資料的文件沒被刪掉，於是順序反了
    // =======================================================================
    //
    // 使用者回報「訓練清單刷新後是舊到新排序，應該新的排前面」。
    //
    // `load()` 沒有記下「雲端現在有幾份歷史文件」，所以 `save()` 裡那個
    // 「把多出來的舊文件刪掉」的迴圈跑的是 `for (i = 現在筆數; i < -1)`
    // —— 一次都不跑。於是讀回來剔掉的重複文件仍然留在雲端，
    // 而它們的 `seq` 比新場次大，反轉之後就排到了新場次前面。
    test('讀回來剔掉的重複文件，下一次存檔要真的刪掉', () async {
      final dup = {
        'date': '2026-09-24T10:00:00.000',
        'planName': '第一場',
        'volume': 500.0,
        'minutes': 40,
        'calories': 210,
        'exercises': [
          {
            'id': 'e1',
            'name': '臥推',
            'isTimed': false,
            'sets': [
              {'w': 60, 'r': 8},
            ],
          },
        ],
      };
      for (var i = 0; i < 7; i++) {
        await db
            .collection('users')
            .doc(_uid)
            .collection('history')
            .doc(i.toString().padLeft(6, '0'))
            .set({...dup, 'seq': i});
      }
      await db.collection('users').doc(_uid).set(snapshot());

      // 讀回來（剔重後只剩 1 筆），原樣存回去。
      final store2 = FirestoreStore(uid: _uid, firestore: db);
      final back = (await store2.load())!;
      expect(back['history'].length, 1);
      await store2.save(snapshot({'history': back['history']}));

      final docs =
          await db.collection('users').doc(_uid).collection('history').get();
      expect(docs.docs.length, 1, reason: '多出來的 6 份要刪掉，否則下次又讀到');
    });

    test('壞資料清掉之後，新的一場排在最前面', () async {
      final dup = {
        'date': '2026-09-24T10:00:00.000',
        'planName': '第一場',
        'volume': 500.0,
        'minutes': 40,
        'calories': 210,
        'exercises': const <Map<String, dynamic>>[],
      };
      for (var i = 0; i < 7; i++) {
        await db
            .collection('users')
            .doc(_uid)
            .collection('history')
            .doc(i.toString().padLeft(6, '0'))
            .set({...dup, 'seq': i});
      }
      await db.collection('users').doc(_uid).set(snapshot());

      final store2 = FirestoreStore(uid: _uid, firestore: db);
      final first = (await store2.load())!['history'] as List;
      // 練一場新的：AppState 會 insert 到 index 0。
      final after = [
        workout('新的一場', [
          [70, 5]
        ], date: '2026-09-26T10:00:00.000'),
        ...first,
      ];
      await store2.save(snapshot({'history': after}));

      final back = (await reload())!;
      expect(
        [for (final h in back['history']) h['planName']],
        ['新的一場', '第一場'],
        reason: '新的要在前面 —— 殘留的舊文件 seq 比它大，會把它擠到後面',
      );
    });

    // =======================================================================
    // 2026-09-26（第三個缺陷）：剔重保留的是「壞順序裡的第一筆」
    // =======================================================================
    //
    // 使用者在上一版之後回報「訓練清單還是日期舊的排前面」。
    //
    // 他的雲端當時長這樣：000000＝舊那場、000001＝新那場、
    // 000002–000006＝舊那場的殘留副本（seq 2–6）。
    // 依 `seq` 反轉之後是 [dup6, dup5, …, 新, 舊]，
    // 而剔重保留的是**先遇到的那一筆** —— 也就是 seq 最大的那份副本。
    // 於是舊那場排到了新那場前面。
    //
    // **根因不是刪除沒跑，是我把「文件順序」當成了可信的。**
    // 那個順序正是壞掉的東西本身。順序的唯一權威是**日期**。
    test('文件順序壞掉時，讀回來仍照日期排（新的在前）', () async {
      Map<String, dynamic> doc(String name, String date, int seq) => {
            'date': date,
            'planName': name,
            'volume': 500.0,
            'minutes': 40,
            'calories': 210,
            'seq': seq,
            'exercises': const <Map<String, dynamic>>[],
          };

      final h = db.collection('users').doc(_uid).collection('history');
      await h.doc('000000').set(doc('舊那場', '2026-09-24T10:00:00.000', 0));
      await h.doc('000001').set(doc('新那場', '2026-09-26T10:00:00.000', 1));
      // 殘留的副本，seq 比新那場大。
      for (var i = 2; i <= 6; i++) {
        await h
            .doc(i.toString().padLeft(6, '0'))
            .set(doc('舊那場', '2026-09-24T10:00:00.000', i));
      }
      await db.collection('users').doc(_uid).set(snapshot());

      final store2 = FirestoreStore(uid: _uid, firestore: db);
      final back = (await store2.load())!;
      expect(
        [for (final e in back['history']) e['planName']],
        ['新那場', '舊那場'],
        reason: '順序的權威是日期，不是文件的 seq —— seq 正是壞掉的那個東西',
      );

      // 存回去之後要自己痊癒：只剩兩份，且時間順序正確。
      await store2.save(snapshot({'history': back['history']}));
      final docs = await h.orderBy('seq').get();
      expect(docs.docs.length, 2, reason: '殘留的 5 份要刪掉');
      expect(
        [for (final d in docs.docs) d.data()['planName']],
        ['舊那場', '新那場'],
        reason: '000000 永遠是時間上最早的那一場',
      );

      // 再讀一次還是對的 —— 不可以每存一次就翻一面。
      expect(
        [for (final e in (await reload())!['history']) e['planName']],
        ['新那場', '舊那場'],
      );
    });

    test('同一天但內容不同的兩場都留著', () async {
      // 去重只認「完全一樣」。同一天早晚各練一場是正常的。
      await store.save(snapshot({
        'history': [
          workout('晚上', [
            [60, 8]
          ], date: '2026-09-24T19:00:00.000'),
          workout('早上', [
            [50, 10]
          ], date: '2026-09-24T07:00:00.000'),
        ],
      }));

      expect((await reload())!['history'].length, 2);
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
