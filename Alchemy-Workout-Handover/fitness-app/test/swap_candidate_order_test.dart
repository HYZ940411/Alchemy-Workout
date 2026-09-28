// 換動作的候選要先看「練的是不是同一塊肌肉」，再看強度。
//
// 2026-09-28 使用者打「今天沒有滑輪機可以用」，模型把
// **三頭肌下壓 · 滑輪機** 換成 **二頭肌屈臂 · 槓鈴** —— 推變成拉。
//
// 這不是模型亂挑：候選清單是我們給的，而**送過去的前五個全是二頭**。
// 六維裡「手」是一維，三頭與二頭同屬 `Dim.arms`（依模型自己的粒度
// 那確實是同肌群），而排序只比相對強度 —— 二頭 2.1、三頭 2.2、
// 原動作 1.9。**差 0.1 就讓三頭訓練變成二頭訓練。**
// 候選池裡本來有 16 個三頭動作，一個都沒進前五。

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/platform_config.dart';
import 'package:fitness_app/mock/mock_data.dart';
import 'package:fitness_app/state/app_state.dart';

void main() {
  setUp(platformConfig.reset);
  tearDown(platformConfig.reset);

  String base(String name) => name.split(' · ').first;

  group('三頭肌下壓的候選不會全是二頭', () {
    test('送給模型的每一個都是三頭動作', () {
      final got = AppState().swapCandidatesFor(ex('pushdown'));
      expect(got, isNotEmpty);
      for (final c in got) {
        expect(c.name, contains('三頭'),
            reason: '「${c.name}」不是三頭動作，卻進了前 ${got.length} 名');
      }
    });

    // **這個啟發式有已知的漏網之魚，據實釘在這裡。**
    // 「三頭肌後屈伸」與「三頭肌下壓」二字重疊 2（三頭、頭肌），
    // 但「仰臥肱三頭伸展」寫的是「肱三頭」不是「三頭肌」，只重疊 1 ——
    // 與「二頭肌屈臂」同分，於是靠強度分勝負。
    //
    // 所以這裡只保證「三頭肌」排在「二頭」前面，不保證每一個三頭動作
    // 都排在前面。真正乾淨的解法是動作庫多一個細部肌群欄位
    //（`PROGRESS.md` 0S），那是資料決策。
    test('名稱含「三頭肌」的排在「二頭」之前', () {
      final all = AppState().swapCandidatesFor(ex('pushdown'), limit: 999);
      final lastTri = all.lastIndexWhere((e) => e.name.contains('三頭肌'));
      final firstBi = all.indexWhere((e) => e.name.contains('二頭'));
      expect(lastTri, greaterThanOrEqualTo(0));
      expect(firstBi, greaterThanOrEqualTo(0));
      expect(lastTri, lessThan(firstBi));
    });
  });

  test('同一個動作換個器材排第一', () {
    final got = AppState().swapCandidatesFor(ex('bench'));
    expect(base(got.first.name), '板凳臥推',
        reason: '沒有槓鈴時，最自然的答案是同一個動作換個器材');
  });

  test('名稱一樣像時，仍照相對強度接近排序', () {
    final s = AppState();
    final src = ex('pushdown');
    final all = s.swapCandidatesFor(src, limit: 999);
    // 取出名稱相似度相同的一段，段內要照強度差遞增。
    for (var i = 1; i < all.length; i++) {
      final sameName = base(all[i - 1].name) == base(all[i].name);
      if (!sameName) continue;
      final a = (all[i - 1].relativeIntensity - src.relativeIntensity).abs();
      final b = (all[i].relativeIntensity - src.relativeIntensity).abs();
      expect(a, lessThanOrEqualTo(b),
          reason: '${all[i - 1].name} / ${all[i].name}');
    }
  });

  // 這個參數原本寫了沒用 —— 函式回傳全部，兩個呼叫端各自 take(5)。
  // 參數騙人比沒有參數更糟：它看起來已經把關了。
  group('limit 真的有作用', () {
    test('預設只回五個', () {
      expect(AppState().swapCandidatesFor(ex('pushdown')).length, 5);
    });

    test('指定幾個就回幾個', () {
      expect(AppState().swapCandidatesFor(ex('pushdown'), limit: 2).length, 2);
    });

    test('候選不足時回實際數量，不補空', () {
      final all = AppState().swapCandidatesFor(ex('pushdown'), limit: 9999);
      expect(all.length, lessThan(9999));
      expect(all.length, greaterThan(5));
    });
  });
}
