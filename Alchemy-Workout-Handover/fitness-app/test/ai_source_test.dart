// 外部 AI 的邊界（`[BE-08]`）。
//
// 規格把 LLM 放在軟體邊界**之外**，只規範呼叫時點、扣點、失敗退點與
// 「AI 僅產出建議、不套用」。那四件事在接上外部 API 之前就已經做好了，
// 所以這個檔案測的是**邊界本身**：送出去的形狀、收回來的還原、
// 以及失敗時有沒有走既有的退點流程。
//
// **不接外部 API 時行為必須與接上之前一模一樣** —— 那是既有一千多條
// 測試的前提，這裡第一組就釘住它。

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/ai_suggestion.dart';
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
  }) async {
    sent = {'intent': intent.name, ...encodePlan(exercises, onlyFrom)};
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

    test('失敗走既有的退點流程 —— 點數淨額為零', () async {
      final s = upToAnalyzing(_FakeSource(throws: true));
      final before = s.aiTotal;

      await s.aiProduceSuggestionAsync(AiSource.beforeTraining);

      expect(s.aiStage[AiSource.beforeTraining], AiStage.failed);
      expect(s.aiTotal, before, reason: '扣了要退回來');
      expect(s.aiSuggestion[AiSource.beforeTraining], isNull,
          reason: '失敗時維持原課表，不留半份建議');
    });
  });
}
