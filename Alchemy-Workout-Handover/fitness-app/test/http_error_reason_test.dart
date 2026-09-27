import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fitness_app/data/http_error.dart';
import 'package:fitness_app/data/quality_score_http.dart';
import 'package:fitness_app/domain/training_quality.dart';

/// Worker 把真正的原因寫在回應內容裡，呼叫端只取狀態碼的話，
/// 開發者模式的診斷面板永遠只寫得出「502」——
/// 而 502 可能是模型忙線、配額用盡、或金鑰沒權限，三者處置完全不同。
///
/// **2026-09-27 我在 `ai_suggestion_http.dart` 修好這件事，
/// 卻沒有套到 `quality_score_http.dart`。** 使用者下一次截圖回報的就是
/// 「評分服務回應 502」，一樣什麼都看不出來 ——
/// 同一個決定寫在兩個地方，只做對一處。
void main() {
  http.Response json(int status, Object body) => http.Response.bytes(
        utf8.encode(body is String ? body : jsonEncode(body)),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  group('錯誤訊息要說得出原因', () {
    test('Worker 的 error 欄位帶出來', () {
      final r = httpFailureReason(
          '評分服務回應', json(502, {'error': '評分失敗：gemini 503 忙線'}));
      expect(r, contains('502'));
      expect(r, contains('忙線'));
    });

    test('不是 JSON 就用原文', () {
      expect(httpFailureReason('X', json(500, 'Internal Error')),
          contains('Internal Error'));
    });

    test('太長就截斷 —— 一頁 HTML 不該灌進一個欄位', () {
      final r = httpFailureReason('X', json(502, 'y' * 5000));
      expect(r.length, lessThan(400));
      expect(r, contains('…'));
    });

    test('沒有內容時只講狀態碼，不留一個孤零零的冒號', () {
      final r = httpFailureReason('X', json(503, ''));
      expect(r, 'X 503');
    });
  });

  // 這一條守的是「品質評分那一支真的有接上」——
  // 上面三條驗的是格式化函式本身，而缺陷發生在**沒有人呼叫它**。
  test('品質評分失敗時，原因帶得出來', () async {
    final src = HttpQualityScoreSource(
      endpoint: Uri.parse('https://example.invalid'),
      idToken: () async => 'token',
      client: MockClient((_) async =>
          json(502, {'error': '評分失敗：gemini 503 高負載'})),
    );
    try {
      await src.score(const <SessionSummary>[]);
      fail('該擲例外');
    } on HttpException catch (_) {
      fail('型別不該是 HttpException');
    } catch (e) {
      expect(e.toString(), contains('502'));
      expect(e.toString(), contains('高負載'),
          reason: '只剩狀態碼的話，開發者模式看不出是忙線還是金鑰壞掉');
    }
  });
}
