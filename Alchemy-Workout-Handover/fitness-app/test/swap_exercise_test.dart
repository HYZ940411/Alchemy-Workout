// 替換動作（`01_Command清單.md`〈替換動作〉→ Event「AI 已替換動作」）。
//
// **這不是新功能，是補做一個規格早就定義、卻從來沒接線的 Command。**
// `PlanExercise.replacedFrom` 這個欄位一直都在，只是沒有任何地方寫進去過 ——
// 與 `[QA-02f]`／`[QA-02i]`／檔案頁／`myTeam` 同一種病。
//
// 規格要點：
//   · 以「持有器材明細」為調整依據（`02_Aggregate定義.md` §1324）
//   · 攜帶原動作 ID、替換後動作 ID、替換原因（〈訓練紀錄流程〉）
//   · 還原的三個 Precondition：該動作為替換結果、尚無已完成的組、尚未結算
//   · 逐個還原，非整批

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/ai_suggestion.dart';
import 'package:fitness_app/domain/ability.dart';
import 'package:fitness_app/domain/ai_adjust.dart';
import 'package:fitness_app/domain/models.dart';
import 'package:fitness_app/state/app_state.dart';

void main() {
  group('替代候選', () {
    test('同肌群、同類型，且器材做得到', () {
      final s = AppState();
      final src = s.platformExercises.firstWhere((e) => e.dim == Dim.chest);
      final got = s.swapCandidatesFor(src);

      expect(got, isNotEmpty);
      expect(got.every((e) => e.dim == src.dim), isTrue);
      expect(got.every((e) => e.type == src.type), isTrue);
      expect(got.any((e) => e.id == src.id), isFalse, reason: '不會換成自己');
    });

    test('器材不夠時候選要跟著變少', () {
      final s = AppState();
      final src = s.platformExercises.firstWhere((e) => e.dim == Dim.chest);
      final all = s.swapCandidatesFor(src, limit: 999).length;

      s.ownedEquipment
        ..clear()
        ..add('徒手');
      final few = s.swapCandidatesFor(src, limit: 999).length;

      expect(few, lessThan(all), reason: '這是「以持有器材明細為調整依據」的意思');
    });

    test('相對強度相近的排前面 —— 換動作不該順便換掉強度', () {
      final s = AppState();
      final src = s.platformExercises.firstWhere((e) => e.dim == Dim.back);
      final got = s.swapCandidatesFor(src, limit: 999);
      if (got.length < 2) return;
      final d0 = (got[0].relativeIntensity - src.relativeIntensity).abs();
      final dn = (got.last.relativeIntensity - src.relativeIntensity).abs();
      expect(d0, lessThanOrEqualTo(dn));
    });
  });

  group('模型挑的動作要在候選裡', () {
    List<PlanExercise> plan(Exercise e) => [
          PlanExercise(exercise: e, planned: const [PlannedSet(60, 8)]),
        ];

    test('挑候選內的就收', () {
      final s = AppState();
      final src = s.platformExercises.first;
      final cand = s.swapCandidatesFor(src).first;

      final got = decodeSuggestion({
        'changes': [
          {
            'index': 0,
            'name': src.name,
            'replacement': cand.name,
            'after': [
              {'weight': 40, 'reps': 10},
            ],
            'reason': '你沒有這個器材。',
          },
        ],
      }, plan(src), AdjustIntent.swap, 0, candidates: {src.name: [cand]});

      expect(got.changes.single.replacement?.id, cand.id);
      expect(got.changes.single.reason, '你沒有這個器材。');
    });

    test('挑候選外的整筆丟棄 —— 模型可能憑空發明一個動作', () {
      final s = AppState();
      final src = s.platformExercises.first;
      final cand = s.swapCandidatesFor(src).first;

      final got = decodeSuggestion({
        'changes': [
          {
            'index': 0,
            'name': src.name,
            'replacement': '飛天遁地大迴旋',
            'after': [
              {'weight': 40, 'reps': 10},
            ],
          },
        ],
      }, plan(src), AdjustIntent.swap, 0, candidates: {src.name: [cand]});

      expect(got.changes, isEmpty);
    });

    test('呼叫端沒給候選時一律不換', () {
      final s = AppState();
      final src = s.platformExercises.first;
      final got = decodeSuggestion({
        'changes': [
          {
            'index': 0,
            'name': src.name,
            'replacement': s.swapCandidatesFor(src).first.name,
            'after': [
              {'weight': 40, 'reps': 10},
            ],
          },
        ],
      }, plan(src), AdjustIntent.swap, 0);
      expect(got.changes, isEmpty);
    });
  });

  group('套用與還原', () {
    /// 開一場訓練，把第一個動作換成候選裡的第一個。
    (AppState, Exercise, Exercise) swapped() {
      final s = AppState();
      s.startWorkout(s.platformPlans.firstWhere((p) => p.exercises.isNotEmpty));
      final before = s.session!.exercises.first;
      final cand = s.swapCandidatesFor(before.exercise).first;

      final out = applySuggestion(s.session!.exercises, AdjustSuggestion(
        intent: AdjustIntent.swap,
        changes: [
          AdjustChange(
            exerciseIndex: 0,
            exerciseName: before.exercise.name,
            before: [...before.planned],
            after: const [PlannedSet(30, 12)],
            replacement: cand,
          ),
        ],
      ));
      for (var i = 0; i < out.length; i++) {
        s.session!.exercises[i] = out[i];
      }
      return (s, before.exercise, cand);
    }

    test('套用後記得原動作與原目標', () {
      final (s, original, cand) = swapped();
      final pe = s.session!.exercises.first;
      expect(pe.exercise.id, cand.id);
      expect(pe.replacedFrom?.id, original.id);
      expect(pe.replacedPlanned, isNotNull,
          reason: '規格：還原要含原動作各組的目標重量與次數');
    });

    test('還原回原動作與原目標', () {
      final (s, original, _) = swapped();
      final want = [...s.session!.exercises.first.replacedPlanned!];

      expect(s.restoreReplacedExercise(0), isTrue);

      final pe = s.session!.exercises.first;
      expect(pe.exercise.id, original.id);
      expect(pe.replacedFrom, isNull);
      expect(pe.planned.map((x) => (x.targetWeight, x.targetReps)),
          want.map((x) => (x.targetWeight, x.targetReps)));
    });

    test('沒被替換過的動作還原不了', () {
      final s = AppState();
      s.startWorkout(s.platformPlans.firstWhere((p) => p.exercises.isNotEmpty));
      expect(s.restoreReplacedExercise(0), isFalse);
    });

    test('已完成任何一組就不給還原 —— 那些成績記在現在這個動作名下', () {
      final (s, _, _) = swapped();
      s.session!.records[0][0].state = SetState.done;
      expect(s.restoreReplacedExercise(0), isFalse);
    });

    test('已結算就不給還原', () {
      final (s, _, _) = swapped();
      s.session = null;
      expect(s.restoreReplacedExercise(0), isFalse);
    });

    test('索引超出範圍回 false，不拋例外', () {
      final (s, _, _) = swapped();
      expect(s.restoreReplacedExercise(-1), isFalse);
      expect(s.restoreReplacedExercise(999), isFalse);
    });
  });

  test('換了動作就不算空建議 —— 即使逐組目標一樣', () {
    final s = AppState();
    s.startWorkout(s.platformPlans.firstWhere((p) => p.exercises.isNotEmpty));
    final pe = s.session!.exercises.first;
    final cand = s.swapCandidatesFor(pe.exercise).first;

    final sug = AdjustSuggestion(intent: AdjustIntent.swap, changes: [
      AdjustChange(
        exerciseIndex: 0,
        exerciseName: pe.exercise.name,
        before: [...pe.planned],
        after: [...pe.planned],
        replacement: cand,
      ),
    ]);
    expect(sug.isEmpty, isFalse,
        reason: '把做不了的動作換成做得到的，本身就是改動');
  });

  test('規則引擎不換動作 —— 那不是一條 ×0.9 算得出來的東西', () {
    final s = AppState();
    final plan = s.platformPlans.firstWhere((p) => p.exercises.isNotEmpty);
    final got = buildSuggestion(plan.exercises, AdjustIntent.swap);
    expect(got.changes.every((c) => c.replacement == null), isTrue);
    expect(got.isEmpty, isTrue, reason: '沒有模型時這個方向產不出建議');
  });
}
