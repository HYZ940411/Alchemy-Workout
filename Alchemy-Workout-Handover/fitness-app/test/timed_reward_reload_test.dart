// 限時任務獎勵重新整理後又能再領一次（使用者 2026-10-21 回報「團隊的限時任務獎勵可以重複領取」）。
//
// 原因：存檔裡「我今天完成／領過了」記的是 `日期#重置代數`（管理員按過「重置所有人今天的限時任務」之後
// 代數大於 0），但登入時**先讀存檔、後讀雲端的代數**。讀存檔那一刻本機的代數還是 0，算出來的
// 識別只有日期，跟存檔裡的 `日期#代數` 對不上 —— 於是完成與已領旗標都被當成「別輪的」丟掉，
// 重新整理一次就能再完成、再領。代數是平台資料，雲端那份晚到，不能拿來比對存檔。

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/store.dart';
import 'package:fitness_app/domain/platform_config.dart';
import 'package:fitness_app/state/app_state.dart';

AppState _fresh() => AppState()
  ..displayName = '阿昶'
  ..myUid = 'u1';

/// 管理員重置過（代數 7）→ 我完成並領了獎勵 → 回傳那個狀態。
AppState _claimedAfterReset() {
  final s = _fresh()..applyTimedEpoch(7);
  s.completeTimedTask();
  expect(s.claimTimedReward(), isNotNull, reason: '前提：第一次領得到');
  expect(s.canClaimTimedReward, isFalse, reason: '前提：領完就不能再領');
  return s;
}

/// 登入的順序：先讀存檔，之後雲端的重置代數才到。
AppState _reloadLikeLogin(AppState before, {int? epochFromCloud = 7}) {
  final snap = jsonDecode(jsonEncode(before.toSnapshot())) as Map<String, dynamic>;
  final s = _fresh();
  expect(s.applySnapshot(snap), isTrue);
  s.applyTimedEpoch(epochFromCloud);
  return s;
}

/// 重新整理之後必須「記得我今天領過」：完成與已領旗標都在，而且就算再按一次完成，也領不到第二次。
///
/// **只斷言「現在不能領」不夠** —— 完成被忘掉時本來就不能領，卻會出現「開始限時任務」讓人重做、重領。
void _expectRemembersClaim(AppState s, {String? why}) {
  expect(s.timedTask.doneBy(s.displayName, uid: s.myUid), isTrue,
      reason: '${why ?? ''}我今天完成過，不能因為重新整理就忘記');
  expect(s.timedRewardClaimed, isTrue, reason: '${why ?? ''}已領過的旗標不能掉');
  final coins = s.coins;
  final exp = s.totalExp;
  s.completeTimedTask(); // 已完成就沒有作用；萬一被忘掉就會重做
  expect(s.claimTimedReward(), isNull, reason: '${why ?? ''}不能領第二次');
  expect(s.coins, coins);
  expect(s.totalExp, exp);
}

void main() {
  setUp(platformConfig.reset);
  tearDown(platformConfig.reset);

  test('重置過之後領了獎勵，重新整理：還是「已完成、已領過」，不能再領', () {
    final before = _claimedAfterReset();
    _expectRemembersClaim(_reloadLikeLogin(before));
  });

  test('真的走 hydrate（登入時讀存檔）：同樣不能再領', () async {
    final before = _claimedAfterReset();
    final store = MemoryStore();
    await store.save(before.toSnapshot());
    final s = _fresh();
    await s.hydrate(store);
    s.applyTimedEpoch(7);
    _expectRemembersClaim(s);
  });

  test('連續重新整理好幾次也一樣', () {
    var s = _claimedAfterReset();
    for (var i = 0; i < 3; i++) {
      s = _reloadLikeLogin(s);
      _expectRemembersClaim(s, why: '第 ${i + 1} 次重新整理：');
    }
  });

  test('這次讀不到雲端代數（空值）：沿用存檔的，也不能再領', () {
    _expectRemembersClaim(
        _reloadLikeLogin(_claimedAfterReset(), epochFromCloud: null));
  });

  test('管理員在我登出期間又重置了（代數 7 → 8）：舊的完成與領取自己失效，可以重做重領', () {
    final before = _claimedAfterReset();
    final after = _reloadLikeLogin(before, epochFromCloud: 8);
    expect(after.timedTask.doneBy(after.displayName, uid: after.myUid), isFalse);
    expect(after.timedRewardClaimed, isFalse);
    after.completeTimedTask();
    expect(after.claimTimedReward(), isNotNull, reason: '重置的目的就是讓大家重做、重領');
  });

  test('沒重置過（代數 0）：照舊，重新整理後不能再領', () {
    final s = _fresh();
    s.completeTimedTask();
    s.claimTimedReward();
    _expectRemembersClaim(_reloadLikeLogin(s, epochFromCloud: 0));
  });

  test('雲端代數已經讀到之後再讀存檔：以雲端為準，存檔裡舊的代數不能蓋掉它', () {
    // 同一個工作階段換帳號再登入：雲端代數早就讀到了（8），這位的存檔是在代數 7 時存的。
    final old = _claimedAfterReset(); // 代數 7 時完成並領取
    final snap = jsonDecode(jsonEncode(old.toSnapshot())) as Map<String, dynamic>;
    final s = _fresh()..applyTimedEpoch(8); // 已讀到雲端代數 8
    expect(s.applySnapshot(snap), isTrue);
    expect(s.timedEpoch, 8, reason: '不能被存檔裡的 7 蓋回去');
    expect(s.timedTask.doneBy(s.displayName, uid: s.myUid), isFalse,
        reason: '舊一輪的完成已失效');
  });

  test('代數是全平台共用的：登出（endSession）與新帳號歸零都不清它', () {
    final a = _claimedAfterReset();
    a.endSession();
    expect(a.timedEpoch, 7, reason: '登出');
    expect(a.timedRewardClaimed, isFalse, reason: '前提：登出會清上一個人的領取旗標');

    final b = _claimedAfterReset();
    b.resetToNewAccount();
    expect(b.timedEpoch, 7, reason: '新帳號歸零');
  });
}
