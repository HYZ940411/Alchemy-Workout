// AI 調整的時間預算與彈性（2026-10-04 使用者裁決）。
//
// 起因：訓練中對 AI 說「請幫我根據這個課表目標增加動作（增加整體強度）」，
// 換來「目前只能往這 4 個方向調」。三項裁決：
//
//   1. AI 可以在訓練中加動作 —— 只能從系統算好的候選清單挑
//   2. 加多少由剩餘時間決定：不夠一組只加重量、夠 1～2 組在現有動作加組、
//      夠 ≥ 3 組可加一個新動作
//   3. 減組數也照時間砍，先砍排在後面的動作，前面的主項保留
//
// 另外修掉兩個自體重動作的 bug：降強度反而加次數、加強度什麼都不做。

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/ai_suggestion.dart';
import 'package:fitness_app/domain/ability.dart';
import 'package:fitness_app/domain/adjust_volume.dart';
import 'package:fitness_app/domain/ai_adjust.dart';
import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/domain/models.dart';
import 'package:fitness_app/domain/plan_duration.dart';
import 'package:fitness_app/state/app_state.dart';

Exercise _ex(String id) => Exercise(
      id: id,
      name: '動作$id',
      dim: Dim.chest,
      parts: const {},
      relativeIntensity: 1,
      isBodyweight: false,
      type: ExerciseType.strength,
      equipment: '',
    );

/// 每組 10 下（50 秒）＋ 休息 100 秒 ＝ 150 秒。
PlanExercise _pe(String id, int sets, {double weight = 60, int reps = 10}) =>
    PlanExercise(
      exercise: _ex(id),
      planned: [for (var i = 0; i < sets; i++) PlannedSet(weight, reps)],
      restSeconds: 100,
    );

int _rest(PlanExercise pe) => pe.restSeconds!;

VolumePlan _plan(List<PlanExercise> ex, List<AdjustIntent> intents, int? min,
        {bool allowNew = false, Map<int, int> done = const {}}) =>
    planVolume(
      exercises: ex,
      intents: intents,
      minutes: min,
      restSecondsOf: _rest,
      doneSets: done,
      allowNewExercise: allowNew,
    );

void main() {
  test('前提：一組 150 秒，與課表頁的時長公式同一份', () {
    final pe = _pe('a', 1);
    expect(setSeconds(pe, pe.planned.first, 100), 150);
  });

  group('加強度：加多少由剩餘時間決定', () {
    // 三個動作各 3 組 ＝ 9 組 × 150 秒 ＝ 22.5 分鐘。
    final ex = [_pe('a', 3), _pe('b', 3), _pe('c', 3)];

    test('多出的時間不夠一組 → 只加重量', () {
      final v = _plan(ex, [AdjustIntent.harder], 24);
      expect(v.weightOnly, isTrue);
      expect(v.addedSetCount, 0);
    });

    test('夠 1～2 組 → 在前面的主項加組', () {
      final v = _plan(ex, [AdjustIntent.harder], 28); // 多 5.5 分 ＝ 2 組
      expect(v.weightOnly, isFalse);
      expect(v.addSets, {0: 1, 1: 1}, reason: '從第一個動作開始，一輪一組');
      expect(v.newExerciseSets, 0);
    });

    test('夠 ≥ 3 組、而且在訓練中 → 加一個新動作', () {
      final v = _plan(ex, [AdjustIntent.harder], 31, allowNew: true); // 3 組
      expect(v.newExerciseSets, 3);
      expect(v.addSets, isEmpty);
    });

    test('新動作最多 4 組，剩下的時間加在既有動作上', () {
      final v = _plan(ex, [AdjustIntent.harder], 40, allowNew: true); // 7 組
      expect(v.newExerciseSets, kNewExerciseMaxSets);
      expect(v.addSets.values.fold(0, (a, b) => a + b), 3);
    });

    test('訓練前不加新動作 —— 規格的加動作只在訓練中', () {
      final v = _plan(ex, [AdjustIntent.harder], 31);
      expect(v.newExerciseSets, 0);
      expect(v.addSets.values.fold(0, (a, b) => a + b), 3);
    });

    test('每個既有動作最多加 2 組 —— 時間再多也不變成另一份課表', () {
      final v = _plan(ex, [AdjustIntent.harder], 300);
      for (final n in v.addSets.values) {
        expect(n, lessThanOrEqualTo(kMaxAddedSetsPerExercise));
      }
    });

    test('不知道時間 → 只加重量（舊規則）', () {
      expect(_plan(ex, [AdjustIntent.harder], null).weightOnly, isTrue);
    });
  });

  group('減組數：照時間砍，先砍後面的動作', () {
    final ex = [_pe('a', 3), _pe('b', 3), _pe('c', 3)]; // 22.5 分鐘

    test('時間夠就不砍', () {
      final v = _plan(ex, [AdjustIntent.trim], 30);
      expect(v.cutSets, isEmpty);
      expect(v.fits, isTrue);
    });

    test('從最後一個動作開始砍，砍到只剩一組才輪到前一個', () {
      final v = _plan(ex, [AdjustIntent.trim], 15); // 要砍 7.5 分 ＝ 3 組
      expect(v.cutSets, {2: 2, 1: 1}, reason: '主項（第一個）一組都不動');
    });

    test('每個動作都只剩一組仍放不下 → 說得出超出多少', () {
      final v = _plan(ex, [AdjustIntent.trim], 3);
      expect(v.cutSets, {2: 2, 1: 2, 0: 2});
      expect(v.overSeconds, greaterThan(0));
    });

    test('已完成的組不算時間、也不能砍', () {
      final v = _plan(ex, [AdjustIntent.trim], 15, done: {2: 3});
      expect(v.cutSets[2], isNull, reason: '最後一個動作已經練完了');
    });

    test('不知道時間 → 每個動作砍一組（舊規則）', () {
      expect(_plan(ex, [AdjustIntent.trim], null).cutSets, {0: 1, 1: 1, 2: 1});
    });

    test('照安排產出的建議，組數真的變了', () {
      final v = _plan(ex, [AdjustIntent.trim], 15);
      final sug = buildSuggestion(ex, AdjustIntent.trim, volume: v);
      expect([for (final c in sug.changes) c.after.length], [3, 2, 1]);
      expect(sug.rationale, contains('前面的主項保留'));
    });
  });

  group('自體重動作的兩個 bug', () {
    final bw = [_pe('p', 3, weight: 0, reps: 10)];

    test('降強度：次數要變少，不是變多', () {
      final after = buildSuggestion(bw, AdjustIntent.easier).changes.single.after;
      expect(after.first.targetReps, lessThan(10));
      expect(after.first.targetWeight, 0);
    });

    test('加強度：次數要變多，不是什麼都沒發生', () {
      final after = buildSuggestion(bw, AdjustIntent.harder).changes.single.after;
      expect(after.first.targetReps, greaterThan(10));
    });
  });

  group('一句話兩個要求', () {
    test('降與升同時出現是矛盾 → 判不出來', () {
      expect(resolveIntents([AdjustIntent.easier, AdjustIntent.harder]), isEmpty);
    });

    test('降強度＋減組數 → 兩件都做', () {
      final ex = [_pe('a', 3), _pe('b', 3)];
      final v = _plan(ex, [AdjustIntent.easier, AdjustIntent.trim], 10);
      final sug = buildSuggestion(ex, AdjustIntent.easier,
          intents: [AdjustIntent.easier, AdjustIntent.trim], volume: v);
      expect(sug.changes.first.after.first.targetWeight, lessThan(60));
      expect(sug.changes.last.after.length, lessThan(3));
      expect(sug.title, '整體降強度＋減少組數');
    });
  });

  group('讀出時間', () {
    test('各種說法', () {
      expect(parseMinutes('只剩 20 分鐘'), 20);
      expect(parseMinutes('還有半小時'), 30);
      expect(parseMinutes('一個半小時'), 90);
      expect(parseMinutes('1.5 小時'), 90);
      expect(parseMinutes('十五分鐘'), 15);
      expect(parseMinutes('二十五分'), 25);
      expect(parseMinutes('２０分鐘'), 20);
      expect(parseMinutes('20'), isNull, reason: '單獨一個數字不一定是時間');
      expect(parseMinutes('20', bareNumber: true), 20,
          reason: '但在回答「還有多少時間」時就是');
      expect(parseMinutes('早安'), isNull);
    });

    test('不知道就說不知道', () {
      expect(minutesUnknown('不確定'), isTrue);
      expect(minutesUnknown('20 分鐘'), isFalse);
    });
  });

  group('整條流程', () {
    AppState started() {
      final s = AppState();
      s.startWorkout(s.platformPlans.firstWhere((p) => p.exercises.length >= 2));
      return s;
    }

    test('加強度會先問時間，答了才進分析', () async {
      final s = started();
      s.aiRequest(AiSource.duringTraining, '');
      await s.aiConfirmDemand(AiSource.duringTraining, '整體升強度');
      expect(s.aiStage[AiSource.duringTraining], AiStage.clarifying);
      expect(s.aiAwaitingMinutes[AiSource.duringTraining], isTrue);

      await s.aiConfirmDemand(AiSource.duringTraining, '30 分鐘');
      expect(s.aiStage[AiSource.duringTraining], AiStage.analyzing);
      expect(s.aiMinutes[AiSource.duringTraining], 30);
    });

    test('句子裡講過時間就不再問', () async {
      final s = started();
      s.aiRequest(AiSource.duringTraining, '');
      await s.aiConfirmDemand(AiSource.duringTraining, '我時間不夠，只剩 10 分鐘');
      expect(s.aiAwaitingMinutes[AiSource.duringTraining] ?? false, isFalse);
      expect(s.aiMinutes[AiSource.duringTraining], 10);
    });

    test('讀不出時間就再問一次，不扣點', () async {
      final s = started();
      final before = s.aiTotal;
      s.aiRequest(AiSource.duringTraining, '');
      await s.aiConfirmDemand(AiSource.duringTraining, '整體升強度');
      await s.aiConfirmDemand(AiSource.duringTraining, '早安');
      expect(s.aiStage[AiSource.duringTraining], AiStage.clarifying);
      expect(s.aiTotal, before);
    });

    test('「增加動作」本機規則也認得 —— AI 掛掉時不再整句落空', () {
      expect(AppState.parseIntent('請幫我增加動作'), AdjustIntent.harder);
      expect(AppState.parseIntent('幫我加一組'), AdjustIntent.harder,
          reason: '含「組」，但講的是加');
      expect(AppState.parseIntent('我想多練上胸'), isNull,
          reason: '改練部位不是加量');
    });
  });

  group('模型與規則逐筆合併', () {
    test('模型給的組數對不上時間安排 → 那一筆用規則', () async {
      final s = AppState();
      s.startWorkout(s.platformPlans.firstWhere((p) => p.exercises.length >= 2));
      final first = s.session!.exercises.first;
      s.aiSource = _Fake({
        'source': 'gemini',
        'changes': [
          // 模型自己多加了 5 組 —— 不照安排。
          {
            'index': 0,
            'name': first.exercise.name,
            'after': [
              for (var i = 0; i < first.planned.length + 5; i++)
                {'weight': first.planned.first.targetWeight, 'reps': 33},
            ],
          },
        ],
      });
      s.aiRequest(AiSource.beforeTraining, '');
      await s.aiConfirmDemand(AiSource.beforeTraining, '減少組數');
      await s.aiConfirmDemand(AiSource.beforeTraining, '5 分鐘');
      await s.aiProduceSuggestionAsync(AiSource.beforeTraining);

      final c = s.aiSuggestion[AiSource.beforeTraining]!.changes
          .firstWhere((c) => c.exerciseIndex == 0);
      expect(c.after.any((x) => x.targetReps == 33), isFalse,
          reason: '模型不照時間安排的那一筆不收');
    });

    test('模型挑出的新動作在訓練中會真的加進課表', () async {
      final s = AppState();
      s.startWorkout(s.platformPlans.firstWhere((p) => p.exercises.length >= 2));
      final pool = s.addCandidatesFor(s.session!.exercises, 0);
      expect(pool, isNotEmpty, reason: '前提：有候選');
      final pick = pool.first;
      s.aiSource = _Fake({
        'source': 'gemini',
        'changes': [],
        'added': [
          {
            'name': pick.name,
            'after': [
              for (var i = 0; i < 4; i++) {'weight': 20, 'reps': 10},
            ],
            'reason': '多出的時間補一個同部位動作',
          },
        ],
      });
      final count = s.session!.exercises.length;
      s.aiRequest(AiSource.duringTraining, '');
      await s.aiConfirmDemand(AiSource.duringTraining, '整體升強度');
      await s.aiConfirmDemand(AiSource.duringTraining, '600 分鐘');
      await s.aiProduceSuggestionAsync(AiSource.duringTraining);

      final sug = s.aiSuggestion[AiSource.duringTraining]!;
      expect(sug.additions.single.addition!.name, pick.name);
      s.aiAccept(AiSource.duringTraining);
      expect(s.session!.exercises.length, count + 1,
          reason: '走「加入動作至本次訓練」，課表真的多一個動作');
      expect(s.session!.exercises.last.exercise.name, pick.name);
    });

    test('模型挑了候選以外的動作 → 不收，時間改加在既有動作上', () async {
      final s = AppState();
      s.startWorkout(s.platformPlans.firstWhere((p) => p.exercises.length >= 2));
      s.aiSource = _Fake({
        'source': 'gemini',
        'changes': [],
        'added': [
          {
            'name': '憑空發明的動作',
            'after': [
              for (var i = 0; i < 4; i++) {'weight': 20, 'reps': 10},
            ],
          },
        ],
      });
      s.aiRequest(AiSource.duringTraining, '');
      await s.aiConfirmDemand(AiSource.duringTraining, '整體升強度');
      await s.aiConfirmDemand(AiSource.duringTraining, '600 分鐘');
      await s.aiProduceSuggestionAsync(AiSource.duringTraining);

      final sug = s.aiSuggestion[AiSource.duringTraining]!;
      expect(sug.additions, isEmpty);
      expect(sug.changes.any((c) => c.after.length > c.before.length), isTrue,
          reason: '加量仍然成立，只是加在既有動作上');
    });

    test('回答時間的那句不會被當成補充說明送進 prompt', () async {
      final fake = _Fake(const {'source': 'gemini', 'changes': []});
      final s = AppState()..aiSource = fake;
      s.startWorkout(s.platformPlans.firstWhere((p) => p.exercises.isNotEmpty));
      s.aiRequest(AiSource.duringTraining, '');
      await s.aiConfirmDemand(AiSource.duringTraining, '整體升強度');
      await s.aiConfirmDemand(AiSource.duringTraining, '20 分鐘');
      await s.aiProduceSuggestionAsync(AiSource.duringTraining);
      expect(fake.note, isNull);
    });
  });
}

/// 直接回一份固定的伺服器回應，走真的 `decodeSuggestion`。
class _Fake implements AiSuggestionSource {
  final Map<String, dynamic> reply;
  String? note;
  _Fake(this.reply);

  @override
  Future<RemoteIntent> classify(String say) async => const RemoteIntent(null);

  @override
  Future<RemoteAutoAdjust> suggestAuto({
    required List<PlanExercise> exercises,
    AdjustContext? context,
    Map<String, List<Exercise>> candidates = const {},
  }) async =>
      const RemoteAutoAdjust();

  @override
  Future<RemoteSuggestion> suggest({
    required List<PlanExercise> exercises,
    required AdjustIntent intent,
    int onlyFrom = 0,
    String? note,
    AdjustContext? context,
    Map<String, List<Exercise>> candidates = const {},
    List<AdjustIntent>? intents,
    VolumePlan? volume,
    List<Exercise> addCandidates = const [],
  }) async {
    this.note = note;
    return RemoteSuggestion(
      originOf(reply),
      decodeSuggestion(reply, exercises, intent, onlyFrom,
          candidates: candidates,
          intents: intents,
          addCandidates: addCandidates),
    );
  }
}
