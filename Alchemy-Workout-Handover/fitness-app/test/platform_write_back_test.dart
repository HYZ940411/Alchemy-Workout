// 管理員改了平台設定，要真的寫回雲端（[BE-12] 的另一半，2026-09-28）。
//
// ## 使用者實測 P123 = B
//
// 「管理員後台 → 平台設定 → 改一個參數 → 存 → 登出再登入」的結果是
// **變回原本的值**。
//
// 根因：`[BE-12]` 只做了**讀**的那一半。`applySettings` 改的是記憶體裡的
// `platformConfig`，而 `AuthGate` 每次登入都會 `applyPlatformData(await
// src.load())` 從雲端整份重新載入 —— 沒寫上去的設定於是靜靜打回原形。
//
// 而且 `AuthGate` 讀完就把來源丟了，`AppState` 根本沒有寫回去的管道。
//
// ## 為什麼不即發即忘
//
// 關注、貼文那些可以晚一點一致，因為使用者當下看得到自己按了什麼。
// **後台不一樣** —— 管理員改完就走了，下次登入才發現沒生效，
// 而那時候他不會知道是哪一次沒存進去。所以寫入要等，失敗要講。

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/platform_data.dart';
import 'package:fitness_app/data/platform_data_firestore.dart';
import 'package:fitness_app/domain/models.dart';
import 'package:fitness_app/domain/platform_config.dart';
import 'package:fitness_app/domain/task_pool.dart';
import 'package:fitness_app/state/app_state.dart';

/// 一律失敗的來源，用來驗「寫不上去要講出來」。
class _Broken implements PlatformDataSource {
  @override
  Future<PlatformData> load() => const BundledPlatformData().load();
  @override
  Future<void> put(String c, String id, Map<String, dynamic> d) async =>
      throw StateError('雲端壞了');
  @override
  Future<void> remove(String c, String id) async =>
      throw StateError('雲端壞了');
}

void main() {
  setUp(platformConfig.reset);
  tearDown(platformConfig.reset);

  late FakeFirebaseFirestore db;
  late AppState s;

  setUp(() {
    db = FakeFirebaseFirestore();
    s = AppState()..platformSource = FirestorePlatformData(firestore: db);
  });

  group('改完要寫得上去', () {
    test('平台設定：改的值真的進了雲端', () async {
      expect(s.applySettings('reward', {'trainCoin': 45}), isNull);
      expect(await s.pushConfigGroup('reward'), isNull);

      final doc =
          await db.collection('platform_config').doc('reward').get();
      expect(doc.data()!['params']['trainCoin'], 45);
    });

    test('改完之後重新載入，值還在 —— 這就是 P123', () async {
      s.applySettings('reward', {'trainCoin': 45});
      await s.pushConfigGroup('reward');

      // 模擬「登出再登入」：整份從雲端重新載入。
      platformConfig.reset();
      final fresh = AppState()
        ..applyPlatformData(
            await FirestorePlatformData(firestore: db).load());

      expect(platformConfig.i('reward', 'trainCoin'), 45,
          reason: '在此之前這裡會變回預設值');
      expect(fresh.coins, isNotNull); // 只是讓 fresh 有被用到
    });

    test('成就定義', () async {
      final a = s.achievements.first;
      expect(
          s.setAchievementDefinition(a, threshold: 7, coins: 50, exp: 60),
          isNull);
      final now = s.achievements
          .firstWhere((x) => x.category == a.category && x.name == a.name);
      expect(await s.pushAchievement(now), isNull);

      final doc = await db
          .collection('achievement_defs')
          .doc(achievementDocId(now))
          .get();
      expect(doc.data()!['threshold'], 7);
      expect(doc.data()!['rewardCoins'], 50);
    });

    test('改門檻不會多長出一枚成就 —— 文件 ID 不編碼會被改的欄位', () async {
      final a = s.achievements.first;
      final before = s.achievements.length;
      final oldId = achievementDocId(a);

      s.setAchievementDefinition(a, threshold: 777, coins: 1, exp: 1);
      final now = s.achievements
          .firstWhere((x) => x.category == a.category && x.name == a.name);
      await s.pushAchievement(now);

      final all = await db.collection('achievement_defs').get();
      expect(all.docs.length, 1,
          reason: '鍵是「類別＋名稱」時只會有一筆；'
              '用門檻當鍵的話改一次就多一筆，舊門檻那枚還留著');
      expect(achievementDocId(now), oldId,
          reason: '改門檻不該讓它換一個身分');
      expect(s.achievements.length, before);
    });

    test('平台動作', () async {
      final e = s.platformExercises.first;
      expect(
          s.setPlatformExercise(e, relativeIntensity: 1.25, restSeconds: 111),
          isNull);
      final now = s.platformExercises.firstWhere((x) => x.id == e.id);
      expect(await s.pushExercise(now), isNull);

      final doc = await db.collection('exercises').doc(e.id).get();
      expect(doc.data()!['defaultRestSeconds'], 111);
    });

    test('每日任務池：新增與移除都要同步', () async {
      final item = TaskPoolItem(
        id: 'tp-new',
        name: '測試任務',
        sourceEvent: '使用者已完成訓練',
        target: 1,
        audience: TaskAudience.personal,
      );
      expect(s.addTaskPoolItem(item), isNull);
      expect(await s.pushTaskPoolItem(item), isNull);
      expect((await db.collection('daily_task_pool').doc('tp-new').get()).exists,
          isTrue);

      expect(s.removeTaskPoolItem(item), isNull);
      expect(await s.dropTaskPoolItem(item), isNull);
      expect((await db.collection('daily_task_pool').doc('tp-new').get()).exists,
          isFalse);
    });

    // ------------------------------------------------------------------
    // [BE-12b]：第五個、也是最後一個補上寫回路徑的集合。
    //
    // 它比另外四個晚了一天，因為後台改的 `unlockCoins` 原本**不在**
    // `PlatformPlanSpec` 上（只活在 `WorkoutPlan`），直接寫回去會被
    // 靜靜丟掉 —— 存了、看起來成功、而那個欄位根本沒被送出去。
    // ------------------------------------------------------------------

    /// 一份真的雲端課表（27 份 CSV 課表之一），不是七份示範假課表。
    WorkoutPlan cloudPlan(AppState s) =>
        s.platformPlans.firstWhere((p) => s.planSpecById.containsKey(p.id));

    test('訓練計畫：階級門檻與解鎖價格都進得了雲端', () async {
      final p = cloudPlan(s);
      expect(s.setPlanConfig(p, requiredRank: 40, unlockCoins: 300), isNull);
      expect(await s.pushPlanSpec(p.id), isNull);

      final doc = await db.collection('plans').doc(p.id).get();
      expect(doc.data()!['requiredRank'], 40);
      expect(doc.data()!['unlockCoins'], 300,
          reason: '這一欄就是 [BE-12b] 卡住的原因 —— 它原本無處可存');
    });

    test('把價格清空也要寫得上去 —— 那與「沒改」是兩件事', () async {
      final p = cloudPlan(s);
      s.setPlanConfig(p, requiredRank: 40, unlockCoins: 300);
      await s.pushPlanSpec(p.id);
      final after = s.platformPlans.firstWhere((x) => x.id == p.id);

      expect(s.setPlanConfig(after, requiredRank: null, unlockCoins: null),
          isNull);
      expect(await s.pushPlanSpec(p.id), isNull);

      final doc = await db.collection('plans').doc(p.id).get();
      expect(doc.data()!['unlockCoins'], isNull);
      expect(doc.data()!['requiredRank'], isNull);
    });

    test('改完之後重新從雲端載入，設定還在', () async {
      final p = cloudPlan(s);
      s.setPlanConfig(p, requiredRank: 40, unlockCoins: 300);
      await s.pushPlanSpec(p.id);

      // 這正是登入時走的那條路 —— 之前就是它把後台的改動洗掉的。
      s.applyPlatformData(
          await FirestorePlatformData(firestore: db).load());

      final back = s.platformPlans.firstWhere((x) => x.id == p.id);
      expect(back.unlockCoins, 300);
      expect(back.requiredRank, 40);
    });

    test('改一份課表不會動到別份的適用經驗與目標', () async {
      final p = cloudPlan(s);
      s.setPlanConfig(p, requiredRank: 40, unlockCoins: 300);
      await s.pushPlanSpec(p.id);

      final doc = await db.collection('plans').doc(p.id).get();
      expect(doc.data()!['suitableGoals'], isNotEmpty,
          reason: '寫回去的是整份規格，那兩欄要跟著走，不能被清掉');
    });

    test('示範用假課表沒有雲端對應，要講出來而不是默默成功', () async {
      // 七份 kPlans 不在 planSpecById 裡 —— 它們不是平台資料。
      final demo =
          s.platformPlans.firstWhere((p) => !s.planSpecById.containsKey(p.id));
      expect(await s.pushPlanSpec(demo.id), contains('示範'));
      expect((await db.collection('plans').doc(demo.id).get()).exists, isFalse);
    });
  });

  group('寫不上去要講出來，不能假裝成功', () {
    test('雲端壞掉時回傳說明，而且說得出會打回原形', () async {
      final broken = AppState()..platformSource = _Broken();
      broken.applySettings('reward', {'trainCoin': 45});

      final why = await broken.pushConfigGroup('reward');

      expect(why, isNotNull);
      expect(why, contains('打回原形'),
          reason: '管理員要知道這次沒存進去，不然他下次登入才發現');
    });

    test('開發者模式的管理員：當場說「寫不上雲」，不要等到下次登入才發現', () async {
      final fake = AppState()
        ..platformSource = FirestorePlatformData(firestore: db)
        ..adminMode = true
        ..adminClaim = false;
      fake.applySettings('reward', {'trainCoin': 45});

      final why = await fake.pushConfigGroup('reward');

      expect(why, isNotNull);
      expect(why, contains('沒有管理員標記'));
      expect((await db.collection('platform_config').doc('reward').get()).exists,
          isFalse, reason: '本來就寫不進去，連試都不必試');
    });

    test('帶著管理員標記就照常寫', () async {
      final boss = AppState()
        ..platformSource = FirestorePlatformData(firestore: db)
        ..adminMode = true
        ..adminClaim = true;
      boss.applySettings('reward', {'trainCoin': 45});
      expect(await boss.pushConfigGroup('reward'), isNull);
    });

    test('沒接雲端就當作成功 —— 既有測試與示範走這條', () async {
      final offline = AppState();
      offline.applySettings('reward', {'trainCoin': 45});
      expect(await offline.pushConfigGroup('reward'), isNull);
    });

    test('後備來源是唯讀的，寫進去不會爆', () async {
      final bundled = AppState()
        ..platformSource = const BundledPlatformData();
      expect(await bundled.pushConfigGroup('reward'), isNull);
    });
  });
}
