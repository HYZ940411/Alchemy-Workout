// 六維的時間維度：現在／30 天前／90 天前。
//
// 快照的鍵是「幾天前」，會隨著日子往前漂 ——[30, 90] 過一天就變成 [31, 91]。
// 畫面若寫死查 snapshots[30]，查不到又默默退回現在的點數，
// 三個檔位就會長得一模一樣，而且**看不出哪裡壞了**。

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/ability.dart';
import 'package:fitness_app/state/app_state.dart';

List<int> pts(AppState s) => [for (final d in Dim.values) s.displayedPoints[d]!];

void main() {
  test('全新狀態：三個檔位各不相同', () {
    final s = AppState();
    s.setSnapshot(0);
    final now = pts(s);
    s.setSnapshot(30);
    final d30 = pts(s);
    s.setSnapshot(90);
    final d90 = pts(s);
    expect(d30, isNot(now));
    expect(d90, isNot(now));
    expect(d90, isNot(d30));
  });

  test('過了幾天，鍵漂掉了，三個檔位仍各不相同', () {
    final s = AppState();
    s.advanceDemoClock(const Duration(days: 1));
    expect(s.snapshots.containsKey(30), isFalse, reason: '前提：鍵確實會漂');

    s.setSnapshot(0);
    final now = pts(s);
    s.setSnapshot(30);
    final d30 = pts(s);
    s.setSnapshot(90);
    final d90 = pts(s);
    expect(d30, isNot(now), reason: '查不到就退回現在的話，這裡會相等');
    expect(d90, isNot(now));
    expect(d90, isNot(d30));
  });

  test('漂很久之後也一樣', () {
    final s = AppState();
    s.advanceDemoClock(const Duration(days: 17));
    s.setSnapshot(0);
    final now = pts(s);
    s.setSnapshot(90);
    expect(pts(s), isNot(now));
  });

  test('切過去之後，停在真的存在的那一筆', () {
    final s = AppState();
    s.advanceDemoClock(const Duration(days: 1));
    s.setSnapshot(30);
    expect(s.snapshots.containsKey(s.snapshotDaysAgo), isTrue,
        reason: 'snapshotDaysAgo 不該停在查無此鍵的值上');
    expect(s.snapshotDaysAgo, 31);
  });

  test('檔位的標籤跟著資料走', () {
    final s = AppState();
    expect(s.snapshotOptions, [0, 30, 90]);
    s.advanceDemoClock(const Duration(days: 1));
    expect(s.snapshotOptions, [0, 31, 91],
        reason: '寫 30 天前卻給 31 天前的資料，就是在騙人');
  });

  test('沒有那麼久以前的紀錄時，不謊稱給得出', () {
    final s = AppState();
    s.snapshots.clear();
    expect(s.snapshotOptions, [0], reason: '一筆歷史都沒有就只有「現在」');
    expect(s.snapshotAgeNear(90), isNull);
    s.setSnapshot(90);
    expect(s.snapshotDaysAgo, 0, reason: '切不過去就要留在現在，不是停在空的檔位');
  });

  test('只有一筆歷史時不重複列出同一筆', () {
    final s = AppState();
    s.snapshots
      ..clear()
      ..[5] = {for (final d in Dim.values) d: 100};
    expect(s.snapshotOptions, [0, 5],
        reason: '最接近 30 與最接近 90 的都是那一筆，只能列一次');
  });
}
