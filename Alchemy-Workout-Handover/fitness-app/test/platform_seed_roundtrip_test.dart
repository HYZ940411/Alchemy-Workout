// 上傳上去的種子，讀回來要跟打包的那份一模一樣（[BE-12]，2026-09-28）。
//
// ## 這條測試擋的是什麼
//
// `[BE-12]` 的程式碼 2026-09-13 就寫好了，但**從來沒有被驗證過**
// （當時的開發機跑不動 Flutter），而且正式環境那五個集合一直是**空的** ——
// App 一路都在用打包的後備資料。
//
// 上傳的那一刻才是它第一次真的生效。而最糟的失敗長這樣：
// **上傳成功、App 讀得到、但內容跟原本的不一樣** —— 沒有錯誤訊息，
// 只有使用者某天發現動作的休息秒數變了、某個成就永遠解不開。
//
// 所以這裡走完整條路：
//
//   BundledPlatformData → *ToMap（匯出工具用的那一組）
//     → jsonEncode／jsonDecode（**上傳腳本是吃 JSON 的**）
//     → 寫進 Firestore → FirestorePlatformData.load()
//     → 與 BundledPlatformData 逐筆比對
//
// jsonEncode／jsonDecode 那一段不是多餘的：JSON 不分 int 與 double，
// 而 Dart 分。少了它，這條測試會漏掉「上傳之後整數變成小數」這一類。

import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/platform_data.dart';
import 'package:fitness_app/data/platform_data_firestore.dart';

void main() {
  late PlatformData bundle;
  late FakeFirebaseFirestore db;

  setUp(() async {
    bundle = await const BundledPlatformData().load();
    db = FakeFirebaseFirestore();

    // 匯出 → JSON 字串 → 解析回來 → 上傳。這一整段就是
    // `export_platform_defs.dart` ＋ `upload_platform_data.py` 做的事。
    final asJson =
        jsonDecode(jsonEncode(platformSeedMap(bundle))) as Map<String, dynamic>;
    for (final c in asJson.entries) {
      for (final doc in (c.value as Map<String, dynamic>).entries) {
        await db
            .collection(c.key)
            .doc(doc.key)
            .set(doc.value as Map<String, dynamic>);
      }
    }
  });

  Future<PlatformData> fromCloud() =>
      FirestorePlatformData(firestore: db).load();

  test('五類的筆數都對得上', () async {
    final got = await fromCloud();
    expect(got.exercises.length, bundle.exercises.length);
    expect(got.planSpecs.length, bundle.planSpecs.length);
    expect(got.achievements.length, bundle.achievements.length);
    expect(got.taskPool.length, bundle.taskPool.length);
    expect(got.config.length, bundle.config.length);
  });

  test('動作庫逐筆一模一樣', () async {
    final got = {for (final e in (await fromCloud()).exercises) e.id: e};
    for (final want in bundle.exercises) {
      final g = got[want.id];
      expect(g, isNotNull, reason: '${want.id} 上雲之後不見了');
      expect(exerciseToMap(g!), exerciseToMap(want),
          reason: '${want.name}（${want.id}）繞一圈之後變了');
    }
  });

  test('課表逐筆一模一樣 —— 含詳情頁的長文與攤平的組數', () async {
    final got = {for (final s in (await fromCloud()).planSpecs) s.id: s};
    for (final want in bundle.planSpecs) {
      expect(planSpecToMap(got[want.id]!), planSpecToMap(want),
          reason: '${want.name}（${want.id}）繞一圈之後變了');
    }
  });

  // **上面那條測試曾經漏掉兩個欄位，而且是結構性的漏。**
  //
  // 它拿 `planSpecToMap(收到的)` 比 `planSpecToMap(想要的)` —— 兩邊都是
  // 同一支序列化函式。函式少寫一個欄位的時候，**兩邊會一起少**，
  // 於是它們仍然相等，測試照樣是綠的。
  //
  // 實際發生的事：`suitableExperience`／`suitableGoals`（`[QA-02l]` 補的
  // 那兩欄，27 份課表逐一判定、使用者 2026-09-18 逐列審核）從來沒有被
  // 序列化過。2026-09-28 平台資料上雲之後，雲端那 27 筆兩欄皆空，
  // 而 `recommendPlan` **把空集合視為「全部符合」**，於是每一份課表
  // 又重新宣稱適合所有人 —— 推薦退回只靠器材篩，`[QA-02l]` 被默默撤銷。
  //
  // 所以這一條不碰 `planSpecToMap`，直接比欄位。
  test('課表的欄位逐一比對 —— 不經過序列化函式，它自己可能就是壞的', () async {
    final got = {for (final s in (await fromCloud()).planSpecs) s.id: s};
    for (final want in bundle.planSpecs) {
      final g = got[want.id];
      expect(g, isNotNull, reason: '${want.id} 上雲之後不見了');
      final why = '${want.name}（${want.id}）';
      expect(g!.name, want.name, reason: why);
      expect(g.level, want.level, reason: why);
      expect(g.requiredRank, want.requiredRank, reason: why);
      expect(g.unlockCoins, want.unlockCoins, reason: why);
      expect(g.equipmentTier, want.equipmentTier, reason: why);
      expect(g.suitableExperience, want.suitableExperience, reason: why);
      expect(g.suitableGoals, want.suitableGoals, reason: why);
      expect(g.duration, want.duration, reason: why);
      expect(g.intro, want.intro, reason: why);
      expect(g.howTo, want.howTo, reason: why);
      expect(g.load, want.load, reason: why);
      expect(g.effect, want.effect, reason: why);
      expect(g.technique, want.technique, reason: why);
      expect(g.reference, want.reference, reason: why);
      expect(g.items.length, want.items.length, reason: why);
    }
  });

  // 上面那條只比得到「兩邊一樣」。這一條盯的是**內容本身不是空的** ——
  // 如果哪天資料源頭把那兩欄清空了，兩邊仍然會一樣，而推薦仍然會壞。
  test('適用經驗與適用目標真的有東西 —— 空集合等於不篩選', () async {
    final got = (await fromCloud()).planSpecs;
    expect(got.where((s) => s.suitableExperience.isNotEmpty).length,
        got.length,
        reason: '每一份課表都要有適用經驗，否則 recommendPlan 視為全部符合');
    expect(got.where((s) => s.suitableGoals.isNotEmpty).length, got.length,
        reason: '同上 —— 這兩欄是 [QA-02l] 的全部內容');
  });

  test('成就定義逐筆一模一樣', () async {
    final got = {
      for (final a in (await fromCloud()).achievements) achievementDocId(a): a,
    };
    for (final want in bundle.achievements) {
      expect(achievementToMap(got[achievementDocId(want)]!),
          achievementToMap(want));
    }
  });

  test('每日任務池逐筆一模一樣', () async {
    final got = {for (final t in (await fromCloud()).taskPool) t.id: t};
    for (final want in bundle.taskPool) {
      expect(taskPoolItemToMap(got[want.id]!), taskPoolItemToMap(want));
    }
  });

  test('平台設定：每一群的每一個參數都對得上，而且型別沒變', () async {
    final got = (await fromCloud()).config;
    for (final group in bundle.config.entries) {
      final g = got[group.key];
      expect(g, isNotNull, reason: '設定群組 ${group.key} 不見了');
      expect(g!.keys.toSet(), group.value.keys.toSet());
      for (final p in group.value.entries) {
        expect(g[p.key], p.value,
            reason: '${group.key}.${p.key} 繞一圈之後變了');
        // **型別也要一樣。** JSON 不分 int 與 double，整數變成小數的話
        // `isInt` 的參數會在別處被取整，而那是無聲的。
        expect(g[p.key].runtimeType, p.value.runtimeType,
            reason: '${group.key}.${p.key} 的型別變了');
      }
    }
  });
}
