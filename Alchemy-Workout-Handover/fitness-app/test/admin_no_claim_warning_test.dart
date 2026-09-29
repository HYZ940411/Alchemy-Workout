// 沒有管理員標記的人進後台，一定要看到警告（P131）。
//
// ## 這個警告本來永遠不會出現
//
// 原本的條件是 `adminMode && !adminClaim`，而：
//
// - `toggleAdminMode()` **全 App 零個呼叫端** —— `adminMode` 永遠是 false
// - `applyAdminClaim(false)` 還會把它強制設回 false
//
// 兩個條件湊不齊，那塊警告是死程式碼。而既有測試是綠的，
// 因為它們直接 `..adminMode = true` —— **從一個 App 不會進入的狀態出發**。
//
// 使用者 2026-09-29 測 P131 回報 B（沒有任何警告）。
//
// 所以這裡刻意**不碰 `adminMode`**：只走 App 真正會走的那條路
// （`applyAdminClaim`），驗它在那個狀態下說不說得出話。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/platform_data.dart';
import 'package:fitness_app/screens/admin/admin_home_screen.dart';
import 'package:fitness_app/state/app_state.dart';

/// 假的平台資料來源 —— 有接雲端才會走到「寫不上去」那條判斷。
class _Src implements PlatformDataSource {
  final puts = <String>[];
  @override
  Future<PlatformData> load() => const BundledPlatformData().load();
  @override
  Future<void> put(String c, String id, Map<String, dynamic> d) async =>
      puts.add('$c/$id');
  @override
  Future<void> remove(String c, String id) async {}
}

void main() {
  Future<void> open(WidgetTester t, AppState s) async {
    await t.pumpWidget(AppScope(
      state: s,
      child: const MaterialApp(home: AdminHomeScreen()),
    ));
    await t.pumpAndSettle();
  }

  testWidgets('沒有標記的帳號進後台 → 出現黃色警告', (t) async {
    // **只呼叫 App 真的會呼叫的那一支。** 不碰 adminMode。
    final s = AppState()..applyAdminClaim(false);
    expect(s.adminMode, isFalse, reason: '這正是實際會發生的狀態');

    await open(t, s);
    expect(find.text('這個帳號沒有管理員標記'), findsOneWidget);
    expect(find.textContaining('改任何東西都寫不上雲'), findsOneWidget);
  });

  testWidgets('帶標記的帳號不該看到警告 —— 全部都警告等於沒警告', (t) async {
    final s = AppState()..applyAdminClaim(true);
    await open(t, s);
    expect(find.text('這個帳號沒有管理員標記'), findsNothing);
  });

  testWidgets('沒有標記時，寫回雲端要當場回一句話而不是默默成功', (t) async {
    final s = AppState()
      ..applyAdminClaim(false)
      ..platformSource = _Src();
    final why = await s.pushConfigGroup('reward');
    expect(why, contains('沒有管理員標記'));
    expect((s.platformSource! as _Src).puts, isEmpty,
        reason: '既然寫不上去，就不該真的送出去');
  });

  testWidgets('帶標記時照常寫', (t) async {
    final s = AppState()
      ..applyAdminClaim(true)
      ..platformSource = _Src();
    expect(await s.pushConfigGroup('reward'), isNull);
    expect((s.platformSource! as _Src).puts, isNotEmpty);
  });
}
