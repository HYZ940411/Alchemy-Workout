// 前台的文字不講規格術語（`[QA-02m]`）。
//
// 使用者回報「App 內的補充文字要移除」，但事後也想不起是哪幾句 ——
// 合理，因為那不是某一句特別糟，而是**整個 App 有一層對自己的說明**。
// 這個專案是照事件風暴建的，於是規格的詞彙一路漏到畫面上：
// 每日任務寫「判定來源：訓練已完成」、「我的」頁寫「兩份 Read Model」、
// 教官申請頁解釋「值域刻意不含六大肌群」。
//
// 那些對讀規格的人是資訊，對使用者是雜訊 —— 而且會讓人以為自己漏懂了什麼。
//
// **這兩條測試是 lint，不是行為測試。** 它們掃前台畫面的字串常值，
// 命中就紅。後台與開發者模式的畫面不掃：那些讀者本來就是我們自己，
// 「Precondition」在那裡是正確的用詞。
//
// 2026-09-19 補第二條：使用者圈出新手任務頁的
// 「系統也不驗證你實際做了幾下 —— 新手任務是引導，不是考核」。
// 那是同一種病的另一種型態 —— 不是用錯詞，是講了不該對使用者講的事。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 不該出現在前台文字裡的詞。
const List<String> _jargon = [
  'Aggregate',
  'Precondition',
  'Postcondition',
  'Read Model',
  '事件風暴',
  '不變條件',
  '狀態機',
  '判定來源',
  '值域',
  '本 App 沒有後端',
];

/// 不該對使用者說的話。
///
/// 與 [_jargon] 是同一種病的兩種型態：那邊是「用了規格的詞」，
/// 這邊是「講了系統內部的事」。兩類都不是某一句特別糟，
/// 而是寫的人跟讀的人搞混了。
///
/// **「系統不驗證你」這類話尤其不能留。** 它一方面告訴使用者
/// 敷衍也沒關係，一方面把我們沒做查核這件事講出去 ——
/// 使用者要知道的是「該做什麼」，不是「我們檢查到什麼程度」。
const List<String> _internals = [
  '不驗證',
  '不會驗證',
  '不檢查',
  '不是考核',
  '假資料',
  '真實系統',
];

/// 讀者是我們自己的畫面 —— 後台與開發者模式底下的示範頁。
const _internal = [
  'lib/screens/admin/',
  'lib/screens/design/',
];

/// 回傳 [words] 裡第一個出現在 [s] 中的詞，都沒有就回 null。
String? _firstIn(String s, List<String> words) {
  for (final w in words) {
    if (s.contains(w)) return w;
  }
  return null;
}

/// 掃前台畫面的字串常值，交給 [check] 判斷每一句。
List<String> _scanFrontStage(String? Function(String) check) {
  final lit = RegExp(r"'([^']{4,})'");
  final offences = <String>[];

  for (final f in Directory('lib/screens')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))) {
    final rel = f.path.replaceAll(r'\', '/');
    if (_internal.any(rel.contains)) continue;

    final lines = f.readAsStringSync().split('\n');
    for (var i = 0; i < lines.length; i++) {
      // 註解不算 —— 程式碼註解本來就該講內部的事。
      if (lines[i].trimLeft().startsWith('//')) continue;
      for (final m in lit.allMatches(lines[i])) {
        final hit = check(m.group(1)!);
        if (hit != null) offences.add('$rel:${i + 1}　「$hit」　${m.group(1)}');
      }
    }
  }
  return offences;
}

void main() {
  test('前台畫面的字串不含規格術語', () {
    final offences = _scanFrontStage((s) => _firstIn(s, _jargon));

    expect(
      offences,
      isEmpty,
      reason: '前台文字出現規格術語，改寫成使用者看得懂的說法：\n'
          '${offences.join('\n')}',
    );
  });

  // 使用者把「新手任務」頁那段圈起來回報：
  // 「目標次數由範本給定，不可調整；系統也不驗證你實際做了幾下 ——
  //   新手任務是引導，不是考核。勾錯了可以取消。」
  //
  // 那一段在講我們為什麼這樣設計，而不是他該做什麼。同一頁底下已經有
  // 「做完後勾選上面那一組，才能按完成。」—— 那句才是他需要的。
  test('前台畫面不對使用者講系統內部的事', () {
    final offences = _scanFrontStage((s) => _firstIn(s, _internals));

    expect(
      offences,
      isEmpty,
      reason: '前台文字講了系統內部的事，刪掉或改寫成使用者要做的事：\n'
          '${offences.join('\n')}',
    );
  });
}
