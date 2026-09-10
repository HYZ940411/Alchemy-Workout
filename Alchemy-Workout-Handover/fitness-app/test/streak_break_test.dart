import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/decay.dart';
import 'package:fitness_app/domain/rewards.dart';
import 'package:fitness_app/state/app_state.dart';

int noticesOf(AppState s, String event) =>
    s.notifications.where((n) => n.sourceEvent == event).length;

/// 假資料的簽到基準是「從未簽到」，會在建構當下就跨過門檻。
/// 這裡把它設成今天，讓每個測試從乾淨的起點推時鐘。
AppState freshCheckedIn() {
  final s = AppState();
  s.checkIn();
  return s;
}

void main() {
  // 日界落在「上次那一日的次日 04:00」，距現在 0–24 小時不等，
  // 故推進 N 天後距日界為 (N−1)×24 至 N×24 小時 —— 以此取穩定的門檻：
  // 1 天必 < 24；2 天必 ≥ 24；3 天必 ≥ 48；5 天必 ≥ 96。
  //
  // **上面這段只適用於「上次那一日＝今天」的計時器**（簽到組是這樣，
  // freshCheckedIn 當場簽到）。訓練組不是：假資料的最後一場在**昨天**，
  // 所以推進 N 天距日界是 N×24 至 (N+1)×24 小時，整組往後挪一天。
  // 照簽到組的天數寫，推進 1 天會落在 24–48 小時，剛好跨在 36 小時門檻上
  // —— 下午四點前跑會過，之後會失敗。這支曾經就是這樣的假陽性。

  group('連續訓練中斷', () {
    test('36 小時未訓練，連續天數歸零', () {
      final s = AppState();
      // 上次訓練在昨天：此刻距日界 0–24 小時，必未滿 36。
      expect(s.trainingStreakDays, greaterThan(0), reason: '未滿 36 小時不中斷');
      // 再推 2 天 → 距日界 48–72 小時，必已超過 36。
      s.advanceDemoClock(const Duration(days: 2));
      expect(s.trainingStreakDays, 0);
    });

    test('歸零即失去獎勵加成', () {
      final s = AppState();
      expect(streakBonus(s.trainingStreakDays), greaterThan(0));
      s.advanceDemoClock(const Duration(days: 3));
      expect(s.trainingStreakDays, 0);
      expect(streakBonus(s.trainingStreakDays), 0,
          reason: '加成由連續天數推導，天數歸零加成即為 0');
    });

    test('三道門檻各發一則通知，逐階補發', () {
      final s = AppState();
      // 門檻自「上次訓練日的日界」起算。假資料的最後一場是昨天，
      // 直接快轉會從第 24 小時之後才開始數 —— 這一條要測的是逐階，
      // 故先把基準對齊到今天。
      s.lastTrainedDate = businessDate(s.now);
      final warn = noticesOf(s, '中斷預告已發送');
      final broke = noticesOf(s, '連練中斷通知已發送');
      final decay = noticesOf(s, '退步預告已發送');

      s.advanceDemoClock(const Duration(days: 1));
      expect(noticesOf(s, '中斷預告已發送'), warn, reason: '未滿 24 小時');

      s.advanceDemoClock(const Duration(days: 1)); // 必 ≥ 24
      expect(noticesOf(s, '中斷預告已發送'), warn + 1);

      s.advanceDemoClock(const Duration(days: 1)); // 必 ≥ 48
      expect(noticesOf(s, '連練中斷通知已發送'), broke + 1);

      s.advanceDemoClock(const Duration(days: 2)); // 必 ≥ 96
      expect(noticesOf(s, '退步預告已發送'), decay + 1);
    });

    test('同一則預告不重複發', () {
      final s = AppState();
      s.advanceDemoClock(const Duration(days: 2));
      final warn = noticesOf(s, '中斷預告已發送');
      s.advanceDemoClock(const Duration(hours: 1));
      s.advanceDemoClock(const Duration(hours: 1));
      expect(noticesOf(s, '中斷預告已發送'), warn);
    });

    test('退步預告載明實際期限，不寫成「即將」', () {
      final s = AppState();
      s.advanceDemoClock(const Duration(days: 5));
      final n = s.notifications.lastWhere(
          (n) => n.sourceEvent == '退步預告已發送' && n.body.contains('未訓練'));
      expect(n.body, contains('10 天'));
    });

    test('恢復訓練後歸位，下一次中斷才重新發預告', () {
      final s = AppState();
      s.advanceDemoClock(const Duration(days: 3));
      expect(s.trainingStreakDays, 0);
      final warn = noticesOf(s, '中斷預告已發送');

      s.startWorkout(s.platformPlans.first);
      s.completeCurrentSet();
      s.finishWorkout(EndKind.completed);
      expect(s.trainingStreakDays, 1, reason: '中斷後自 1 起算');

      s.advanceDemoClock(const Duration(days: 2));
      expect(noticesOf(s, '中斷預告已發送'), warn + 1, reason: '這是新的一次中斷');
    });

    test('隔日訓練連續天數續計', () {
      final s = AppState();
      final before = s.trainingStreakDays;
      // 上次訓練在昨天，所以「隔日」就是今天 —— 不必推時鐘。
      // 原本這裡推了 1 天，那是上次訓練的**後天**，本來就該中斷。
      s.startWorkout(s.platformPlans.first);
      s.completeCurrentSet();
      s.finishWorkout(EndKind.completed);
      expect(s.trainingStreakDays, before + 1);
    });
  });

  group('連續簽到中斷', () {
    test('36 小時未簽到，連續天數歸零', () {
      final s = freshCheckedIn();
      final before = s.checkInStreak;
      expect(before, greaterThan(0));
      s.advanceDemoClock(const Duration(days: 1));
      expect(s.checkInStreak, before, reason: '未滿 36 小時不中斷');
      s.advanceDemoClock(const Duration(days: 2));
      expect(s.checkInStreak, 0);
    });

    test('24 小時發連簽中斷預告，48 小時發補簽提醒', () {
      final s = freshCheckedIn();
      final warn = noticesOf(s, '連簽中斷預告已發送');
      final makeup = noticesOf(s, '補簽提醒已發送');

      s.advanceDemoClock(const Duration(days: 2)); // ≥24、<48
      expect(noticesOf(s, '連簽中斷預告已發送'), warn + 1);
      expect(noticesOf(s, '補簽提醒已發送'), makeup, reason: '還沒到 48 小時');

      s.advanceDemoClock(const Duration(days: 1)); // ≥48
      expect(noticesOf(s, '補簽提醒已發送'), makeup + 1);
    });

    test('中斷後再簽，自 1 起算', () {
      final s = freshCheckedIn();
      s.advanceDemoClock(const Duration(days: 3));
      expect(s.checkInStreak, 0);
      s.checkIn();
      expect(s.checkInStreak, 1);
    });

    test('隔日簽到連續天數續計', () {
      final s = freshCheckedIn();
      final before = s.checkInStreak;
      s.advanceDemoClock(const Duration(days: 1));
      expect(s.checkedInToday, isFalse);
      s.checkIn();
      expect(s.checkInStreak, before + 1);
    });

    test('累計天數與歷史最長皆為單調遞增，不隨中斷減少', () {
      final s = freshCheckedIn();
      final total = s.checkInTotal;
      final longest = s.checkInLongest;
      s.advanceDemoClock(const Duration(days: 5));
      expect(s.checkInStreak, 0);
      expect(s.checkInTotal, total);
      expect(s.checkInLongest, longest);
    });

    test('從未簽到者自註冊日的日界起算，不是永遠顯示舊值', () {
      final s = AppState();
      // 假資料本來就有 9 天簽到紀錄；要測「從未簽到」得先把紀錄清掉。
      // 上次簽到日期與連續天數都由紀錄推導，清空紀錄兩者才會一起歸零。
      s.checkInRecords.clear();
      expect(s.lastCheckInDate, isNull);
      expect(s.checkInStreak, 0,
          reason: '一次都沒簽過，不該顯示著一個連續天數');
    });

    test('上次簽到日期就是紀錄裡最晚的那一天', () {
      final s = AppState();
      expect(s.checkInRecords, isNotEmpty, reason: '前提：假資料有簽到紀錄');
      final latest =
          s.checkInRecords.keys.reduce((a, b) => a.isAfter(b) ? a : b);
      expect(s.lastCheckInDate, latest,
          reason: '一邊說「從來沒簽到過」、另一邊畫出 9 個已簽到的格子，不能並存');
    });
  });

  group('兩邊共用同一條續計規則', () {
    test('streakContinues 以日界起算滿 36 小時為界', () {
      final last = DateTime(2026, 1, 1, 20);
      // 日界為 1/2 04:00；+36h ＝ 1/3 16:00。
      expect(streakContinues(last, DateTime(2026, 1, 2, 23)), isTrue);
      expect(streakContinues(last, DateTime(2026, 1, 3, 15)), isTrue);
      expect(streakContinues(last, DateTime(2026, 1, 3, 17)), isFalse);
    });
  });
}
