// 外部 AI 的邊界（`[BE-08]`）。
//
// 規格把 LLM 放在軟體邊界**之外**，只規範呼叫時點、扣點、失敗退點與
// 「AI 僅產出建議、不套用」。那四件事在接上外部 API 之前就已經做好了，
// 所以這個檔案測的是**邊界本身**：送出去的形狀、收回來的還原、
// 以及失敗時有沒有走既有的退點流程。
//
// **不接外部 API 時行為必須與接上之前一模一樣** —— 那是既有一千多條
// 測試的前提，這裡第一組就釘住它。

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fitness_app/data/ai_suggestion.dart';
import 'package:fitness_app/data/ai_suggestion_http.dart';
import 'package:fitness_app/domain/ability.dart';
import 'package:fitness_app/domain/ai_adjust.dart';
import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/domain/models.dart';
import 'package:fitness_app/state/app_state.dart';

/// 回傳預先寫好的東西，或是擲出例外。
class _FakeSource implements AiSuggestionSource {
  final Map<String, dynamic>? reply;
  final bool throws;
  Map<String, dynamic>? sent;
  _FakeSource({this.reply, this.throws = false});

  @override
  Future<RemoteSuggestion> suggest({
    required List<PlanExercise> exercises,
    required AdjustIntent intent,
    int onlyFrom = 0,
    String? note,
  }) async {
    sent = {
      'intent': intent.name,
      'note': ?note,
      ...encodePlan(exercises, onlyFrom),
    };
    if (throws) throw Exception('逾時');
    final data = reply!;
    return RemoteSuggestion(
      originOf(data),
      decodeSuggestion(data, exercises, intent, onlyFrom),
    );
  }
}

List<PlanExercise> _plan() => [
      PlanExercise(
        exercise: const Exercise(
            id: 'e1', name: '槓鈴臥推', dim: Dim.chest,
            relativeIntensity: 1.0, equipment: '槓鈴'),
        planned: const [PlannedSet(60, 8), PlannedSet(60, 8)],
      ),
      PlanExercise(
        exercise: const Exercise(
            id: 'e2', name: '徒手深蹲', dim: Dim.legs,
            relativeIntensity: 0.6, isBodyweight: true),
        planned: const [PlannedSet(0, 12)],
      ),
    ];

void main() {
  group('送出去的形狀', () {
    test('只送動作名稱與逐組目標 —— 不送使用者是誰', () {
      final got = encodePlan(_plan(), 0);
      expect(got, {
        'exercises': [
          {
            'name': '槓鈴臥推',
            'sets': [
              {'weight': 60.0, 'reps': 8},
              {'weight': 60.0, 'reps': 8},
            ],
          },
          {
            'name': '徒手深蹲',
            'sets': [
              {'weight': 0.0, 'reps': 12},
            ],
          },
        ],
      });
      // 這是刻意的：調整建議用不到身分與身體資料，送了只是擴大外洩面。
      expect(got.toString(), isNot(contains('uid')));
      expect(got.toString(), isNot(contains('bodyweight')));
    });

    test('onlyFrom 之前的動作不送上去', () {
      final got = encodePlan(_plan(), 1);
      expect((got['exercises'] as List).length, 1);
      expect((got['exercises'] as List).first['name'], '徒手深蹲');
    });
  });

  group('收回來的還原', () {
    test('索引要加回 onlyFrom —— 否則會套到已經練完的動作上', () {
      final plan = _plan();
      // 伺服器收到的是切片，所以它回的 index 0 指的是原始課表的 1。
      final s = decodeSuggestion({
        'changes': [
          {
            'index': 0,
            'name': '徒手深蹲',
            'after': [
              {'weight': 0, 'reps': 15},
            ],
          },
        ],
      }, plan, AdjustIntent.easier, 1);

      expect(s.changes.single.exerciseIndex, 1);
      expect(s.changes.single.exerciseName, '徒手深蹲');
      expect(s.changes.single.after.single.targetReps, 15);
    });

    test('名稱對不上就丟掉 —— 這是伺服器之外的第二道', () {
      final s = decodeSuggestion({
        'changes': [
          {
            'index': 0,
            'name': '這個動作不在課表裡',
            'after': [
              {'weight': 50, 'reps': 10},
            ],
          },
        ],
      }, _plan(), AdjustIntent.easier, 0);
      expect(s.changes, isEmpty);
    });

    test('索引超出範圍就丟掉', () {
      final s = decodeSuggestion({
        'changes': [
          {
            'index': 99,
            'name': '槓鈴臥推',
            'after': [
              {'weight': 50, 'reps': 10},
            ],
          },
        ],
      }, _plan(), AdjustIntent.easier, 0);
      expect(s.changes, isEmpty);
    });

    test('before 取的是課表現值，不是伺服器說的', () {
      final s = decodeSuggestion({
        'changes': [
          {
            'index': 0,
            'name': '槓鈴臥推',
            'after': [
              {'weight': 55, 'reps': 10},
            ],
          },
        ],
      }, _plan(), AdjustIntent.easier, 0);
      expect(s.changes.single.before.first.targetWeight, 60);
    });

    test('分得出是模型產的還是規則產的', () {
      expect(originOf({'source': 'gemini'}), SuggestionOrigin.gemini);
      expect(originOf({'source': 'rule'}), SuggestionOrigin.rule);
      expect(originOf(const {}), SuggestionOrigin.rule, reason: '認不出來就當規則');
    });
  });

  group('接上 AppState', () {
    /// 照 `ai_adjust_test.dart` 的建法：開一場訓練，走到「等建議」那一步。
    AppState upToAnalyzing(AiSuggestionSource? source) {
      final s = AppState()..aiSource = source;
      s.startWorkout(s.platformPlans.firstWhere((p) => p.exercises.isNotEmpty));
      s.aiRequest(AiSource.beforeTraining, '今天狀況不太好');
      s.aiConfirmDemand(AiSource.beforeTraining, '整體降強度');
      return s;
    }

    test('不注入就走端內規則 —— 既有測試的前提', () async {
      final s = upToAnalyzing(null);
      await s.aiProduceSuggestionAsync(AiSource.beforeTraining);
      expect(s.aiStage[AiSource.beforeTraining], AiStage.proposed);
      expect(s.aiLastOrigin, isNull, reason: '沒接外部 API 就沒有來源可言');
      expect(s.aiSuggestion[AiSource.beforeTraining], isNotNull);
    });

    test('注入之後，送出去的是使用者眼前那份課表', () async {
      final fake = _FakeSource(reply: const {'source': 'gemini', 'changes': []});
      final s = upToAnalyzing(fake);
      final names = s.session!.exercises.map((e) => e.exercise.name).toList();

      await s.aiProduceSuggestionAsync(AiSource.beforeTraining);

      expect(fake.sent!['intent'], 'easier');
      final sent = (fake.sent!['exercises'] as List)
          .map((e) => (e as Map)['name']).toList();
      expect(sent, names, reason: '送的必須是他眼前這一份，不是別的課表');
    });

    test('看不出意圖時不猜、不扣點、不產建議', () async {
      // 使用者打「早安」也換來一份降強度的課表並被扣一點 —— 他從頭到尾
      // 沒要求調整強度。猜錯的代價不是保守與否，是做了他沒要求的事還收了錢。
      final fake = _FakeSource(reply: const {'source': 'gemini', 'changes': []});
      final s = AppState()..aiSource = fake;
      s.startWorkout(s.platformPlans.firstWhere((p) => p.exercises.isNotEmpty));
      final before = s.aiTotal;
      s.aiRequest(AiSource.beforeTraining, '早安');
      s.aiConfirmDemand(AiSource.beforeTraining, '我早餐吃蘑菇麵');

      expect(s.aiStage[AiSource.beforeTraining], AiStage.clarifying,
          reason: '停在追問，不往下走');
      expect(s.aiIntent[AiSource.beforeTraining], isNull);
      expect(s.aiTotal, before, reason: '未扣點');
      expect(fake.sent, isNull, reason: '根本不該呼叫模型');
      expect(s.aiConversations[AiSource.beforeTraining]!.last.text,
          contains('看不出你想往哪個方向調'));
    });

    test('再問一次答得出來就繼續', () async {
      final fake = _FakeSource(reply: const {'source': 'gemini', 'changes': []});
      final s = AppState()..aiSource = fake;
      s.startWorkout(s.platformPlans.firstWhere((p) => p.exercises.isNotEmpty));
      s.aiRequest(AiSource.beforeTraining, '早安');
      s.aiConfirmDemand(AiSource.beforeTraining, '我早餐吃蘑菇麵');
      s.aiConfirmDemand(AiSource.beforeTraining, '減少組數');

      expect(s.aiStage[AiSource.beforeTraining], AiStage.analyzing);
      expect(s.aiIntent[AiSource.beforeTraining], AdjustIntent.trim);
    });

    test('parseIntent：三個方向都要有寬鬆比對', () {
      // easier 原本是預設值，所以一條寬鬆比對都沒有。改掉預設之後
      // 若不補上，「想降強度」這種最自然的說法反而認不出來。
      expect(AppState.parseIntent('整體降強度'), AdjustIntent.easier);
      expect(AppState.parseIntent('今天肩膀緊，想降強度'), AdjustIntent.easier);
      expect(AppState.parseIntent('今天很累'), AdjustIntent.easier);
      expect(AppState.parseIntent('想加重一點'), AdjustIntent.harder);
      expect(AppState.parseIntent('減少組數'), AdjustIntent.trim);
      expect(AppState.parseIntent('組數少一點'), AdjustIntent.trim);
    });

    test('parseIntent：曖昧與無關的一律回空值', () {
      expect(AppState.parseIntent('早安'), isNull);
      expect(AppState.parseIntent('我早餐吃蘑菇麵'), isNull);
      expect(AppState.parseIntent(''), isNull);
      // 系統沒有「替換動作」這個意圖，認不出來才是對的。
      expect(AppState.parseIntent('換掉臥推'), isNull);
      // 「太難了」是想降強度，舊版的 `難` 會判成升強度 —— 剛好相反。
      expect(AppState.parseIntent('太難了'), isNull);
      // 「減強度」講的不是組數，舊版的 `減` 會判成減組數。
      expect(AppState.parseIntent('減強度'), isNull);
    });

    test('使用者原本那幾句話會送給模型 —— 不再被丟掉', () async {
      final fake = _FakeSource(reply: const {'source': 'gemini', 'changes': []});
      final s = AppState()..aiSource = fake;
      s.startWorkout(s.platformPlans.firstWhere((p) => p.exercises.isNotEmpty));
      s.aiRequest(AiSource.duringTraining, '幫我保留一個動作就好');
      s.aiConfirmDemand(AiSource.duringTraining, '減少組數');

      await s.aiProduceSuggestionAsync(AiSource.duringTraining);

      expect(fake.sent!['note'], '幫我保留一個動作就好');
      expect(fake.sent!['intent'], 'trim', reason: '意圖仍然只有三選一');
    });

    test('只回答三選一時不送 note —— 那已經表達成 intent 了', () async {
      final fake = _FakeSource(reply: const {'source': 'gemini', 'changes': []});
      final s = AppState()..aiSource = fake;
      s.startWorkout(s.platformPlans.firstWhere((p) => p.exercises.isNotEmpty));
      s.aiRequest(AiSource.duringTraining, '整體降強度');
      s.aiConfirmDemand(AiSource.duringTraining, '整體降強度');

      await s.aiProduceSuggestionAsync(AiSource.duringTraining);
      expect(fake.sent!.containsKey('note'), isFalse);
    });

    test('補充過長時截斷 —— 不讓使用者決定 prompt 有多長', () async {
      final fake = _FakeSource(reply: const {'source': 'gemini', 'changes': []});
      final s = AppState()..aiSource = fake;
      s.startWorkout(s.platformPlans.firstWhere((p) => p.exercises.isNotEmpty));
      s.aiRequest(AiSource.duringTraining, '很' * 500);
      s.aiConfirmDemand(AiSource.duringTraining, '減少組數');

      await s.aiProduceSuggestionAsync(AiSource.duringTraining);
      expect((fake.sent!['note'] as String).length, 200);
    });

    test('模型回的建議會取代端內規則的結果', () async {
      final base = AppState()
        ..startWorkout(AppState()
            .platformPlans
            .firstWhere((p) => p.exercises.isNotEmpty));
      final first = base.session!.exercises.first;

      final s = upToAnalyzing(_FakeSource(reply: {
        'source': 'gemini',
        'changes': [
          {
            'index': 0,
            'name': first.exercise.name,
            'after': [
              {'weight': first.planned.first.targetWeight, 'reps': 33},
            ],
          },
        ],
      }));
      await s.aiProduceSuggestionAsync(AiSource.beforeTraining);

      final sug = s.aiSuggestion[AiSource.beforeTraining]!;
      expect(sug.changes.single.after.single.targetReps, 33,
          reason: '33 是規則引擎絕對算不出來的數字');
      expect(s.aiLastOrigin, SuggestionOrigin.gemini);
    });

    test('還沒產出建議就失敗 —— 不退不該退的點', () async {
      // 這是既有的 bug，接外部 API 才踩到：畫面上的「模擬逾時」
      // 顯示在 analyzing 階段，而扣點發生在「成功產出建議」時。
      // aiFail 原本無條件退 1 點 —— 使用者每失敗一次就白賺一點。
      final s = upToAnalyzing(null);
      final before = s.aiTotal;
      s.aiFail(AiSource.beforeTraining, AiFailReason.timeout);
      expect(s.aiTotal, before, reason: '沒扣過就不該退');
    });

    test('扣過了才退 —— 成功產出後失敗，點數淨額為零', () async {
      final s = upToAnalyzing(null);
      final before = s.aiTotal;
      await s.aiProduceSuggestionAsync(AiSource.beforeTraining);
      expect(s.aiTotal, before - 1, reason: '前提：成功產出時扣了一點');

      s.aiFail(AiSource.beforeTraining, AiFailReason.timeout);
      expect(s.aiTotal, before, reason: '扣了就要退回來');
    });

    test('接受之後的失敗不退點 —— 那一點已經定了', () async {
      final s = upToAnalyzing(null);
      final before = s.aiTotal;
      await s.aiProduceSuggestionAsync(AiSource.beforeTraining);
      s.aiAccept(AiSource.beforeTraining);
      s.aiFail(AiSource.beforeTraining, AiFailReason.timeout);
      expect(s.aiTotal, before - 1);
    });

    test('外部 API 失敗走既有的退點流程 —— 點數淨額為零', () async {
      final s = upToAnalyzing(_FakeSource(throws: true));
      final before = s.aiTotal;

      await s.aiProduceSuggestionAsync(AiSource.beforeTraining);

      expect(s.aiStage[AiSource.beforeTraining], AiStage.failed);
      expect(s.aiTotal, before,
          reason: '失敗在產出之前，所以沒扣到也不該退 —— 淨額為零');
      expect(s.aiSuggestion[AiSource.beforeTraining], isNull,
          reason: '失敗時維持原課表，不留半份建議');
    });
  });

  group('HTTP 實作', () {
    final url = Uri.parse('https://example.workers.dev');

    HttpAiSuggestionSource src(
      MockClient client, {
      String? token = 'tok',
    }) =>
        HttpAiSuggestionSource(
          endpoint: url,
          idToken: () async => token,
          client: client,
        );

    test('帶上 Bearer token —— Worker 靠它擋掉別人', () async {
      late http.Request seen;
      final s = src(MockClient((r) async {
        seen = r;
        return http.Response(
            jsonEncode({'source': 'rule', 'changes': []}), 200);
      }));
      await s.suggest(exercises: _plan(), intent: AdjustIntent.easier);

      expect(seen.headers['Authorization'], 'Bearer tok');
      expect(jsonDecode(seen.body)['intent'], 'easier');
    });

    test('使用者自己打的話會一起送出去', () async {
      late http.Request seen;
      final s = src(MockClient((r) async {
        seen = r;
        return http.Response(
            jsonEncode({'source': 'rule', 'changes': []}), 200);
      }));
      await s.suggest(
        exercises: _plan(),
        intent: AdjustIntent.trim,
        note: '幫我保留一個動作就好',
      );
      expect(jsonDecode(utf8.decode(seen.bodyBytes))['note'], '幫我保留一個動作就好');
    });

    test('沒有補充時不送 note 這個欄位', () async {
      late http.Request seen;
      final s = src(MockClient((r) async {
        seen = r;
        return http.Response(
            jsonEncode({'source': 'rule', 'changes': []}), 200);
      }));
      await s.suggest(exercises: _plan(), intent: AdjustIntent.easier);
      expect(jsonDecode(seen.body).containsKey('note'), isFalse);
    });

    test('沒登入就不送出去 —— 不浪費一趟往返', () async {
      var called = false;
      final s = src(
        MockClient((_) async {
          called = true;
          return http.Response('{}', 200);
        }),
        token: null,
      );
      await expectLater(
        s.suggest(exercises: _plan(), intent: AdjustIntent.easier),
        throwsA(isA<StateError>()),
      );
      expect(called, isFalse);
    });

    test('非 200 視為失敗 —— 交給既有的退點流程', () async {
      final s = src(MockClient((_) async => http.Response('boom', 500)));
      await expectLater(
        s.suggest(exercises: _plan(), intent: AdjustIntent.easier),
        throwsA(isA<http.ClientException>()),
      );
    });

    test('中文以 UTF-8 解，動作名稱才對得上', () async {
      final s = src(MockClient((_) async => http.Response.bytes(
            utf8.encode(jsonEncode({
              'source': 'gemini',
              'changes': [
                {
                  'index': 0,
                  'name': '槓鈴臥推',
                  'after': [
                    {'weight': 55, 'reps': 10},
                  ],
                },
              ],
            })),
            200,
          )));
      final got =
          await s.suggest(exercises: _plan(), intent: AdjustIntent.easier);
      expect(got.origin, SuggestionOrigin.gemini);
      expect(got.suggestion.changes.single.exerciseName, '槓鈴臥推');
    });
  });
}
