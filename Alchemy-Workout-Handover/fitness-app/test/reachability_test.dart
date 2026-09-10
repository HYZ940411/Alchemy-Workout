import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// 可達性檢查
///
/// 由來：2026-08-26 改成五格導覽時，「六維能力值雷達圖」與「每日簽到／每日任務」
/// 兩個畫面被從導覽拿掉卻沒接到任何地方，變成進不去的死畫面。
/// 當時的煙霧測試只檢查「我列出的入口」，因此照樣全過 ——
/// 它沒有能力發現「有東西不在清單上」。本測試補的正是這個缺口。
void main() {
  test('每個 Screen 類別都至少被別的檔案引用一次', () {
    final lib = Directory('lib');
    final files = lib
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();

    final sources = {for (final f in files) f.path: f.readAsStringSync()};

    // 收集所有 public 的 *Screen / *Shell 類別
    final declared = <String, String>{}; // 類別名 -> 宣告檔
    final re = RegExp(r'^class ([A-Z]\w*(?:Screen|Shell))\b', multiLine: true);
    sources.forEach((path, src) {
      for (final m in re.allMatches(src)) {
        declared[m.group(1)!] = path;
      }
    });

    expect(declared.length, greaterThan(20),
        reason: '應該掃到二十幾個畫面，掃不到表示這個測試本身壞了');

    // 一個類別「被引用」＝ 在它自己的程式區塊之外出現過。
    // 同檔中由另一個類別引用（例如 ConversationsScreen 開啟 ChatScreen）也算。
    String stripOwnBody(String src, String cls) {
      final start = src.indexOf(RegExp('^class $cls\\b', multiLine: true));
      if (start < 0) return src;
      final after = src.indexOf(RegExp(r'^class \w', multiLine: true), start + 1);
      return src.substring(0, start) + (after < 0 ? '' : src.substring(after));
    }

    final orphans = <String>[];
    declared.forEach((cls, declPath) {
      final referenced = sources.entries.any((e) {
        final body =
            e.key == declPath ? stripOwnBody(e.value, cls) : e.value;
        return RegExp('\\b$cls\\s*\\(').hasMatch(body);
      });
      if (!referenced) orphans.add('$cls  ($declPath)');
    });

    expect(orphans, isEmpty,
        reason: '以下畫面沒有任何入口，使用者進不去：\n  ${orphans.join('\n  ')}');
  });

  test('底部導覽的五格都有對應畫面', () {
    final shell = File('lib/screens/home_shell.dart').readAsStringSync();
    for (final cls in [
      'HomeScreen',
      'SocialShell',
      'PlanSelectScreen',
      'ShopHubScreen',
      'MoreScreen',
    ]) {
      expect(shell, contains(cls), reason: '五格架構缺少 $cls');
    }
  });
}
