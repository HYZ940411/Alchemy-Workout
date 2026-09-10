// 連續簽到天數與上次簽到日期，都由每日簽到紀錄推導。
//
// 補簽頁的日曆畫出 9/4、9/5 連兩天已簽，首頁卻寫「連續 0 天」；
// 而 lastCheckInDate 是空值，等於一邊說「從來沒簽到過」、
// 另一邊畫出 9 個已簽到的格子。存兩份就會有兩份對不起來的事實。

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/state/app_state.dart';

/// 自昨日往回逐日數，與畫面上的日曆看到的是同一件事。
int streakFromCalendar(AppState s) {
  var n = 0;
  var d = businessDate(s.now);
  if (s.checkInMethodOn(d) == null) d = d.subtract(const Duration(days: 1));
  while (s.checkInMethodOn(d) != null) {
    n += 1;
    d = d.subtract(const Duration(days: 1));
  }
  return n;
}

void main() {
  test('連續天數與日曆上數出來的一致', () {
    final s = AppState();
    expect(s.checkInStreak, streakFromCalendar(s),
        reason: '日曆畫著連兩天已簽，首頁卻寫 0 天');
  });

  test('上次簽到日期是紀錄裡最晚的那一天', () {
    final s = AppState();
    expect(s.checkInRecords, isNotEmpty);
    final latest =
        s.checkInRecords.keys.reduce((a, b) => a.isAfter(b) ? a : b);
    expect(s.lastCheckInDate, latest);
  });

  test('簽到後兩者同步前進', () {
    final s = AppState();
    final before = s.checkInStreak;
    s.checkIn();
    expect(s.lastCheckInDate, businessDate(s.now));
    expect(s.checkInStreak, before + 1);
    expect(s.checkInStreak, streakFromCalendar(s));
  });

  test('補簽把斷點補起來，連續天數跟著重算', () {
    final s = AppState();
    final gap = s.makeupDaysInRange.firstWhere((d) => s.canMakeUp(d));
    s.useMakeupTicket(gap);
    expect(s.checkInStreak, streakFromCalendar(s),
        reason: '補簽只是往紀錄補一筆，連續天數整個重算');
  });

  test('清空紀錄，兩者一起歸零', () {
    final s = AppState();
    s.checkInRecords.clear();
    expect(s.lastCheckInDate, isNull);
    expect(s.checkInStreak, 0);
  });

  test('存讀一輪之後仍然一致 —— 不存這兩個欄位', () async {
    final s = AppState();
    s.checkIn();
    final snap = s.toSnapshot();
    expect(snap.containsKey('checkInStreak'), isFalse,
        reason: '存下來就會有兩份可能對不起來的事實');
    expect(snap.containsKey('lastCheckInDate'), isFalse);

    final back = AppState();
    back.applySnapshot(snap);
    expect(back.checkInStreak, s.checkInStreak);
    expect(back.lastCheckInDate, s.lastCheckInDate);
    expect(back.checkInStreak, streakFromCalendar(back));
  });

  test('舊存檔帶著這兩個欄位也不採信', () {
    final s = AppState();
    final snap = s.toSnapshot();
    snap['checkInStreak'] = 99;
    snap['lastCheckInDate'] = '2020-01-01T00:00:00.000';
    final back = AppState();
    back.applySnapshot(snap);
    expect(back.checkInStreak, isNot(99));
    expect(back.checkInStreak, streakFromCalendar(back));
  });
}
