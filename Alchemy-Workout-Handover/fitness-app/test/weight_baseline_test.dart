// 動作權重的「標準情境基準表」（使用者逐類裁決，2026-10-17；紀錄在「動作權重盤點.md」）。
//
// 使用者的目的：練動作時能力值不要加得太多、太奇怪。盤點時的情形（體重 70 kg 男性、10 下）：
//   · 徒手伏地挺身 639、捲腹／引體向上 999（到頂），槓鈴臥推 40 kg 才 294
//   · 啞鈴／壺鈴／彈力繩的新手重量 147 個動作是 10 分（等於沒加分）
//   · 同樣是新手，同一個部位的分數差十倍以上
//
// 裁決的標準：**體重 70 kg 的新手，舒服做完 10 下，落在固定分數**
//   · 有重量的動作（槓鈴／啞鈴／機械／繩索／壺鈴）與徒手動作：C 級，294 分
//   · 彈力繩：150 分
//   · 13 個沒拿東西的徒手孤立動作：50 分
//
// 這份測試就是那張基準表：**它自己獨立分類、用真的 measuredScore 算**，不讀生成腳本的任何中間結果。
// 以後任何人調了權重（tools/import_exercises.py 的 NOVICE_WEIGHT 等），
// 這裡會紅，並指出是哪一類、哪個動作、現在變成幾分。
// 要改標準就改這裡的數字，並在 PROGRESS 記下為什麼。
//
// 新手標準重量（公斤；啞鈴為每手）與腳本那份是兩份各寫的 —— 刻意的，兩邊對不上就會紅。

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/ability.dart';
import 'package:fitness_app/domain/carry_forward.dart';
import 'package:fitness_app/domain/models.dart';
import 'package:fitness_app/domain/rewards.dart';
import 'package:fitness_app/mock/platform_exercises.g.dart';
import 'package:fitness_app/state/app_state.dart';

const double _bw = 70; // 標準情境的體重
const int _tolerance = 2; // 係數只留 4 位小數，分數可能差 1～2 分

const int _scoreC = 294;
const int _scoreBand = 150;
const int _scoreLow = 50;

/// 13 個沒拿東西的徒手孤立動作。
const _lowGroup = {
  '肘臂繞圈', '手臂繞圈', '前平舉', '上舉', '合掌上舉', '站姿反手上提', '臥姿反向飛鳥',
  '交互拳擊', '二頭肌屈臂', '二頭肌彎舉(抬腿)', '側臥二頭肌彎舉', '跪姿三頭肌伸展', '側平舉',
};

/// 新手標準重量。鍵：動作型態 → 器材群（槓／啞／器／繩）。
const _novice = <String, Map<String, double>>{
  '複合推': {'槓': 40, '啞': 14, '器': 35, '繩': 20},
  '飛鳥夾胸': {'啞': 8, '器': 25, '繩': 10},
  '仰臥上拉': {'槓': 20, '啞': 14},
  '划船': {'槓': 40, '啞': 16, '器': 35, '繩': 35},
  '下拉上拉': {'槓': 20, '啞': 14, '器': 40, '繩': 40},
  '聳肩': {'槓': 50, '啞': 16, '器': 50, '繩': 40},
  '硬舉': {'槓': 60, '啞': 16, '器': 50},
  '背伸展躬身': {'槓': 30, '器': 30},
  '肩後束小肌群': {'啞': 4, '器': 10, '繩': 8},
  '深蹲': {'槓': 50, '啞': 14, '器': 40, '繩': 30},
  '腿推': {'器': 100},
  '弓步單腿': {'槓': 30, '啞': 10, '器': 20, '繩': 15},
  '臀橋臀推': {'槓': 60, '啞': 16, '器': 60, '繩': 30},
  '提踵': {'槓': 40, '啞': 12, '器': 40},
  '腿孤立': {'啞': 5, '器': 30, '繩': 15},
  '全身爆發': {'槓': 30, '啞': 12},
  '負重行走': {'槓': 40, '啞': 16},
  '肩推': {'槓': 30, '啞': 10, '器': 25, '繩': 15},
  '平舉': {'槓': 15, '啞': 5, '器': 10, '繩': 8},
  '二頭彎舉': {'槓': 20, '啞': 8, '器': 15, '繩': 15},
  '三頭肌': {'槓': 20, '啞': 8, '器': 25, '繩': 20},
  '腕彎舉': {'槓': 15, '啞': 6, '繩': 15},
  '核心捲腹抬腿': {'啞': 8, '繩': 30},
  '核心轉體側彎': {'槓': 20, '啞': 8, '器': 30, '繩': 20},
};

/// 壺鈴：一般 12 kg，下列動作例外。
const _kettlebellDefault = 12.0;
const _kettlebell = {
  '硬舉': 16.0, '直腿硬舉': 16.0, '單腳硬舉': 16.0, '農夫走路': 16.0,
  '上舉': 8.0, '風車': 8.0, '仰臥起坐': 8.0,
  '側平舉': 4.0,
};

String _group(Exercise e) {
  final q = e.equipment.split(' ＋ ').first;
  if (q.contains('彈力繩')) return '帶';
  if (q.contains('壺鈴')) return '壺';
  if (q.contains('槓鈴')) return '槓';
  if (q.contains('啞鈴')) return '啞';
  if (q.contains('繩索')) return '繩';
  if (q.contains('機械式')) return '器';
  return '徒';
}

bool _has(String name, String pattern) => RegExp(pattern).hasMatch(name);

String _pattern(Exercise e) {
  final n = e.name;
  if (_has(n, r'抓舉|挺舉|上搏|瞬發|甩壺|甩鈴|土耳其|借力')) return '全身爆發';
  if (_has(n, r'負重行走|農夫走路')) return '負重行走';
  switch (e.dim!) {
    case Dim.back:
      if (_has(n, '划船')) return '划船';
      if (_has(n, r'下拉|上拉|引體|滑輪下壓')) return '下拉上拉';
      if (_has(n, '聳肩')) return '聳肩';
      if (_has(n, '硬舉')) return '硬舉';
      if (_has(n, r'背部伸展|躬身|超人')) return '背伸展躬身';
      return '肩後束小肌群';
    case Dim.chest:
      if (_has(n, '上拉')) return '仰臥上拉';
      if (_has(n, r'飛鳥|夾胸|擴胸')) return '飛鳥夾胸';
      return '複合推';
    case Dim.shoulders:
      if (_has(n, r'反向.*飛鳥|臉拉|外旋|外琁|內轉|後划|划舉|繞圈|上提')) return '肩後束小肌群';
      if (_has(n, '平舉')) return '平舉';
      if (_has(n, '划船')) return '划船';
      return '肩推';
    case Dim.arms:
      if (_has(n, '腕彎舉')) return '腕彎舉';
      if (_has(n, r'集中推舉|三頭|下壓')) return '三頭肌';
      return '二頭彎舉';
    case Dim.core:
      if (_has(n, r'捲腹|仰臥起坐|抬腿|抬膝|提膝|V字|Ｖ字|由下而上伸展')) return '核心捲腹抬腿';
      return '核心轉體側彎';
    case Dim.legs:
      if (_has(n, r'腿部推蹬|腿部推蹲|推蹬|小腿推蹬')) return '腿推';
      if (_has(n, r'提踵|提腫')) return '提踵';
      if (_has(n, r'臀橋|臀推|臀腿|蛙式|提髖')) return '臀橋臀推';
      if (_has(n, '硬舉')) return '硬舉';
      if (_has(n, r'弓箭步|分腿|登階|保加利亞')) return '弓步單腿';
      if (_has(n, r'深蹲|前蹲|哈克|坐站|蹲')) return '深蹲';
      return '腿孤立';
  }
}

/// 一個動作在標準情境下的「類別、單組重量、目標分數」。
({String label, double weight, int target}) _standard(Exercise e) {
  if (e.isBodyweight) {
    final w = _bw * e.bodyweightFactor; // 不加外加負重
    if (_lowGroup.contains(e.name)) {
      return (label: '沒拿東西的徒手孤立', weight: w, target: _scoreLow);
    }
    if (e.equipment.contains('彈力繩')) {
      return (label: '彈力繩', weight: w, target: _scoreBand);
    }
    return (label: '徒手', weight: w, target: _scoreC);
  }
  final g = _group(e);
  if (g == '壺') {
    final base = e.name.split(' · ').first;
    return (
      label: '壺鈴',
      weight: _kettlebell[base] ?? _kettlebellDefault,
      target: _scoreC
    );
  }
  final pat = _pattern(e);
  final w = _novice[pat]?[g];
  if (w == null) {
    throw StateError('沒有新手標準重量：${e.name}（$pat，器材群 $g）');
  }
  return (label: '$pat・$g', weight: w, target: _scoreC);
}

int _score(Exercise e, double weight) => measuredScore(
    weightKg: weight,
    reps: 10,
    relativeIntensity: e.relativeIntensity,
    bodyweightKg: _bw,
    isMale: true);

List<Exercise> get _all =>
    kPlatformExercises.where((e) => e.type == ExerciseType.strength).toList();

Exercise _byName(String name) =>
    kPlatformExercises.firstWhere((e) => e.name == name, orElse: () => throw StateError('動作庫沒有「$name」'));

/// 練一場只有一個動作的訓練，回傳那個動作所屬維度的「單組實測分數」。
int _measured(Exercise e, {double weight = 0, int reps = 10}) {
  final s = AppState(demo: false)
    ..resetToNewAccount()
    ..bodyweightKg = _bw;
  final plan = WorkoutPlan(
    id: 'p',
    name: 'p',
    source: PlanSource.privateCustom,
    exercises: [
      PlanExercise(
          exercise: e,
          planned: [PlannedSet(weight, reps), PlannedSet(weight, reps)])
    ],
  );
  s.beginWorkout(plan);
  if (e.isBodyweight && weight > 0) s.setAddedLoad(e, true);
  for (var i = 0; i < 2; i++) {
    s.editCurrentSet(weight: weight, reps: reps);
    s.completeCurrentSet();
    s.advanceDemoClock(const Duration(seconds: 40));
  }
  s.backdateSession(const Duration(minutes: 10));
  final r = s.finishWorkout(EndKind.completed);
  return r.measured[e.dim!]!;
}

void main() {
  group('標準情境基準表（體重 70 kg 男性、10 下）', () {
    test('每個動作都落在所屬類別的目標分數（±$_tolerance）', () {
      final off = <String>[];
      final table = <String, List<int>>{};
      for (final e in _all) {
        final s = _standard(e);
        final got = _score(e, s.weight);
        (table[s.label] ??= []).add(got);
        if ((got - s.target).abs() > _tolerance) {
          off.add('${e.name}（${s.label}）目標 ${s.target} 實得 $got');
        }
      }
      // 基準表：每一類的分數範圍。紅燈時看這張最快。
      final lines = [
        for (final k in table.keys.toList()..sort())
          '$k：${table[k]!.length} 個，${table[k]!.reduce((a, b) => a < b ? a : b)}'
              '～${table[k]!.reduce((a, b) => a > b ? a : b)}',
      ];
      // ignore: avoid_print
      print(lines.join('\n'));
      expect(off, isEmpty,
          reason: '共 ${off.length} 個偏離，前 15 個：\n${off.take(15).join('\n')}');
    });

    test('各目標分數有幾個動作（分類悄悄漂移會在這裡紅）', () {
      final count = <int, int>{};
      for (final e in _all) {
        final t = _standard(e).target;
        count[t] = (count[t] ?? 0) + 1;
      }
      expect(_all.length, 505);
      expect(count[_scoreLow], 13, reason: '沒拿東西的徒手孤立');
      expect(count[_scoreBand], 69, reason: '彈力繩');
      expect(count[_scoreC], 505 - 13 - 69);
    });

    test('標準情境下沒有任何動作到頂（999），也沒有只剩 10 分的', () {
      for (final e in _all) {
        final got = _score(e, _standard(e).weight);
        expect(got, lessThan(999), reason: '${e.name} 到頂');
        expect(got, greaterThan(10), reason: '${e.name} 只有 10 分');
      }
    });

    test('徒手動作不加負重：最高就是 C 級，不會比槓鈴臥推 40 kg 高', () {
      final bench = _score(
          _byName('板凳臥推 · 槓鈴'), 40); // 對照基準：新手槓鈴臥推
      for (final e in _all.where((x) => x.isBodyweight)) {
        expect(_score(e, _bw * e.bodyweightFactor),
            lessThanOrEqualTo(bench + _tolerance),
            reason: e.name);
      }
    });
  });

  group('資料本身', () {
    test('彈力繩動作都是徒手型：不用使用者猜要填幾公斤', () {
      final bands = _all.where((e) => e.equipment.contains('彈力繩'));
      expect(bands.length, 69);
      for (final e in bands) {
        expect(e.isBodyweight, isTrue, reason: e.name);
      }
    });

    test('13 個沒拿東西的徒手孤立動作都有，且是徒手型', () {
      for (final n in _lowGroup) {
        final e = _byName(n);
        expect(e.isBodyweight, isTrue, reason: n);
        expect(e.type, ExerciseType.strength, reason: '不改標有氧');
      }
    });

    test('椅子坐站是徒手動作', () {
      expect(_byName('椅子坐站').isBodyweight, isTrue);
    });

    test('部位歸錯的 4 個動作已改正', () {
      expect(_byName('架上推舉 · 槓鈴').dim, Dim.shoulders);
      expect(_byName('火箭推 · 槓鈴').dim, Dim.shoulders);
      expect(_byName('火箭推 · 壺鈴').dim, Dim.shoulders);
      expect(_byName('繩索髖屈伸').dim, Dim.legs);
      // 全身動作維持歸腿
      expect(_byName('抓舉 · 槓鈴').dim, Dim.legs);
    });
  });

  group('走完整個結算流程（AppState.finishWorkout）', () {
    test('槓鈴臥推 40 kg 是基準 294', () {
      expect(_measured(_byName('板凳臥推 · 槓鈴'), weight: 40),
          closeTo(_scoreC, _tolerance));
    });

    test('啞鈴臥推每手 14 kg 也是 294（以前只有 10）', () {
      expect(_measured(_byName('板凳臥推 · 啞鈴'), weight: 14),
          closeTo(_scoreC, _tolerance));
    });

    test('壺鈴硬舉 16 kg 是 294（以前只有 10）', () {
      expect(_measured(_byName('硬舉 · 壺鈴'), weight: 16),
          closeTo(_scoreC, _tolerance));
    });

    test('徒手伏地挺身、捲腹、引體向上、深蹲、提踵不加負重都是 294（以前 639／999／999／63／10）', () {
      for (final n in ['伏地挺身', '捲腹', '引體向上', '深蹲', '站姿提踵']) {
        expect(_measured(_byName(n)), closeTo(_scoreC, _tolerance), reason: n);
      }
    });

    test('彈力繩約 150（徒手型，重量欄鎖住、不用猜公斤數）', () {
      expect(_measured(_byName('站姿胸推 · 彈力帶')), closeTo(_scoreBand, _tolerance));
      expect(_measured(_byName('二頭肌屈臂 · 彈力帶')), closeTo(_scoreBand, _tolerance));
    });

    test('沒拿東西的徒手孤立動作約 50', () {
      expect(_measured(_byName('前平舉')), closeTo(_scoreLow, _tolerance));
      expect(_measured(_byName('手臂繞圈')), closeTo(_scoreLow, _tolerance));
    });

    test('徒手加外加負重：引體向上 +10 kg ≈ 376、深蹲 +10 kg ≈ 431（照槓鈴同樣的算法加上去；'
        '2026-10-19 重新校準前是 429／519）', () {
      expect(_measured(_byName('引體向上'), weight: 10), closeTo(376, 3));
      expect(_measured(_byName('深蹲'), weight: 10), closeTo(431, 3));
    });
  });

  group('建議起始重量跟著係數走', () {
    int pointsFor(Exercise e) => e.dim == Dim.legs || e.dim == Dim.core ? 30 : 10;
    double suggested(Exercise e) => suggestedWeight(
        exercise: e,
        dimPoints: pointsFor(e),
        bodyweightKg: _bw,
        isMale: true,
        targetReps: 10);

    test('新帳號的啞鈴不再被建議重到每手 27.5／40 kg', () {
      // 以前：啞鈴臥推 27.5、啞鈴深蹲 40、壺鈴硬舉 45（係數沒分器材）
      expect(suggested(_byName('板凳臥推 · 啞鈴')), lessThanOrEqualTo(12.5));
      expect(suggested(_byName('深蹲 · 啞鈴')), lessThanOrEqualTo(15));
      expect(suggested(_byName('硬舉 · 壺鈴')), lessThanOrEqualTo(15));
    });

    test('徒手與彈力繩不建議重量（0）', () {
      expect(suggested(_byName('伏地挺身')), 0);
      expect(suggested(_byName('站姿胸推 · 彈力帶')), 0);
    });

    test('槓鈴臥推新帳號還是從輕的開始（不超過新手標準 40 kg）', () {
      final w = suggested(_byName('板凳臥推 · 槓鈴'));
      expect(w, greaterThan(0));
      expect(w, lessThan(40));
    });
  });
}
