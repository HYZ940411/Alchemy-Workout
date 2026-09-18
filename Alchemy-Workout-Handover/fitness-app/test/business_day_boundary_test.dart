// 凌晨 00:00–03:59 的「今天」（2026-09-19）。
//
// 全專案的換日時點是當地 04:00（`00_全域規範.md`）。`clock.dart` 對
// `businessDate` 的註解寫著一句預言：兩套「今天」的差別「在那段時間以外
// 完全看不出來」。
//
// 這份測試就是把那四個小時固定下來。原本 `AppState.daysAgo` 用的是日曆日，
// 而補簽日曆是從 `businessDate(now)` 往回數的 —— 於是凌晨一點打開補簽頁，
// 日期與「能不能補」對不起來。
//
// **它是怎麼被發現的**：使用者在 02:13 跑了一次全量測試，兩條紅的；
// 同一份程式碼在 05:38、06:09、06:29 三次都全綠。時間戳就是線索。

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/clock.dart';
import 'package:fitness_app/state/app_state.dart';

/// 把展示時鐘固定在今天的某個鐘點。
void _setHour(int hour) {
  resetAppClock();
  final n = DateTime.now();
  appClockOffset =
      DateTime(n.year, n.month, n.day, hour, 30).difference(n);
}

void main() {
  tearDown(resetAppClock);

  for (final hour in [0, 1, 3]) {
    group('凌晨 $hour 點半', () {
      test('補簽日曆的距今天數仍是 1 至 N，不偏移', () {
        _setHour(hour);
        final s = AppState();
        expect(
          s.makeupDaysInRange.map((d) => s.daysAgo(d.date)).toList(),
          [for (var i = s.makeupRangeDays; i >= 1; i--) i],
        );
      });

      test('最遠那一天正好在端點上，補得回來', () {
        _setHour(hour);
        final s = AppState();
        final far = s.makeupDaysInRange.first;
        expect(s.daysAgo(far.date), s.makeupRangeDays);
        // 「只補得回最近 N 天」是超出範圍的訊息。端點那天不該收到它。
        expect(s.makeupBlockedReason(far), isNot(contains('只補得回')));
      });
    });
  }

  group('04:00 之後（同一天的正常時段）', () {
    test('行為與凌晨一致 —— 這一條是對照組', () {
      _setHour(10);
      final s = AppState();
      expect(
        s.makeupDaysInRange.map((d) => s.daysAgo(d.date)).toList(),
        [for (var i = s.makeupRangeDays; i >= 1; i--) i],
      );
    });
  });

  test('daysAgo 的基準是營業日，不是日曆日', () {
    // 直接釘住那個換算。凌晨 1 點半時，日曆日是今天、營業日是昨天；
    // 「昨天」這一天對營業日而言距今 0 天。
    _setHour(1);
    final s = AppState();
    final calendarToday = DateTime.now();
    final yesterday = DateTime(
        calendarToday.year, calendarToday.month, calendarToday.day)
        .subtract(const Duration(days: 1));
    expect(s.daysAgo(yesterday), 0, reason: '凌晨一點的「今天」是前一個自然日');
  });
}
