// 登入時載入的東西，重新整理時也要載 —— 反過來也是。
//
// ## 為什麼需要這道檢查
//
// 跨使用者資料有**兩條載入路徑**：
//
//   · `AuthGate._syncProfile()` —— 登入時跑一次
//   · `AppState.refreshInbound()` —— 下拉重新整理與即時訂閱訊號時跑
//
// 兩條各自寫了一份，於是**修了其中一條不會影響另一條**。
//
// 2026-09-29 就踩到：拜師申請讀不回來，我把 `applyMySentMentorRequests`
// 加進 `refreshInbound`，測試全綠、使用者重測還是壞的 ——
// 因為登入走的是 `AuthGate` 那一條，它有自己的「師徒申請」步驟。
//
// ## 這道檢查驗什麼
//
// `refreshInbound` 會做的每一件事，`AuthGate` 都要做。
// 反過來不成立是正常的：登入時還要載平台資料、公開檔案、管理員身分
// 那些「只在登入時需要一次」的東西。
//
// **這是文字比對，不是行為驗證** —— 它抓得到「漏接」，
// 抓不到「接了但接錯」。與 `data_source_wiring_test` 同一個層級的工具。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  /// 從一段程式碼裡抓出所有 `applyXxx(` 與 `loadXxx(` 的呼叫。
  ///
  /// **`load` 是 2026-09-29 補的。** 原本只看 `apply`，於是
  /// `loadMyApprenticeSide()` 漏接在 `AuthGate` 那一條時它沒抓到 ——
  /// 而那正是這道檢查存在的理由（教官的回答到不了學徒手上）。
  Set<String> loadCalls(String src) =>
      RegExp(r'\b((?:apply|load)[A-Z]\w*)\(')
          .allMatches(src)
          .map((m) => m.group(1)!)
          // `loadMentorSideOf` 由 `loadMentorSide` 內部呼叫，
          // 不需要 `AuthGate` 自己再叫一次。
          .where((n) => n != 'loadMentorSideOf')
          .toSet();

  test('refreshInbound 做的每一件事，登入時也要做', () {
    final state = File('lib/state/app_state.dart').readAsStringSync();
    final gate = File('lib/screens/auth_gate.dart').readAsStringSync();

    final start = state.indexOf('Future<void> refreshInbound() async {');
    expect(start, greaterThan(0), reason: '找不到 refreshInbound —— 這道檢查失效了');
    // 抓到下一個同縮排的方法為止。
    final rest = state.substring(start);
    final end = rest.indexOf('\n  // ────');
    final body = end > 0 ? rest.substring(0, end) : rest.substring(0, 7000);

    final onRefresh = loadCalls(body);
    expect(onRefresh, isNotEmpty, reason: '抓不到任何呼叫 —— 檢查本身壞了');

    final onLogin = loadCalls(gate);
    final missing = onRefresh.difference(onLogin);

    expect(missing, isEmpty,
        reason: '這幾件事重新整理時會做、登入時不會：$missing\n'
            '兩條路徑各寫一份的代價就是這個 —— '
            '修了一條，另一條還是舊的，而測試會是綠的。');
  });
}
