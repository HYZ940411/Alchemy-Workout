// 訓練結算：給的獎勵與帳上增加的一致，而且重新整理之後不會重領（第二批第 5 項）。
//
// 規則：訓練獎勵每日最多發放一次，金幣以當日最高完成度為準，後續只補差額
// （〈訓練結算流程〉）。這條「當日已領多少」若不進存檔，使用者重新整理頁面再練一場
// 就能重領一次。

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/store.dart';
import 'package:fitness_app/domain/clock.dart';
import 'package:fitness_app/domain/rewards.dart';
import 'package:fitness_app/mock/mock_data.dart';
import 'package:fitness_app/state/app_state.dart';

final _plan = kAllPlans.firstWhere((p) => p.id == 'p_push');

Future<MemoryStore> _account() async {
  final st = MemoryStore();
  final seed = AppState(demo: false);
  await seed.hydrate(MemoryStore());
  seed.signUpCompleted = true;
  await st.save(seed.toSnapshot());
  return st;
}

Future<AppState> _load(MemoryStore st) async {
  final s = AppState(demo: false);
  await s.hydrate(st);
  return s;
}

/// 練一場：把整份課表勾完（組間隔 45 秒過防作弊）再結算。
SettlementResult _train(AppState s) {
  s.startWorkout(_plan);
  var guard = 0;
  while (s.currentRecord != null && guard++ < 80) {
    s.advanceDemoClock(const Duration(seconds: 45));
    if (!s.completeCurrentSet()) break;
  }
  return s.finishWorkout(EndKind.completed);
}

void main() {
  setUp(() {
    // 吃真實時鐘的測試要先把時鐘挪到當天正午：換日時點是當地 04:00，
    // 在 0 到 4 點之間跑，「同一天」會被切成兩天，測試只在凌晨紅。
    resetAppClock();
    final n = appNow();
    appClockOffset += Duration(hours: 12 - n.hour, minutes: -n.minute);
  });
  tearDown(resetAppClock);

  test('結算給的獎勵 ＝ 帳上增加的', () async {
    final s = await _load(await _account());
    final coins0 = s.coins;
    final exp0 = s.totalExp;
    final hist0 = s.history.length;
    final w0 = s.totalWorkouts;

    final r = _train(s);

    expect(r.rewards.coins, greaterThan(0), reason: '前提：這場有金幣可領');
    expect(s.coins - coins0, r.rewards.coins);
    expect(s.totalExp - exp0, r.rewards.exp);
    expect(s.history.length, hist0 + 1);
    expect(s.totalWorkouts, w0 + 1);
    expect(r.doneSets, r.plannedSets, reason: '整份課表都勾完');
  });

  test('重新整理後，帳上的數字一樣', () async {
    final st = await _account();
    final s = await _load(st);
    _train(s);
    await s.saveNow();

    final back = await _load(st);
    expect(back.coins, s.coins);
    expect(back.totalExp, s.totalExp);
    expect(back.history.length, s.history.length);
    expect(back.totalWorkouts, s.totalWorkouts);
    expect(back.trainingStreakDays, s.trainingStreakDays);
    for (final d in s.points.keys) {
      expect(back.points[d], s.points[d], reason: '能力值 $d');
    }
  });

  test('當日獎勵只發一次：重新整理再練一場，不會重領', () async {
    final st = await _account();
    final s = await _load(st);
    final first = _train(s);
    expect(first.rewards.coins, greaterThan(0));
    await s.saveNow();

    final back = await _load(st);
    final coins0 = back.coins;
    final exp0 = back.totalExp;
    final second = _train(back);

    expect(first.rewards.exp, greaterThan(0), reason: '前提：第一場有經驗值可領');
    expect(second.rewards.coins, 0, reason: '同一天、同樣完成度，金幣已領過');
    expect(second.rewards.exp, 0, reason: '經驗值每日只發一次');
    expect(back.coins - coins0, 0);
    expect(back.totalExp - exp0, 0);
  });

  test('一組都沒做就結束：什麼都不給、也不留紀錄', () async {
    final s = await _load(await _account());
    final coins0 = s.coins;
    final hist0 = s.history.length;
    s.startWorkout(_plan);
    final r = s.finishWorkout(EndKind.endedEarly);

    expect(r.doneSets, 0);
    expect(s.coins, coins0);
    expect(s.history.length, hist0);
  });
}
