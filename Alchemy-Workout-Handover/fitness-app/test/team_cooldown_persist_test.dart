// 換隊冷卻要存進存檔（`[QA-09]`，使用者裁決 A，2026-10-19）。
//
// 以前 `teamLeftAt`／`_cooldownAtLeave` 只存在記憶體：重新整理就歸零，等於冷卻擋不住換隊。
// 現在存「退出的時戳」和「退出當下鎖住的冷卻長度（秒）」，剩餘時間仍由它們推導，不存倒數值。

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/store.dart';
import 'package:fitness_app/domain/platform_config.dart';
import 'package:fitness_app/state/app_state.dart';

/// 走存檔的來回：存成 JSON 再讀回一個全新的狀態 —— 等同重新整理。
AppState _reload(AppState before) {
  final snap = jsonDecode(jsonEncode(before.toSnapshot())) as Map<String, dynamic>;
  final s = AppState();
  expect(s.applySnapshot(snap), isTrue);
  return s;
}

/// 剛退出隊伍的人（示範帳號的隊伍已加入 20 天，不在誤入的免罰窗口內，所以會進冷卻）。
AppState _justLeft() => AppState()..leaveTeam();

void main() {
  setUp(platformConfig.reset);
  tearDown(platformConfig.reset);

  test('前提：退隊後會進冷卻', () {
    final s = _justLeft();
    expect(s.switchCooldownLeft, greaterThan(Duration.zero));
  });

  test('重新整理（存檔來回）後冷卻還在，而且剩餘時間差不多', () {
    final before = _justLeft();
    final after = _reload(before);
    expect(after.switchCooldownLeft, greaterThan(Duration.zero),
        reason: '以前這裡是 0 —— 重新整理就能換隊');
    expect((before.switchCooldownLeft - after.switchCooldownLeft).inSeconds.abs(),
        lessThan(5));
    // 隊伍不在存檔裡（真實帳號由雲端載入；退隊後雲端沒有隊伍）。示範狀態會自己長出一支，先清掉。
    after.myTeam = null;
    expect(after.joinBlockedReason(after.publicTeams.firstWhere((t) => t.isPublic && !t.isFull)),
        contains('換隊冷卻中'));
  });

  test('真的走 hydrate（登入時讀存檔）：冷卻還在', () async {
    final before = _justLeft();
    final store = MemoryStore();
    await store.save(before.toSnapshot());
    final s = AppState();
    await s.hydrate(store);
    expect(s.switchCooldownLeft, greaterThan(Duration.zero));
  });

  test('冷卻長度是退出當下鎖住的：管理員之後調高參數，不延長已在冷卻中的人', () {
    final before = _justLeft();
    final left = before.switchCooldownLeft;
    platformConfig.group('team').param('cooldownHours').value = 24 * 30;
    final after = _reload(before);
    expect(after.switchCooldownLeft.inHours, lessThanOrEqualTo(left.inHours + 1),
        reason: '存的是退出當下的長度，不是現在的參數');
  });

  test('冷卻已經結束：存檔來回後是 0，不會又冒出一段冷卻', () {
    final s = _justLeft();
    s.teamLeftAt = DateTime.now().subtract(kTeamSwitchCooldown + const Duration(hours: 1));
    final after = _reload(s);
    expect(after.switchCooldownLeft, Duration.zero);
  });

  test('沒退出過：存檔來回後沒有冷卻', () {
    final after = _reload(AppState());
    expect(after.teamLeftAt, isNull);
    expect(after.switchCooldownLeft, Duration.zero);
  });

  test('誤入窗口內退出本來就不進冷卻，存檔來回後也不會有', () {
    final s = AppState()
      ..teamJoinedAt = DateTime.now().subtract(const Duration(minutes: 5))
      ..leaveTeam();
    expect(s.switchCooldownLeft, Duration.zero, reason: '前提');
    expect(_reload(s).switchCooldownLeft, Duration.zero);
  });

  test('新帳號歸零：不把上一個人的冷卻帶給下一個人', () {
    final s = _justLeft();
    expect(s.toSnapshot()['teamLeftAt'], isNotNull, reason: '前提：存檔裡有');
    s.resetToNewAccount();
    expect(s.teamLeftAt, isNull);
    expect(s.switchCooldownLeft, Duration.zero);
    expect(s.toSnapshot()['teamLeftAt'], isNull);
    expect(s.toSnapshot()['teamCooldownSecs'], isNull);
  });
}
