import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/commerce.dart';
import 'package:fitness_app/state/app_state.dart';

DateTime dayOf(AppState s, int daysAgo) {
  final t = s.now;
  return DateTime(t.year, t.month, t.day).subtract(Duration(days: daysAgo));
}

void main() {
  group('每日簽到紀錄：只存已簽到的日子', () {
    test('簽到寫入一筆，方式為真實簽到', () {
      final s = AppState();
      final today = dayOf(s, 0);
      expect(s.checkInMethodOn(today), isNull);
      s.checkIn();
      expect(s.checkInMethodOn(today), CheckInMethod.real);
    });

    test('未簽到之日查無此筆，即代表該日未簽到', () {
      final s = AppState();
      final missed = s.makeupDaysInRange
          .firstWhere((d) => d.state == MakeupDayState.missed);
      expect(s.checkInMethodOn(missed.date), isNull);
    });

    test('補簽寫入一筆，方式為補簽', () {
      final s = AppState();
      final d = s.makeupDaysInRange.firstWhere(s.canMakeUp);
      s.useMakeupTicket(d);
      expect(s.checkInMethodOn(d.date), CheckInMethod.makeup);
      expect(s.makeupDaysInRange
          .firstWhere((x) => x.date == d.date)
          .state, MakeupDayState.madeUp,
          reason: '日曆由紀錄推導，寫進去就該變成已補簽');
    });

    test('同一日至多一筆', () {
      final s = AppState();
      s.checkIn();
      final n = s.checkInRecords.length;
      s.checkIn(); // 已簽到者再按無效
      expect(s.checkInRecords.length, n);
    });
  });

  group('補簽日曆隨時鐘滾動', () {
    test('簽到那天，隔日會出現在日曆上且標為已簽到', () {
      final s = AppState();
      final today = dayOf(s, 0);
      s.checkIn();
      s.advanceDemoClock(const Duration(days: 1));
      final row = s.makeupDaysInRange.where((d) => d.date == today);
      expect(row, isNotEmpty, reason: '簽到那天不該從日曆上消失');
      expect(row.first.state, MakeupDayState.signed);
    });

    test('推進幾天後，中間沒簽到的日子補得回來', () {
      final s = AppState();
      s.checkIn();
      s.advanceDemoClock(const Duration(days: 3));
      final gap = s.makeupDaysInRange
          .where((d) => d.state == MakeupDayState.missed && s.daysAgo(d.date) <= 3)
          .toList();
      expect(gap.length, greaterThanOrEqualTo(2),
          reason: '那幾天既沒簽到也不該憑空消失');
      s.grantMakeupTickets(3);
      expect(s.canMakeUp(gap.first), isTrue);
    });

    test('日曆恆為距今 1 至 N 天，長度不隨時間縮水', () {
      final s = AppState();
      final n = s.makeupDaysInRange.length;
      expect(n, s.makeupRangeDays);
      s.advanceDemoClock(const Duration(days: 10));
      expect(s.makeupDaysInRange.length, n);
      expect(s.makeupDaysInRange.map((d) => s.daysAgo(d.date)).toList(),
          [for (var i = s.makeupRangeDays; i >= 1; i--) i]);
    });
  });

  group('連續簽到已恢復：逐日推算', () {
    test('補一天即接起前後兩段', () {
      final s = AppState();
      // 造一段：3 天前簽、2 天前沒簽、1 天前簽、今天簽。
      s.checkInRecords
        ..clear()
        ..[dayOf(s, 3)] = CheckInMethod.real
        ..[dayOf(s, 1)] = CheckInMethod.real;
      s.checkIn();
      expect(s.checkInStreak, greaterThan(0));

      final gap = s.makeupDaysInRange.firstWhere((d) => d.date == dayOf(s, 2));
      s.grantMakeupTickets(1);
      s.useMakeupTicket(gap);
      expect(s.checkInStreak, 4, reason: '斷點補起來，前後兩段接成一段');
    });

    test('未補齊者不跨越斷點', () {
      final s = AppState();
      s.checkInRecords
        ..clear()
        ..[dayOf(s, 4)] = CheckInMethod.real
        ..[dayOf(s, 3)] = CheckInMethod.real
        ..[dayOf(s, 1)] = CheckInMethod.real;
      s.checkIn();
      s.grantMakeupTickets(1);
      // 補 2 天前，但 4/3 天前那一段與今天之間仍有別的斷點？沒有 —— 補完即連成一段。
      expect(s.simulateStreakAfterMakeup(
              s.makeupDaysInRange.firstWhere((d) => d.date == dayOf(s, 2))),
          5);
    });

    test('斷點之外的舊區段不得被加進來', () {
      final s = AppState();
      // 6、5 天前是一段；4 天前是斷點；3、2、1 天前與今天是另一段。
      s.checkInRecords
        ..clear()
        ..[dayOf(s, 6)] = CheckInMethod.real
        ..[dayOf(s, 5)] = CheckInMethod.real
        ..[dayOf(s, 3)] = CheckInMethod.real
        ..[dayOf(s, 2)] = CheckInMethod.real
        ..[dayOf(s, 1)] = CheckInMethod.real;
      s.checkIn();
      expect(s.checkInStreak, 4,
          reason: '遇查無紀錄之日即停止 —— '
              '把被斷點切開的兩段相加會得出偏大的 6');
    });

    test('補在斷點上才會把兩段接起來', () {
      final s = AppState();
      s.checkInRecords
        ..clear()
        ..[dayOf(s, 6)] = CheckInMethod.real
        ..[dayOf(s, 5)] = CheckInMethod.real
        ..[dayOf(s, 3)] = CheckInMethod.real
        ..[dayOf(s, 2)] = CheckInMethod.real
        ..[dayOf(s, 1)] = CheckInMethod.real;
      s.checkIn();
      s.grantMakeupTickets(1);
      s.useMakeupTicket(
          s.makeupDaysInRange.firstWhere((d) => d.date == dayOf(s, 4)));
      expect(s.checkInStreak, 7, reason: '斷點補起來，7 天連成一段');
    });

    test('可重入：重複推算不改變結果', () {
      final s = AppState();
      s.checkIn();
      final a = s.simulateStreakAfterMakeup(
          s.makeupDaysInRange.firstWhere((d) => d.date == dayOf(s, 1)));
      final b = s.simulateStreakAfterMakeup(
          s.makeupDaysInRange.firstWhere((d) => d.date == dayOf(s, 1)));
      expect(a, b);
    });

    test('累計天數與歷史最長仍為單調遞增', () {
      final s = AppState();
      final total = s.checkInTotal;
      final d = s.makeupDaysInRange.firstWhere(s.canMakeUp);
      s.useMakeupTicket(d);
      expect(s.checkInTotal, total + 1, reason: '補簽當日計入累計天數');
      expect(s.checkInLongest, greaterThanOrEqualTo(s.checkInStreak));
    });
  });
}
