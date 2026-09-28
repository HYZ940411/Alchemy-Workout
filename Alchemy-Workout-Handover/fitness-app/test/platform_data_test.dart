// 平台公用資料上雲（[BE-12]）的測試。
//
// 用 fake_cloud_firestore 而非 Firebase emulator，與既有測試同一哲學：
// 測試不碰網路、不起外部行程（見 store_firestore_test.dart 檔頭）。
// 代價是驗不到安全規則與網路故障 —— 前者靠 Console 的 Rules Playground、
// 後者靠人工測試。
//
// mock 邊界：不注入 PlatformDataSource 的既有 1,2xx 個測試完全走
// BundledPlatformData（＝打包在本地的種子），行為與上雲前一個位元都不差。
// 這裡補的是「注入 Firestore 之後」那條新路徑。

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/platform_data.dart';
import 'package:fitness_app/data/platform_data_firestore.dart';
import 'package:fitness_app/domain/ability.dart';
import 'package:fitness_app/domain/models.dart';
import 'package:fitness_app/domain/platform_config.dart';
import 'package:fitness_app/domain/platform_plan.dart';
import 'package:fitness_app/domain/task_pool.dart';
import 'package:fitness_app/mock/mock_data.dart';
import 'package:fitness_app/mock/platform_plans.g.dart';
import 'package:fitness_app/state/app_state.dart';

void main() {
  group('序列化原樣進出（*ToMap → *FromDoc）', () {
    test('動作：肌群、複選訓練部位、有氧型別、休息秒數都原樣回來', () {
      const e = Exercise(
        id: 'x1',
        name: '窄距臥推 · 槓鈴',
        dim: Dim.chest,
        parts: {Dim.chest, Dim.arms},
        relativeIntensity: 1.18,
        isBodyweight: false,
        equipment: '槓鈴',
        defaultRestSeconds: 90,
      );
      final back = exerciseFromDoc('x1', exerciseToMap(e));
      expect(back.id, 'x1');
      expect(back.name, e.name);
      expect(back.dim, Dim.chest);
      expect(back.parts, {Dim.chest, Dim.arms});
      expect(back.relativeIntensity, 1.18);
      expect(back.equipment, '槓鈴');
      expect(back.defaultRestSeconds, 90);
      expect(back.type, ExerciseType.strength);
    });

    test('有氧動作：dim 為 null、parts 為空、型別為 cardio', () {
      const e = Exercise(
        id: 'c1',
        name: '開合跳',
        dim: null,
        relativeIntensity: 0,
        type: ExerciseType.cardio,
      );
      final back = exerciseFromDoc('c1', exerciseToMap(e));
      expect(back.dim, isNull);
      expect(back.parts, isEmpty);
      expect(back.type, ExerciseType.cardio);
    });

    test('課表規格：六段長文與組數攤平原樣回來', () {
      const s = PlatformPlanSpec(
        id: 'csv99',
        name: '測試課表',
        level: '學員級',
        requiredRank: null,
        equipmentTier: '徒手',
        duration: '30min',
        intro: '介紹',
        howTo: '說明',
        load: '負荷',
        effect: '效果',
        technique: '技術',
        reference: '依據',
        items: [
          PlanItemSpec('p1', 3, 8, PlanUnit.reps, 90),
          PlanItemSpec('p2', 4, 40, PlanUnit.seconds, 60),
        ],
      );
      final back = planSpecFromDoc('csv99', planSpecToMap(s));
      expect(back.name, '測試課表');
      expect(back.requiredRank, isNull);
      expect(back.reference, '依據');
      expect(back.items.length, 2);
      expect(back.items[1].unit, PlanUnit.seconds);
      expect(back.items[1].amount, 40);
      expect(back.items[0].restSeconds, 90);
    });

    test('成就定義：doc id 為 category#name、獎勵原樣回來', () {
      final a = Achievement(
        category: '能力值',
        name: '任一維達 100 點',
        threshold: 100,
        rewardCoins: 100,
        rewardExp: 50,
      );
      // **不是 `能力值#100`。** 門檻是管理員改得動的欄位，拿它當文件 ID
      // 的話，後台改一次就在雲端多長出一筆（見 PROGRESS 1W）。
      expect(achievementDocId(a), '能力值#任一維達 100 點');
      final back = achievementFromDoc(achievementDocId(a), achievementToMap(a));
      expect(back.category, '能力值');
      expect(back.threshold, 100);
      expect(back.rewardCoins, 100);
      expect(back.rewardExp, 50);
      // 定義不帶使用者狀態。
      expect(back.unlocked, isFalse);
      expect(back.claimed, isFalse);
    });

    test('任務池：適用對象與獎勵定義 ID 原樣回來', () {
      final t = TaskPoolItem(
        id: 'tp9',
        name: '團隊循環',
        sourceEvent: '訓練已結算',
        target: 1,
        audience: TaskAudience.team,
        rewardId: 'daily',
      );
      final back = taskPoolItemFromDoc('tp9', taskPoolItemToMap(t));
      expect(back.id, 'tp9');
      expect(back.audience, TaskAudience.team);
      expect(back.rewardId, 'daily');
      expect(back.target, 1);
    });
  });

  group('FirestorePlatformData', () {
    test('空資料庫 → 五類全數退回本地後備', () async {
      final db = FakeFirebaseFirestore();
      final bundle = await const BundledPlatformData().load();
      final loaded = await FirestorePlatformData(firestore: db).load();
      expect(loaded.exercises.length, bundle.exercises.length);
      expect(loaded.planSpecs.length, bundle.planSpecs.length);
      expect(loaded.achievements.length, bundle.achievements.length);
      expect(loaded.taskPool.length, bundle.taskPool.length);
      expect(loaded.config.keys.toSet(), bundle.config.keys.toSet());
    });

    test('某一類有雲端資料即採雲端、其餘仍退回後備', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('exercises').doc('cloudex').set(exerciseToMap(
          const Exercise(
              id: 'cloudex',
              name: '雲端動作',
              dim: Dim.back,
              relativeIntensity: 1.0,
              equipment: '槓鈴')));

      final loaded = await FirestorePlatformData(firestore: db).load();
      // 動作庫採雲端（只有那一筆）。
      expect(loaded.exercises.length, 1);
      expect(loaded.exercises.single.name, '雲端動作');
      // 其餘仍是後備。
      final bundle = await const BundledPlatformData().load();
      expect(loaded.planSpecs.length, bundle.planSpecs.length);
      expect(loaded.achievements.length, bundle.achievements.length);
    });

    test('平台設定：雲端 params 覆寫、缺的鍵維持後備', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('platform_config').doc('reward').set({
        'params': {'trainCoin': 99},
      });
      final loaded = await FirestorePlatformData(firestore: db).load();
      expect(loaded.config['reward']!['trainCoin'], 99);
    });

    test('單筆格式壞掉略過，不拖垮整類', () async {
      final db = FakeFirebaseFirestore();
      // 一筆合法、一筆缺必要欄位（name）。
      await db.collection('exercises').doc('ok').set(exerciseToMap(
          const Exercise(
              id: 'ok',
              name: '好的',
              dim: Dim.chest,
              relativeIntensity: 1.0,
              equipment: '槓鈴')));
      await db.collection('exercises').doc('bad').set({'dim': 'chest'});
      final loaded = await FirestorePlatformData(firestore: db).load();
      expect(loaded.exercises.map((e) => e.id), ['ok']);
    });
  });

  group('AppState.applyPlatformData 套用到既有可變容器', () {
    tearDown(platformConfig.reset); // 平台設定是全域單例，避免污染其他測試

    test('動作庫被雲端取代；有氧分頁也跟著走雲端', () {
      final s = AppState();
      final before = s.platformExercises.length;
      s.applyPlatformData(PlatformData(
        exercises: const [
          Exercise(
              id: 'z1',
              name: '雲端重訓',
              dim: Dim.legs,
              relativeIntensity: 0.7,
              equipment: '槓鈴'),
          Exercise(
              id: 'z2',
              name: '雲端有氧',
              dim: null,
              relativeIntensity: 0,
              type: ExerciseType.cardio),
        ],
        planSpecs: const [],
        achievements: const [],
        taskPool: const [],
        config: const {},
      ));
      expect(s.platformExercises.length, 2);
      expect(s.platformExercises.length, isNot(before));
      // 有氧分頁 = 固定器材 + 動作庫裡的有氧。雲端有氧要出現在其中。
      expect(s.cardioExercises.any((e) => e.id == 'z2'), isTrue);
      // 固定的有氧器材（跑步機等）仍在。
      expect(s.cardioExercises.any((e) => e.id == 'treadmill'), isTrue);
    });

    test('平台設定被雲端覆寫，且 isInt 的參數取整', () {
      final s = AppState();
      expect(platformConfig.i('reward', 'trainCoin'), 30); // 後備預設
      s.applyPlatformData(const PlatformData(
        exercises: [],
        planSpecs: [],
        achievements: [],
        taskPool: [],
        config: {
          'reward': {'trainCoin': 88.6}
        },
      ));
      // 整數參數取整（沿用管理員編輯路徑的慣例）。
      expect(platformConfig.i('reward', 'trainCoin'), 89);
    });

    test('課表詳情（planSpecById）改讀雲端內容', () {
      final s = AppState();
      s.applyPlatformData(const PlatformData(
        exercises: [
          Exercise(
              id: 'p1',
              name: '動作',
              dim: Dim.chest,
              relativeIntensity: 1.0,
              equipment: '槓鈴'),
        ],
        planSpecs: [
          PlatformPlanSpec(
            id: 'csv00',
            name: '雲端課表',
            level: '學員級',
            requiredRank: null,
            equipmentTier: '徒手',
            duration: '30min',
            intro: '雲端介紹',
            howTo: '',
            load: '',
            effect: '',
            technique: '',
            reference: '依據',
            items: [PlanItemSpec('p1', 3, 8, PlanUnit.reps, 90)],
          ),
        ],
        achievements: [],
        taskPool: [],
        config: {},
      ));
      expect(s.planSpecById['csv00']!.intro, '雲端介紹');
      // 對應的 WorkoutPlan 也建出來了（kPlans 示範課表 + 雲端 csv 課表）。
      expect(s.platformPlans.any((p) => p.id == 'csv00'), isTrue);
    });
  });

  group('BundledPlatformData 與 App 既有種子一致（mock 邊界）', () {
    test('bundle 動作庫即 kExercises，課表即 kPlatformPlans', () async {
      final bundle = await const BundledPlatformData().load();
      expect(bundle.exercises.length, kExercises.length);
      expect(bundle.planSpecs.length, kPlatformPlans.length);
      // 平台設定涵蓋所有群組。
      expect(bundle.config.keys.toSet(),
          platformConfig.groups.map((g) => g.id).toSet());
    });
  });
}
