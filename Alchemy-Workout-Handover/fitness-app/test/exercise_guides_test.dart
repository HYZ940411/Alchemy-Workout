import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/mock/platform_exercises.g.dart';

/// 動作教學文字的中譯品質檢查
///
/// 由來：527 筆教學文字原本是英文，動作詳情頁的「動作說明」直接顯示原文。
/// 逐批人工翻譯的風險是漏譯與貼錯欄位，兩者都不會讓程式壞掉，
/// 只會讓使用者看到英文或看到重複的段落 —— 故用測試把它們釘住。
void main() {
  final en = jsonDecode(File('assets/data/exercise_guides.json')
      .readAsStringSync()) as Map<String, dynamic>;
  final zh = jsonDecode(File('assets/data/exercise_guides.zh.json')
      .readAsStringSync()) as Map<String, dynamic>;

  String all(Map<String, dynamic> v) =>
      '${v['setup'] ?? ''}${v['howto'] ?? ''}${v['tips'] ?? ''}';

  test('每一筆英文教學都有對應的中譯，且沒有多出來的 ID', () {
    expect(zh.keys.toSet(), en.keys.toSet());
    expect(zh.length, 527);
  });

  test('準備工作與動作要領都不得為空', () {
    final empty = zh.entries
        .where((e) =>
            (e.value['setup'] as String).trim().isEmpty ||
            (e.value['howto'] as String).trim().isEmpty)
        .map((e) => e.key)
        .toList();
    expect(empty, isEmpty, reason: '這些動作的教學文字缺欄位：$empty');
  });

  test('沒有整段殘留的英文', () {
    // 三個連續英文字母即視為未譯。少數動作名詞（Hollow Hold、L-sit、Dead bug）
    // 是使用者原本就以英文書寫的專有名詞，逐一列為例外而非放寬規則。
    const allowed = {'p484', 'p485'};
    final latin = RegExp(r'[A-Za-z]{3,}');
    final left = zh.entries
        .where((e) => !allowed.contains(e.key) && latin.hasMatch(all(e.value)))
        .map((e) => e.key)
        .toList();
    expect(left, isEmpty, reason: '這些動作仍有英文未譯：$left');
  });

  test('動作要領不得只是複製準備工作', () {
    // 原始 CSV 有幾筆的 howto 欄位誤填成 setup 的內容，翻譯時已逐筆補寫。
    final dup = zh.entries
        .where((e) =>
            (e.value['setup'] as String).trim() ==
            (e.value['howto'] as String).trim())
        .map((e) => e.key)
        .toList();
    expect(dup, isEmpty, reason: '這些動作的動作要領與準備工作完全相同：$dup');
  });

  test('平台動作庫的每一筆動作都查得到教學文字', () {
    final missing =
        kPlatformExercises.where((e) => !zh.containsKey(e.id)).map((e) => e.id);
    expect(missing, isEmpty, reason: '這些動作沒有教學文字：$missing');
  });

  test('中譯後仍保有分行的條列結構', () {
    // 動作要領原本是編號清單，譯文若把換行吃掉，詳情頁會擠成一大段。
    final flattened = zh.entries.where((e) {
      final h = e.value['howto'] as String;
      return h.contains('2.') && !h.contains('\n');
    }).map((e) => e.key).toList();
    expect(flattened, isEmpty, reason: '這些動作的動作要領少了換行：$flattened');
  });
}
