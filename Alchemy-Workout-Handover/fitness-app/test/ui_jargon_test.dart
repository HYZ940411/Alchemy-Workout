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
// **這條測試是一道 lint，不是行為測試。** 它掃前台畫面的字串常值，
// 命中術語就紅。後台與開發者模式的畫面不掃：那些讀者本來就是我們自己，
// 「Precondition」在那裡是正確的用詞。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 不該出現在前台文字裡的詞。
const _jargon = [
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

/// 讀者是我們自己的畫面 —— 後台與開發者模式底下的示範頁。
const _internal = [
  'lib/screens/admin/',
  'lib/screens/design/',
];

void main() {
  test('前台畫面的字串不含規格術語', () {
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
        final line = lines[i];
        final t = line.trimLeft();
        // 註解不算 —— 程式碼註解本來就該用規格的詞彙。
        if (t.startsWith('//')) continue;
        for (final m in lit.allMatches(line)) {
          final s = m.group(1)!;
          for (final j in _jargon) {
            if (s.contains(j)) {
              offences.add('$rel:${i + 1}　「$j」　$s');
            }
          }
        }
      }
    }

    expect(
      offences,
      isEmpty,
      reason: '前台文字出現規格術語，改寫成使用者看得懂的說法：\n'
          '${offences.join('\n')}',
    );
  });
}
