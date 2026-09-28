// 優化建議的記號活不過重新整理（P86，2026-09-28）。
//
// 使用者訂閱後回報「我沒看到優化建議的標籤」。**建議是產生了的**，
// 只是那個記號只存在於 `platformPlans[i].hasOptimizationSuggestion`，
// 而那份清單是**平台目錄** —— `applyPlatformData()` 每次登入都整份重建，
// 存檔也不含它。記號當場蒸發。
//
// 「哪一份課表掛著我的優化建議」是**使用者自己的資料**，不是目錄的。

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/platform_data.dart';
import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/domain/platform_config.dart';
import 'package:fitness_app/domain/rewards.dart';
import 'package:fitness_app/state/app_state.dart';

Future<AppState> _clean() async {
  final s = AppState();
  final p = s.aiOptimizePlan;
  if (p != null) {
    s.aiRequest(AiSource.autoOptimize, '調一下');
    await s.aiConfirmDemand(AiSource.autoOptimize, '整體降強度');
    s.aiProduceSuggestion(AiSource.autoOptimize);
    s.aiReject(AiSource.autoOptimize);
  }
  s.autoOptimizeCount = 0;
  return s;
}

void _train(AppState s, String planId) {
  s.startWorkout(s.platformPlans.firstWhere((p) => p.id == planId));
  s.completeCurrentSet();
  s.finishWorkout(EndKind.completed);
}

void main() {
  setUp(platformConfig.reset);
  tearDown(platformConfig.reset);

  _catalogueHasNoPersonalMarks();

  test('產生建議時記下是哪一份課表', () async {
    final s = await _clean()..subscribe(yearly: false);
    for (var i = 0; i < 3; i++) {
      _train(s, 'p_push');
    }
    expect(s.aiOptimizePlan, isNotNull);
    expect(s.optimizedPlanId, s.aiOptimizePlan!.id);
  });

  test('平台目錄整份重建之後，記號還在', () async {
    final s = await _clean()..subscribe(yearly: false);
    for (var i = 0; i < 3; i++) {
      _train(s, 'p_push');
    }
    final id = s.aiOptimizePlan!.id;

    // 這正是每次登入都會發生的事。
    s.applyPlatformData(PlatformData(
      exercises: s.platformExercises,
      planSpecs: s.planSpecById.values.toList(),
      achievements: s.achievements,
      taskPool: s.taskPool,
      config: const {},
    ));

    expect(s.aiOptimizePlan?.id, id, reason: '重建之後記號不該蒸發');
    expect(
      s.platformPlans.where((p) => p.hasOptimizationSuggestion).length,
      1,
      reason: '只該有一份掛著',
    );
  });

  test('存檔帶得走，載回來記號也回來', () async {
    final a = await _clean()..subscribe(yearly: false);
    for (var i = 0; i < 3; i++) {
      _train(a, 'p_push');
    }
    final id = a.aiOptimizePlan!.id;

    final b = AppState()..applySnapshot(a.toSnapshot());
    expect(b.optimizedPlanId, id);
    expect(b.aiOptimizePlan?.id, id, reason: '載回來要看得見那個標籤');
  });

  test('接受之後記號清掉，重建也不會冒出來', () async {
    final s = await _clean()..subscribe(yearly: false);
    for (var i = 0; i < 3; i++) {
      _train(s, 'p_push');
    }
    s.aiRequest(AiSource.autoOptimize, '調一下');
    await s.aiConfirmDemand(AiSource.autoOptimize, '整體降強度');
    s.aiProduceSuggestion(AiSource.autoOptimize);
    s.aiAccept(AiSource.autoOptimize);

    expect(s.optimizedPlanId, isNull);
    expect(s.aiOptimizePlan, isNull);
  });

  test('課表被下架時記號跟著失效，不留一個指向空氣的 ID', () async {
    final s = await _clean()..subscribe(yearly: false);
    for (var i = 0; i < 3; i++) {
      _train(s, 'p_push');
    }
    expect(s.optimizedPlanId, isNotNull);
    s.platformPlans.removeWhere((p) => p.id == s.optimizedPlanId);
    s.applyOptimizationMark();
    expect(s.optimizedPlanId, isNull);
  });

  // 0k③ 把寫死在平台目錄裡的 `lastTrainedAt` 移除了（那是「我上次練它
  // 是什麼時候」，每個人各自不同），但沒回頭看誰在讀它 ——
  // `_autoOptimizeTarget()` 的排序整段失效，永遠退回第一份官方課表。
  test('優化的是我最近練的那一份，不是清單上的第一份', () async {
    final s = await _clean()..subscribe(yearly: false);
    final official = s.platformPlans
        .where((p) => p.source == PlanSource.official && p.exercises.isNotEmpty)
        .toList();
    expect(official.length, greaterThan(1), reason: '前提：要有得挑');
    final later = official.last;

    _train(s, official.first.id);
    _train(s, later.id);
    _train(s, later.id);

    expect(s.aiOptimizePlan?.id, later.id,
        reason: '最近練的是 ${later.name}，不該挑 ${official.first.name}');
  });
}

// `p_custom`（「我的核心日」）在 `kPlans` 裡寫死了
// `hasOptimizationSuggestion: true` —— 那是「**我**有一份待看的建議」，
// 每個人各自不同，不該長在共用的課表目錄上。
//
// 與 0k③ 的 `lastTrainedAt`／`lastCompletion` 同一個家族：
// 使用者的資料寫進了平台目錄。
void _catalogueHasNoPersonalMarks() {
  test('課表目錄裡沒有任何一份預先掛著優化建議', () {
    final s = AppState();
    expect(
      s.platformPlans.where((p) => p.hasOptimizationSuggestion),
      isEmpty,
      reason: '一個沒練過任何一次的新帳號不該有優化建議',
    );
    expect(s.optimizedPlanId, isNull);
  });
}
