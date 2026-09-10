import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_app/design/tokens.dart';

// --- 依 UI 設計規格書 §4.3 與分類色票的驗證方法重算 ---

double _s2lin(double c) =>
    c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

List<double> _lin(Color c) => [
      _s2lin(((c.toARGB32() >> 16) & 0xFF) / 255),
      _s2lin(((c.toARGB32() >> 8) & 0xFF) / 255),
      _s2lin((c.toARGB32() & 0xFF) / 255),
    ];

double _lum(Color c) {
  final l = _lin(c);
  return 0.2126 * l[0] + 0.7152 * l[1] + 0.0722 * l[2];
}

double contrast(Color a, Color b) {
  final x = _lum(a), y = _lum(b);
  final hi = math.max(x, y), lo = math.min(x, y);
  return (hi + 0.05) / (lo + 0.05);
}

List<double> _oklab(List<double> rgb) {
  final l = math.pow(
      0.4122214708 * rgb[0] + 0.5363325363 * rgb[1] + 0.0514459929 * rgb[2],
      1 / 3).toDouble();
  final m = math.pow(
      0.2119034982 * rgb[0] + 0.6806995451 * rgb[1] + 0.1073969566 * rgb[2],
      1 / 3).toDouble();
  final s = math.pow(
      0.0883024619 * rgb[0] + 0.2817188376 * rgb[1] + 0.6299787005 * rgb[2],
      1 / 3).toDouble();
  return [
    0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
    1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
    0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s,
  ];
}

const _machado = {
  'protan': [
    [0.152286, 1.052583, -0.204868],
    [0.114503, 0.786281, 0.099216],
    [-0.003882, -0.048116, 1.051998],
  ],
  'deutan': [
    [0.367322, 0.860646, -0.227968],
    [0.280085, 0.672501, 0.047413],
    [-0.011820, 0.042940, 0.968881],
  ],
};

List<double> _sim(Color c, String kind) {
  final l = _lin(c), m = _machado[kind]!;
  return List.generate(
      3,
      (i) => (m[i][0] * l[0] + m[i][1] * l[1] + m[i][2] * l[2])
          .clamp(0.0, 1.0));
}

double deltaE(Color a, Color b, [String? kind]) {
  final x = _oklab(kind == null ? _lin(a) : _sim(a, kind));
  final y = _oklab(kind == null ? _lin(b) : _sim(b, kind));
  return 100 *
      math.sqrt(math.pow(x[0] - y[0], 2) +
          math.pow(x[1] - y[1], 2) +
          math.pow(x[2] - y[2], 2));
}

void main() {
  group('§4.3 對比度底線', () {
    test('一般文字在頁面底 ≥ 4.5:1', () {
      expect(contrast(C.textPrimary, C.bgPage), greaterThanOrEqualTo(4.5));
      expect(contrast(C.textSecondary, C.bgPage), greaterThanOrEqualTo(4.5));
    });

    test('【必須】CTA 與成功色上的文字一律用 text/on-accent（深色）', () {
      // 白字在橘黃上僅 2.03:1、在薄荷上僅 1.77:1，皆不合格
      expect(contrast(C.textOnAccent, C.actionPrimary),
          greaterThanOrEqualTo(4.5));
      expect(contrast(C.textOnAccent, C.statusSuccess),
          greaterThanOrEqualTo(4.5));
      expect(contrast(C.textOnDark, C.actionPrimary), lessThan(4.5),
          reason: '白字在橘黃上不合格，這是為何規定用深色字');
    });

    test('錯誤色在卡片底 ≥ 4.5:1', () {
      expect(contrast(C.statusError, C.bgSurface), greaterThanOrEqualTo(4.5));
    });

    test('v0.8：資訊沿用中性色，不另設輔助色', () {
      expect(C.accentInfo, C.textSecondary);
      expect(contrast(C.accentInfo, C.bgPage), greaterThanOrEqualTo(4.5));
    });
  });

  group('§4.1a 等級色階（v0.8 甲案）', () {
    // v0.8 起本色階不再是「序列色階」，而是**依色相排序的等級色階**：
    // S 紅 → A 橙 → B 黃 → C 綠 → D 青 → E 深藍（使用者指定）。
    // 因此明度不再單調，序列色階的判準（明度遞減、相鄰 ΔL）已不適用；
    // 改用分類色的判準：全配對分離、對比、與語意色的距離。

    test('六階互不相同，且順序為 E→S', () {
      expect(C.gradeScale.length, 6);
      expect(C.gradeScale.toSet().length, 6);
      expect(C.gradeScale.first, C.gradeE);
      expect(C.gradeScale.last, C.gradeS);
    });

    test('【必須】每一階都有對比 ≥ 4.5 的前景色', () {
      for (final g in ['E', 'D', 'C', 'B', 'A', 'S']) {
        final c = contrast(C.gradeOn(g), C.gradeFill(g));
        expect(c, greaterThanOrEqualTo(4.5), reason: '$g 階前景僅 $c');
      }
    });

    test('色相順序為 S 紅 → E 藍（暖到冷）', () {
      double hue(Color c) {
        final o = _oklab(_lin(c));
        var h = math.atan2(o[2], o[1]) * 180 / math.pi;
        if (h < 0) h += 360;
        return h;
      }
      // S 落在紅區、E 落在藍區
      expect(hue(C.gradeS), inInclusiveRange(10, 45));
      expect(hue(C.gradeE), inInclusiveRange(240, 275));
    });

    // ---- 以下三項為已裁決接受的豁免。測試「鎖住現況」而非「要求合規」，
    //      任何改動都會使數字漂移並讓測試失敗，屆時須重新裁決。----

    test('豁免一：僅 B 對頁底不足 3.0，且必須補外框', () {
      for (final g in ['E', 'D', 'C', 'B', 'A', 'S']) {
        final low = contrast(C.gradeFill(g), C.bgPage) < 3.0;
        expect(C.gradeNeedsOutline(g), low,
            reason: '$g 階的外框需求與其對比不符');
      }
      // 目前只有 B 落在豁免範圍
      expect(C.gradeNeedsOutline('B'), isTrue);
      expect(
          ['E', 'D', 'C', 'A', 'S'].where(C.gradeNeedsOutline), isEmpty);
    });

    test('豁免二：色盲全配對 ΔE 落在 4–6，靠字母承擔辨識', () {
      var worst = 999.0;
      for (var i = 0; i < C.gradeScale.length; i++) {
        for (var j = i + 1; j < C.gradeScale.length; j++) {
          for (final k in ['protan', 'deutan']) {
            worst = math.min(worst, deltaE(C.gradeScale[i], C.gradeScale[j], k));
          }
        }
      }
      // 低於 6.0 底線為已知並接受；但不得再惡化到 4 以下
      expect(worst, greaterThanOrEqualTo(4.0));
      expect(worst, lessThan(6.0),
          reason: '若已高於 6.0，代表色階被改過，豁免說明應一併移除');
    });

    test('豁免三：正常視覺全配對 ΔE ≥ 12', () {
      var worst = 999.0;
      for (var i = 0; i < C.gradeScale.length; i++) {
        for (var j = i + 1; j < C.gradeScale.length; j++) {
          worst = math.min(worst, deltaE(C.gradeScale[i], C.gradeScale[j]));
        }
      }
      expect(worst, greaterThanOrEqualTo(12.0));
    });

    test('豁免三：與語意色的距離不得再縮小', () {
      const sem = [C.actionPrimary, C.statusSuccess, C.statusError];
      var worst = 999.0;
      for (final g in C.gradeScale) {
        for (final s in sem) {
          worst = math.min(worst, deltaE(g, s));
        }
      }
      // B ↔ CTA 金為目前最近的一對（ΔE 7.3）
      expect(worst, greaterThanOrEqualTo(7.0));
    });
  });

  group('§4.1 顏色的職責分離', () {
    test('【必須】資訊色不得等於 CTA 色', () {
      expect(C.accentInfo, isNot(C.actionPrimary));
    });

    test('【必須】導覽選中態不得用 action/primary', () {
      expect(C.navActive, isNot(C.actionPrimary));
    });

    test('等級色不得與狀態色或 CTA 重複', () {
      for (final c in C.gradeScale) {
        expect(c, isNot(C.statusSuccess));
        expect(c, isNot(C.statusError));
        expect(c, isNot(C.actionPrimary));
      }
    });

    test('v0.8：成功色淡底本身看不出邊界，故必須搭配虛線框', () {
      // 對頁底僅 1.11 —— 這個數字就是「虛線框不是裝飾」的理由
      expect(contrast(C.statusSuccessTint, C.bgPage), lessThan(1.5));
      // 但其上的文字必須清楚
      expect(contrast(C.textOnAccent, C.statusSuccessTint),
          greaterThanOrEqualTo(4.5));
    });

    test('v0.6：次要動作與導覽選中態為品牌深藍，不再是近黑', () {
      expect(C.actionOutline, C.accentDeep);
      expect(C.navActive, C.accentDeep);
      expect(contrast(C.actionOutline, C.bgSurface), greaterThanOrEqualTo(4.5));
    });
  });

  group('填色上的前景色', () {
    // 由來：商品詳情頁被選中的規格用深藍底配墨字，對比 1.15:1，整塊看不見。
    // 同一個錯也在 TagBadge 裡 —— 它一律用 textOnAccent，
    // 而那個 token 的定義是「橘黃、薄荷底上的文字」，深底本來就不適用。
    const fills = <String, Color>{
      '主要動作（橘黃）': C.actionPrimary,
      '次要動作／導覽選中（深藍）': C.actionOutline,
      '成功（薄荷）': C.statusSuccess,
      '成功淡底': C.statusSuccessTint,
      '錯誤': C.statusError,
      '警告': C.statusWarning,
    };

    test('每一種填色配 onFill 都達 4.5:1', () {
      fills.forEach((name, fill) {
        expect(contrast(C.onFill(fill), fill), greaterThanOrEqualTo(4.5),
            reason: '$name 上的前景色對比不足');
      });
    });

    test('onFill 挑的是對比較高的那一個，不是靠明度門檻', () {
      // 橘黃的相對明度 0.47 落在 0.5 以下，門檻法會判給白字（僅 2.3:1）。
      expect(C.onFill(C.actionPrimary), C.textOnAccent);
      expect(contrast(C.textOnDark, C.actionPrimary), lessThan(3.0));
      // 深藍則相反。
      expect(C.onFill(C.actionOutline), C.textOnDark);
      expect(contrast(C.textOnAccent, C.actionOutline), lessThan(1.5),
          reason: '這 1.x:1 就是那塊看不見的規格卡');
    });
  });
}
