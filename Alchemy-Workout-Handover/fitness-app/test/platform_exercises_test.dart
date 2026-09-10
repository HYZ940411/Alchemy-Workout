import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_app/domain/ability.dart';
import 'package:fitness_app/domain/models.dart';
import 'package:fitness_app/mock/mock_data.dart';
import 'package:fitness_app/mock/mock_equipment.dart';

/// 守住由 CSV 產生的平台動作庫。
/// 產生器是 tools/import_exercises.py —— 這些斷言在它改壞時要擋下來。
void main() {
  group('平台動作庫（自 CSV 匯入）', () {
    test('筆數與唯一 id', () {
      expect(kExercises.length, 527);
      final ids = kExercises.map((e) => e.id).toSet();
      expect(ids.length, kExercises.length, reason: 'id 必須唯一');
    });

    test('所屬肌群為空值，當且僅當動作類型為有氧', () {
      for (final e in kExercises) {
        expect(e.name.trim(), isNotEmpty);
        expect(e.dim == null, e.type == ExerciseType.cardio,
            reason: '${e.name}：肌群為空與有氧兩者必須同時成立或同時不成立');
      }
    });

    test('活動度與體能訓練走有氧路徑，不進六維', () {
      final cardio = kExercises.where((e) => e.type == ExerciseType.cardio);
      // 18 筆活動度／呼吸／伸展 ＋ 4 筆體能訓練
      expect(cardio.length, 22);
      for (final e in cardio) {
        expect(e.dim, isNull);
        expect(e.relativeIntensity, 0.0,
            reason: '${e.name} 不計入能力值，相對強度係數應為 0');
      }
      expect(cardio.map((e) => e.name), contains('貓牛式'));
      expect(cardio.map((e) => e.name), contains('波比跳'));
    });

    test('有氧分頁涵蓋器材類與匯入的有氧動作', () {
      final names = kCardioExercises.map((e) => e.name).toSet();
      expect(names, contains('跑步機'));
      expect(names, contains('仰臥腹式呼吸'));
      expect(kCardioExercises.every((e) => e.dim == null), isTrue);
    });

    test('器材只能落在模型的 8 個品項內', () {
      final domain = kEquipmentVenues.keys.toSet();
      for (final e in kExercises) {
        // 「＋」之後為配件（平板椅等），不屬模型值域，不參與器材比對。
        final head = e.equipment.split(' ＋ ').first;
        for (final item in head.split(' · ')) {
          expect(domain, contains(item),
              reason: '${e.name} 的器材「$item」不在〈器材設定 Aggregate〉的值域中');
        }
      }
    });

    test('六維都有動作，沒有哪一維是空的', () {
      for (final d in Dim.values) {
        expect(kExercises.where((e) => e.dim == d), isNotEmpty,
            reason: '${dimNames[d]} 沒有任何動作，動作庫該分頁會是空的');
      }
    });

    test('調過係數的 15 筆示範動作在匯入後仍在，且值沒被覆蓋', () {
      // CSV 沒有相對強度係數與預設組間休息秒數，這兩欄靠 OVERRIDES 保留。
      const expected = {
        'bench': (1.00, 150),
        'squat': (0.72, 180),
        'deadlift': (0.62, 180),
        'ohp': (1.35, 120),
        'lateral': (2.60, 60),
      };
      expected.forEach((id, v) {
        final e = ex(id);
        expect(e.relativeIntensity, v.$1, reason: '$id 的相對強度係數被覆蓋了');
        expect(e.defaultRestSeconds, v.$2, reason: '$id 的預設休息秒數被覆蓋了');
      });
    });

    test('相對強度係數不再全是 1.0，且落在合理範圍', () {
      final strength =
          kExercises.where((e) => e.type == ExerciseType.strength).toList();
      final ones = strength.where((e) => e.relativeIntensity == 1.0).length;
      expect(ones / strength.length, lessThan(0.1),
          reason: '係數若大多是 1.0，等於沒有把不同動作拉到同一尺度');
      for (final e in strength) {
        expect(e.relativeIntensity, greaterThan(0.3), reason: e.name);
        expect(e.relativeIntensity, lessThan(5.0), reason: e.name);
      }
    });

    test('重量級動作的係數低於臥推，孤立動作高於臥推', () {
      // 錨點：槓鈴臥推 ＝ 1.0。基準值與映射係數皆由它反解，
      // 故六維共用同一把尺，係數必須全部相對於臥推。
      expect(ex('bench').relativeIntensity, 1.0);
      // 硬舉、深蹲、腿推舉得比臥推重 → 係數更低
      expect(ex('deadlift').relativeIntensity, lessThan(1.0));
      expect(ex('squat').relativeIntensity, lessThan(1.0));
      expect(ex('legpress').relativeIntensity, lessThan(ex('squat').relativeIntensity));
      // 側平舉、彎舉舉得比臥推輕 → 係數更高
      expect(ex('lateral').relativeIntensity, greaterThan(2.0));
      expect(ex('curl').relativeIntensity, greaterThan(1.0));
    });

    test('同型態的動作係數一致 —— 上斜比平板重不起來，係數該更高', () {
      final flat = kExercises.firstWhere((e) => e.name == '板凳臥推 · 槓鈴');
      final incline =
          kExercises.firstWhere((e) => e.name == '上斜板凳臥推 · 槓鈴');
      final decline =
          kExercises.firstWhere((e) => e.name == '下斜板凳臥推 · 槓鈴');
      expect(incline.relativeIntensity, greaterThan(flat.relativeIntensity));
      expect(decline.relativeIntensity, lessThan(flat.relativeIntensity));
    });

    test('未調過的匯入動作退回全站預設休息秒數', () {
      final plain = kExercises.firstWhere((e) => e.id.startsWith('p'));
      expect(plain.defaultRestSeconds, isNull,
          reason: 'CSV 沒有這一欄，應退回全站預設 90 秒而非給假值');
    });

    test('課表引用的動作 id 全都解析得到', () {
      for (final p in kPlans) {
        for (final pe in p.exercises) {
          expect(kExercises.any((e) => e.id == pe.exercise.id), isTrue,
              reason: '${p.name} 引用了不存在的動作 ${pe.exercise.id}');
        }
      }
    });
  });

  group('訓練部位（複選）與所屬肌群（單值）是兩件事', () {
    test('能力值歸屬仍是單一維度', () {
      for (final e in kExercises) {
        // dim 是能力值歸屬 —— 一個動作只提升一維，不因可練到多部位而分散。
        expect(e.dim == null, e.type == ExerciseType.cardio);
      }
    });

    test('訓練部位含主要肌群', () {
      for (final e in kExercises.where((e) => e.parts.isNotEmpty)) {
        expect(e.parts, contains(e.dim),
            reason: '${e.name} 的訓練部位不含其主要肌群，兩者對不上');
      }
    });

    test('窄距臥推同時出現在胸與手 —— 這正是複選要解決的事', () {
      final e = kExercises.firstWhere((e) => e.name == '板凳臥推 (窄距) · 槓鈴');
      expect(e.tabs, containsAll([Dim.chest, Dim.arms]));
      expect(e.dim, Dim.chest, reason: '能力值仍只計入胸');
    });

    test('單一部位的動作不必填 parts，tabs 退回所屬肌群', () {
      final e = ex('squat');
      expect(e.parts, isEmpty);
      expect(e.tabs, {Dim.legs});
    });

    test('有氧動作不出現在任何肌群分頁', () {
      for (final e in kExercises.where((e) => e.type == ExerciseType.cardio)) {
        expect(e.tabs, isEmpty);
      }
    });

    test('複選讓各分頁的動作數增加，且沒有哪一維變空', () {
      for (final d in Dim.values) {
        final byTab = kExercises.where((e) => e.tabs.contains(d)).length;
        final byDim = kExercises.where((e) => e.dim == d).length;
        expect(byTab, greaterThanOrEqualTo(byDim));
        expect(byTab, greaterThan(0));
      }
    });
  });
}
