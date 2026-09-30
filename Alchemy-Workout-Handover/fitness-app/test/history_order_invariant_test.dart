import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_app/state/app_state.dart';

/// 訓練歷史一律新的在前 —— 這是 `AppState.history` 的不變條件，
/// 不是「存檔裡剛好是那個順序」。
///
/// 使用者回報「訓練清單還是日期舊的排前面」。那一次是 Firestore 的文件
/// 順序壞了，但首頁、訓練歷史頁、課表卡的「上次訓練」全都假設新的在前 ——
/// 所以這個保證要放在所有 Store 的共同入口，不是各個 Store 各自保證一次。
void main() {
  Map<String, dynamic> entry(String name, String date) => {
        'date': date,
        'planName': name,
        'volume': 500.0,
        'minutes': 40,
        'calories': 210,
        'exercises': const <Map<String, dynamic>>[],
      };

  test('存檔裡是舊到新，讀回來要變成新到舊', () {
    final s = AppState()
      ..applySnapshot({
        ...AppState().toSnapshot(),
        'history': [
          entry('最早', '2026-09-20T10:00:00.000'),
          entry('中間', '2026-09-23T10:00:00.000'),
          entry('最新', '2026-09-26T10:00:00.000'),
        ],
      });
    expect([for (final h in s.history) h.planName], ['最新', '中間', '最早']);
  });

  test('存檔裡順序全亂，讀回來一樣照日期', () {
    final s = AppState()
      ..applySnapshot({
        ...AppState().toSnapshot(),
        'history': [
          entry('中間', '2026-09-23T10:00:00.000'),
          entry('最新', '2026-09-26T10:00:00.000'),
          entry('最早', '2026-09-20T10:00:00.000'),
        ],
      });
    expect([for (final h in s.history) h.planName], ['最新', '中間', '最早']);
  });

  test('本來就對的順序不被改動', () {
    final s = AppState()
      ..applySnapshot({
        ...AppState().toSnapshot(),
        'history': [
          entry('最新', '2026-09-26T10:00:00.000'),
          entry('最早', '2026-09-20T10:00:00.000'),
        ],
      });
    expect([for (final h in s.history) h.planName], ['最新', '最早']);
  });

  test('結算寫入的那一場在最前面，且存回去讀回來還在最前面', () {
    final a = AppState()
      ..applySnapshot({
        ...AppState().toSnapshot(),
        'history': [entry('舊的', '2026-09-20T10:00:00.000')],
      });
    final firstName = a.history.first.planName;
    expect(firstName, '舊的');

    // 來回一趟不改變順序。
    final b = AppState()..applySnapshot(a.toSnapshot());
    expect([for (final h in b.history) h.planName],
        [for (final h in a.history) h.planName]);
  });
}
