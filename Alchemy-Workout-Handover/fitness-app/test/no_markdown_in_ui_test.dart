import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// **畫面上的字串不可以帶 Markdown 語法。**
///
/// `Text` 不渲染 Markdown —— 寫 `**很重要**` 的結果是使用者**看到那四個
/// 星號**。2026-09-27 使用者截圖回報教官申請頁出現
/// 「**不會因此駁回你的申請。**」，全案掃過發現五處都是我寫的。
///
/// 會發生是因為我在註解裡習慣用 `**` 強調，寫字串時手就跟著打了。
/// 註解那樣寫沒問題（給人讀的原始碼），字串不行。
///
/// **這條守的是原始碼，不是行為** —— 所以用讀檔的方式驗，
/// 而不是把每一頁都畫出來找星號。
void main() {
  /// 不掃生成檔與資料來源：`platform_plans.g.dart` 的 `**` 來自
  /// 《健身計劃.csv》的原文（課表作者自己寫的強調），那是資料不是文案，
  /// 而且它顯示在課表詳情頁的「依據」裡 —— 原樣呈現才誠實。
  const skip = ['platform_plans.g.dart', 'platform_exercises.g.dart'];

  test('lib/ 底下的字串常值不含 **', () {
    final bad = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      if (skip.any(f.path.endsWith)) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        final t = line.trimLeft();
        // 註解裡愛怎麼強調都行 —— 那是給人讀原始碼用的。
        if (t.startsWith('//') || t.startsWith('///') || t.startsWith('*')) {
          continue;
        }
        for (final m in RegExp(r"'([^']*)'").allMatches(line)) {
          if (m.group(1)!.contains('**')) {
            bad.add('${f.path}:${i + 1}  ${m.group(1)}');
          }
        }
      }
    }
    expect(bad, isEmpty,
        reason: 'Text 不渲染 Markdown —— 使用者會直接看到那些星號');
  });
}
