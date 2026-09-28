import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fitness_app/data/ai_suggestion.dart';
import 'package:fitness_app/data/ai_suggestion_http.dart';
import 'package:fitness_app/domain/ai_adjust.dart';
import 'package:fitness_app/domain/models.dart';
import 'package:fitness_app/state/app_state.dart';

/// 診斷用的兩件事。
///
/// 使用者回報「P61 沒找到在哪看」與「P60 還是被擋」——
/// 而我建的那個面板**永遠只寫得出「AI 服務回應 502」**，
/// 因為真正的原因（Worker 放在回應內容裡）在 HTTP 那一層就被丟掉了。
void main() {
  HttpAiSuggestionSource sourceThat(
    int status,
    String body,
  ) =>
      HttpAiSuggestionSource(
        endpoint: Uri.parse('https://example.invalid'),
        idToken: () async => 'token',
        client: MockClient((_) async => http.Response.bytes(
              utf8.encode(body),
              status,
              headers: {'content-type': 'application/json; charset=utf-8'},
            )),
      );

  group('錯誤要說得出原因，不能只剩狀態碼', () {
    test('Worker 的 error 欄位要被帶出來', () async {
      final src = sourceThat(
          502, jsonEncode({'error': '分類失敗：gemini 429: 配額用盡'}));
      await expectLater(
        src.classify('今天時間不夠'),
        throwsA(predicate((e) =>
            e.toString().contains('502') &&
            e.toString().contains('配額用盡'))),
      );
    });

    test('不是 JSON 的回應就用原文', () async {
      final src = sourceThat(500, 'Internal Error');
      await expectLater(
        src.classify('今天時間不夠'),
        throwsA(predicate((e) => e.toString().contains('Internal Error'))),
      );
    });

    test('太長的內容截斷 —— 一頁 HTML 不該灌進一個欄位', () async {
      final src = sourceThat(502, 'x' * 5000);
      try {
        await src.classify('a');
        fail('該擲例外');
      } catch (e) {
        expect(e.toString().length, lessThan(400));
        expect(e.toString(), contains('…'));
      }
    });
  });

  group('一鍵診斷', () {
    test('沒接 AI 時說得出來，不是靜靜地什麼都沒有', () async {
      final s = AppState();
      expect(await s.probeAiClassify(), contains('沒有接上'));
    });

    test('成功時回傳判到的方向', () async {
      final s = AppState()..aiSource = _Fake(RemoteIntent(AdjustIntent.trim));
      final r = await s.runAiProbe();
      expect(r, contains(adjustIntentNames[AdjustIntent.trim]!));
      expect(s.aiProbeResult, r, reason: '結果要留在畫面上看得到');
    });

    test('判不出來也是一種結果，不是失敗', () async {
      final s = AppState()..aiSource = _Fake(const RemoteIntent(null));
      expect(await s.runAiProbe(), contains('判不出來'));
    });

    test('失敗時把原因整段帶出來', () async {
      final s = AppState()..aiSource = _Fake(null, err: '502：配額用盡');
      final r = await s.runAiProbe();
      expect(r, contains('失敗'));
      expect(r, contains('配額用盡'));
    });
  });
}

class _Fake implements AiSuggestionSource {
  /// 這幾份假件都不測自動優化 —— **擲例外而不是回空值**：
  /// 回空值會讓「沒被呼叫到」與「回了個空的」長得一樣。
  @override
  Future<RemoteAutoAdjust> suggestAuto({
    required List<PlanExercise> exercises,
    AdjustContext? context,
    Map<String, List<Exercise>> candidates = const {},
  }) =>
      throw UnimplementedError('這個假件不支援自動優化');

  final RemoteIntent? reply;
  final String? err;
  _Fake(this.reply, {this.err});

  @override
  Future<RemoteIntent> classify(String say) async {
    if (err != null) throw Exception(err);
    return reply!;
  }

  @override
  Future<RemoteSuggestion> suggest({
    required List exercises,
    required AdjustIntent intent,
    int onlyFrom = 0,
    String? note,
    Object? context,
    Map<String, List> candidates = const {},
  }) =>
      throw UnimplementedError();
}
