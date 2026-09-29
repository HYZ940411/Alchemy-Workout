// 課表的適用經驗與適用目標（`[QA-02l]`）。
//
// 使用者回報「訓練計畫的標籤待完善（進階、增肌等）」。查下去發現不只是
// 沒畫出來 —— **27 份平台課表的這兩欄全是空集合**。
//
// 而 `recommendPlan` 把空集合視為「全部符合」，所以每一份課表都宣稱
// 適合所有經驗、所有目標，推薦實際上只靠器材在篩。這份測試釘住的就是
// 「填了之後真的會篩」。
//
// 兩欄的來源不同：經驗由級別機械對應；目標依各課表自己寫的「訓練效果」欄
// 判定，2026-09-18 由使用者逐列審核通過。對應表在
// `tools/gen_platform_plans.py`，不可手改 `.g.dart`。

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/models.dart';
import 'package:fitness_app/domain/registration.dart';
import 'package:fitness_app/mock/mock_data.dart';
import 'package:fitness_app/mock/platform_exercises.g.dart';
import 'package:fitness_app/mock/platform_plans.g.dart';

void main() {
  // 只驗《健身計劃.csv》那 27 份 —— 2026-09-29 起 `buildCsvPlans()` 還含
  // 四份從 `kPlans` 搬上雲的官方課表，而「級別 → 適用經驗」那條機械對應
  // 是 `gen_platform_plans.py` 對 CSV 做的，那四份不適用。
  final plans = buildCsvPlansFrom(kPlatformPlans, kPlatformExercises);
  final byId = {for (final p in plans) p.id: p};

  group('每一份課表都標得出適用對象', () {
    test('27 份都有適用經驗，沒有空的', () {
      expect(plans, hasLength(27));
      for (final p in plans) {
        expect(p.suitableExperience, isNotEmpty, reason: '${p.name} 沒有適用經驗');
      }
    });

    test('27 份都有適用目標，沒有空的', () {
      for (final p in plans) {
        expect(p.suitableGoals, isNotEmpty, reason: '${p.name} 沒有適用目標');
      }
    });

    test('標的值都在註冊問卷的值域裡', () {
      // 打錯一個字就永遠比對不中，而且不會有任何錯誤訊息。
      for (final p in plans) {
        for (final e in p.suitableExperience) {
          expect(kExperience, contains(e), reason: '${p.name} 的「$e」不在值域裡');
        }
        for (final g in p.suitableGoals) {
          expect(kCommonGoals, contains(g), reason: '${p.name} 的「$g」不在值域裡');
        }
      }
    });
  });

  group('級別 → 適用經驗的對應', () {
    String levelOf(String id) => kPlanSpecById[id]!.level;

    test('學員級是新手、戰士級是中階、精銳級是進階', () {
      for (final p in plans) {
        final want = switch (levelOf(p.id)) {
          '學員級' => '新手（未滿 6 個月）',
          '戰士級' => '中階（6 個月–2 年）',
          '精銳級' => '進階（2 年以上）',
          _ => null,
        };
        if (want == null) continue;
        expect(p.suitableExperience.toList(), [want], reason: p.name);
      }
    });

    test('功能重啟級三級都適用', () {
      // 功能性課表是活動度與復健性質，跟訓練年資無關 ——
      // 練了五年的人肩頸痛一樣該做。只標新手的話，中階／進階
      // 在退步或受傷後推薦不到它（2026-09-18 使用者裁決）。
      final fn = plans.where((p) => levelOf(p.id) == '功能重啟級').toList();
      expect(fn, hasLength(3));
      for (final p in fn) {
        expect(p.suitableExperience.toSet(), kExperience.toSet(), reason: p.name);
      }
    });
  });

  group('幾條依「訓練效果」欄判定的目標', () {
    test('代謝優化 → 減重', () {
      // 效果欄原文：「促進減脂與代謝效率」。
      expect(byId['csv05']!.suitableGoals, contains('減重'));
    });

    test('肌力強化 → 增肌，且不含減重', () {
      // 效果欄原文：「提升肌肉量與肌力」。
      expect(byId['csv06']!.suitableGoals, contains('增肌'));
      expect(byId['csv06']!.suitableGoals, isNot(contains('減重')));
    });

    test('體能續航 → 提升體能', () {
      expect(byId['csv07']!.suitableGoals, contains('提升體能'));
    });

    test('無器材-全身 → 含減重（效果欄寫的是有氧負荷）', () {
      // 名稱看不出目標，但效果欄寫「快速提升心率…有氧負荷」。
      // 這一條證明對應不是照名字猜的。
      expect(byId['csv04']!.suitableGoals, contains('減重'));
    });
  });

  group('填了之後推薦真的會篩', () {
    WorkoutPlan? pick({
      required String equipment,
      required String experience,
      required String goal,
    }) =>
        recommendPlan<WorkoutPlan>(
          plans,
          equipment: equipment,
          experience: experience,
          commonGoal: goal,
          tierOf: (p) => p.equipmentTier,
          experienceOf: (p) => p.suitableExperience,
          goalsOf: (p) => p.suitableGoals,
        );

    test('新手徒手想減重，推薦到的課表真的標著減重', () {
      final p = pick(
        equipment: '徒手',
        experience: '新手（未滿 6 個月）',
        goal: '減重',
      )!;
      expect(p.suitableGoals, contains('減重'));
      expect(p.suitableExperience, contains('新手（未滿 6 個月）'));
    });

    test('同樣的器材與經驗，換個目標就換一份課表', () {
      // 這一條是整份測試的重點：填之前兩者會拿到同一份
      //（空集合＝全部符合，於是分數一樣，取索引最小的那份）。
      final lose = pick(
        equipment: '徒手',
        experience: '新手（未滿 6 個月）',
        goal: '減重',
      )!;
      final muscle = pick(
        equipment: '徒手',
        experience: '新手（未滿 6 個月）',
        goal: '增肌',
      )!;
      expect(lose.id, isNot(muscle.id));
    });
  });
}
