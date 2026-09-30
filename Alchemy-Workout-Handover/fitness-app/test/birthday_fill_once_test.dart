import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_app/domain/clock.dart';
import 'package:fitness_app/domain/registration.dart';
import 'package:fitness_app/screens/me/settings_screen.dart';
import 'package:fitness_app/state/app_state.dart';

/// 生日：**沒填的可以補，填了就鎖住**（2026-09-26 使用者裁決 B）。
///
/// 規格明訂生日唯讀（它決定年齡係數，改動會使既有點數失去計算基準，
/// 如需更正屬客服範疇），但沒設想到「從來沒存過」這種狀況 ——
/// 2026-09-26 之前註冊問卷問了生日卻沒有任何地方存它，
/// 那些帳號的生日是空的，唯讀意味著永遠填不進去。
///
/// 「補一個從來沒有的值」不會讓任何點數失去基準，因為在它之前沒有基準。
void main() {
  tearDown(resetAppClock);

  // 相對於「今天」算，不寫死日期 —— 寫死的話這份測試明年會自己紅。
  final today = DateTime(appNow().year, appNow().month, appNow().day);
  DateTime yearsAgo(int y, {int days = 0}) =>
      DateTime(today.year - y, today.month, today.day)
          .add(Duration(days: days));

  group('補填', () {
    test('原本沒有就填得進去', () {
      final s = AppState()..birthday = null;
      final d = yearsAgo(25);
      expect(s.fillBirthday(d), isNull);
      expect(s.birthday, d);
    });

    test('只留年月日，不帶時分秒', () {
      final s = AppState()..birthday = null;
      final d = yearsAgo(25);
      s.fillBirthday(DateTime(d.year, d.month, d.day, 14, 30, 59));
      expect(s.birthday, d);
    });

    test('**填了就不能再改** —— 那才是規格鎖住的那件事', () {
      final s = AppState()..birthday = null;
      final d = yearsAgo(25);
      s.fillBirthday(d);
      final err = s.fillBirthday(yearsAgo(40));
      expect(err, isNotNull);
      expect(s.birthday, d, reason: '原值不可被覆蓋');
    });
  });

  group('年齡門檻與註冊流程同一道', () {
    test('未滿 13 歲不給填 —— 差一天也算沒滿', () {
      final s = AppState()..birthday = null;
      expect(s.fillBirthday(yearsAgo(kMinAge, days: 1)), contains('$kMinAge'));
      expect(s.birthday, isNull);
    });

    test('剛好滿 13 歲的當天可以', () {
      final s = AppState()..birthday = null;
      expect(s.fillBirthday(yearsAgo(kMinAge)), isNull);
    });

    test('未來的日期不給填', () {
      final s = AppState()..birthday = null;
      expect(s.fillBirthday(today.add(const Duration(days: 1))),
          contains('未來'));
      expect(s.birthday, isNull);
    });

    test('超過 120 歲不給填', () {
      final s = AppState()..birthday = null;
      expect(s.fillBirthday(yearsAgo(121)), isNotNull);
      expect(s.birthday, isNull);
    });
  });

  group('設定頁那一列', () {
    Future<void> pump(WidgetTester t, AppState s) async {
      await t.pumpWidget(AppScope(
        state: s,
        child: const MaterialApp(home: SettingsScreen()),
      ));
      await t.pumpAndSettle();
    }

    testWidgets('沒填時說得出「可補填」，而不是只掛一把鎖', (t) async {
      final s = AppState()..birthday = null;
      await pump(t, s);
      expect(find.text('未填寫（可補填）'), findsOneWidget);
    });

    testWidgets('填了之後變成唯讀，點下去說得出理由', (t) async {
      final s = AppState()..birthday = DateTime(2001, 7, 3);
      await pump(t, s);
      expect(find.text('2001 / 07 / 03'), findsOneWidget);
      await t.tap(find.text('2001 / 07 / 03'));
      await t.pumpAndSettle();
      expect(find.textContaining('年齡係數'), findsOneWidget);
      expect(s.birthday, DateTime(2001, 7, 3), reason: '點了不該改掉它');
    });
  });

  test('補填的生日要進存檔', () {
    final a = AppState()..birthday = null;
    a.fillBirthday(yearsAgo(25));
    final b = AppState()..applySnapshot(a.toSnapshot());
    expect(b.birthday, yearsAgo(25));
  });
}
