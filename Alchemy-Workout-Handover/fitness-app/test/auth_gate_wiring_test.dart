// 接外部服務的指派不得依賴其他網路呼叫是否成功。
//
// `aiSource` 原本被放在 `AuthGate._syncProfile()` 裡面，而那個函式有
// **六個接連的網路 await**（發布公開檔案、讀別人的、貼文、私訊、團隊、
// 師徒），整段包在 `try/catch` 裡。任何一個失敗，catch 吞掉，
// `aiSource` 就永遠不會被設。
//
// 而 `AppState.aiProduceSuggestionAsync()` 看到空值會**靜靜地**退回
// 端內規則，不留任何痕跡。線上症狀是：
//   · AI 建議沒有理由（規則產不出理由）
//   · 「替換做不了的動作」回「沒有可調的空間」（規則不換動作）
//   · Cloudflare Worker 的 log 完全沒有流量
// 三個症狀指向三個不同方向，查到第三層才發現原因在這裡。
//
// **這條測試是一道 lint。** 它讀原始碼，不執行任何東西 ——
// 要跑真的 `AuthGate` 得先有 `AuthService`，而那個包著 FirebaseAuth。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 取出 `_syncProfile` 的函式本體。
String _syncProfileBody(String src) {
  final start = src.indexOf('Future<void> _syncProfile(');
  expect(start, isNot(-1), reason: '函式改名了，這條測試要跟著更新');
  var depth = 0;
  var i = src.indexOf('{', start);
  final from = i;
  for (; i < src.length; i++) {
    if (src[i] == '{') depth++;
    if (src[i] == '}') {
      depth--;
      if (depth == 0) return src.substring(from, i + 1);
    }
  }
  fail('找不到 _syncProfile 的結尾');
}

void main() {
  final src = File('lib/screens/auth_gate.dart').readAsStringSync();

  test('aiSource 在 initState 就接上，不等任何網路呼叫', () {
    final start = src.indexOf('void initState()');
    final end = src.indexOf('void _onAuthChanged');
    expect(start, isNot(-1));
    expect(
      src.substring(start, end),
      contains('state.aiSource = widget.aiSource'),
      reason: 'aiSource 不需要 uid、也不必載入任何東西，沒有理由延後',
    );
  });

  test('aiSource 不得埋回 _syncProfile 的 try 區塊', () {
    expect(
      _syncProfileBody(src),
      isNot(contains('aiSource')),
      reason: '那裡面任何一個 await 失敗，catch 就會把這個指派一起吞掉',
    );
  });
}
