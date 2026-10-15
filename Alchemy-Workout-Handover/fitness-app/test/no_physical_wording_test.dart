// 實體商品已移除（2026-10-15），使用者看得到的文字不能再提到出貨、收貨、物流。
//
// 尤其是隱私聲明與帳號刪除頁：原本寫著「已付款未出貨的實體訂單，其收貨資訊暫留至出貨完成」，
// 實體商品不存在之後，那是一個不實的保留承諾。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/registration.dart';

const _banned = ['實體商品', '實體訂單', '出貨', '收貨', '物流', '預扣'];

void main() {
  test('lib 裡的程式碼（非註解）沒有出貨、收貨、物流、預扣等字樣', () {
    final hits = <String>[];
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final l = lines[i];
        if (l.trimLeft().startsWith('//')) continue;
        for (final w in _banned) {
          if (l.contains(w)) hits.add('${f.path}:${i + 1} 「$w」');
        }
      }
    }
    expect(hits, isEmpty, reason: hits.join('\n'));
  });

  test('隱私聲明沒有提到實體訂單', () {
    final text = kTermsSections.map((e) => e.$2).join('\n');
    expect(text, isNot(contains('實體')));
    expect(text, isNot(contains('出貨')));
    expect(text, contains('檢舉或申訴'), reason: '前提：例外條款還在');
  });
}
