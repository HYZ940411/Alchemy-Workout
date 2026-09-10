// 新帳號的第一場，要真的算成第一場。
//
// 使用者回報「完成一組板凳臥推卻沒有任何能力提升」。查下來那一組
// 27.5 kg × 8（體重 65 kg）實測 10 分，恰等於當時的胸 10 點 ——
// 沒有提升在算術上是對的。但順著查出 [AppState.resetToNewAccount]
// 漏了兩個欄位：[trainedDims] 與 [pending]。
//
// 漏掉的後果不是小事：新帳號會宣稱六維全都練過，於是每一維真正的
// 第一場都走「非首場」那條路 —— 首場可直接跳到實測值（上限 450），
// 非首場只能爬到下一個節點的上緣。實測 296 分的第一場只給到 69。

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/ability.dart';
import 'package:fitness_app/state/app_state.dart';

void main() {
  group('新帳號的能力值 Aggregate 整份歸零', () {
    test('六維點數、待兌現、已訓練維度三者一起清', () {
      final s = AppState();
      expect(s.trainedDims, isNotEmpty, reason: '前提：假資料確實六維都練過');
      s.pending[Dim.chest] = 500;

      s.resetToNewAccount();
      expect(s.trainedDims, isEmpty,
          reason: '零次訓練的帳號不該宣稱哪一維練過');
      expect(s.pending.values.every((v) => v == 0), isTrue,
          reason: '上一個帳號的待兌現分數不該跟著過來');
      for (final d in Dim.values) {
        expect(s.points[d], s.initialOf(d));
      }
    });

    test('第一場走的是「首場」那條路', () {
      final s = AppState()..resetToNewAccount();
      final g = applySessionGain(
        current: s.points[Dim.chest]!,
        measured: 296,
        pending: s.pending[Dim.chest]!,
        isFirstSessionForDim: !s.trainedDims.contains(Dim.chest),
      );
      expect(g.newPoints, 296,
          reason: '首場直接對齊實測值；走成非首場只會給到 69');
    });

    test('第二場之後才受節點上緣限制', () {
      final s = AppState()..resetToNewAccount();
      s.trainedDims.add(Dim.chest);
      final g = applySessionGain(
        current: s.points[Dim.chest]!,
        measured: 296,
        pending: 0,
        isFirstSessionForDim: false,
      );
      expect(g.newPoints, lessThan(296),
          reason: '非首場一次只跨一個節點 —— 這條規則本身是對的');
    });
  });

  group('載入既有存檔時的修復', () {
    test('沒有訓練證據的維度會被移除', () {
      final s = AppState();
      final j = AppState().toSnapshot();
      // 假資料的歷史涵蓋六維，先確認正常存檔不會被誤刪。
      expect(s.applySnapshot(j), isTrue);
      expect(s.trainedDims, hasLength(Dim.values.length),
          reason: '有證據的維度不該被清掉');
    });

    test('零筆歷史的帳號，六維全部清空', () {
      final s = AppState();
      final j = AppState().toSnapshot();
      j['history'] = <dynamic>[];
      j['trainedDims'] = [for (final d in Dim.values) d.name];
      expect(s.applySnapshot(j), isTrue);
      expect(s.trainedDims, isEmpty);
      expect(s.pending.values.every((v) => v == 0), isTrue);
    });

    test('只練過胸的存檔，只留下胸', () {
      final s = AppState();
      final j = AppState().toSnapshot();
      final hist = (j['history'] as List);
      // 只留下含臥推的那些
      j['history'] = [
        for (final h in hist)
          if ((h as Map)['exercises'] is List &&
              (h['exercises'] as List).any((e) => (e as Map)['id'] == 'bench'))
            {
              ...h,
              'exercises': [
                for (final e in h['exercises'] as List)
                  if ((e as Map)['id'] == 'bench') e
              ],
            }
      ];
      j['trainedDims'] = [for (final d in Dim.values) d.name];
      expect(s.applySnapshot(j), isTrue);
      expect((j['history'] as List), isNotEmpty,
          reason: '前提：篩完要還有臥推的紀錄，否則這個測試是空的');
      expect(s.trainedDims, {Dim.chest});
    });

    test('修復只移除、不新增', () {
      final s = AppState();
      final j = AppState().toSnapshot();
      j['trainedDims'] = <String>[]; // 存檔說一維都沒練過
      expect(s.applySnapshot(j), isTrue);
      expect(s.trainedDims, isEmpty,
          reason: '歷史有證據也不補 —— 存檔說沒有就是沒有');
    });

    test('修復不會動到 pending 裡有證據的那些', () {
      final s = AppState();
      final j = AppState().toSnapshot();
      j['pending'] = {for (final d in Dim.values) d.name: 500};
      expect(s.applySnapshot(j), isTrue);
      expect(s.pending[Dim.chest], 500,
          reason: '胸有訓練證據，它的待兌現分數不該被清');
    });
  });

  group('那一組臥推本身', () {
    test('27.5 kg × 8、體重 65 kg 的男性，實測就是 10 分', () {
      final m = measuredScore(
        weightKg: 27.5,
        reps: 8,
        relativeIntensity: 1.0,
        bodyweightKg: 65,
        isMale: true,
      );
      expect(m, 10, reason: '量表滿分 999，這個負重落在最底端');
    });

    test('同一動作加到 40 kg 就推得動了', () {
      final m = measuredScore(
        weightKg: 40,
        reps: 8,
        relativeIntensity: 1.0,
        bodyweightKg: 65,
        isMale: true,
      );
      expect(m, greaterThan(10));
    });
  });
}
