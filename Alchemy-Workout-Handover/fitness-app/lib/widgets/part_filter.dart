import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../design/typography.dart';

/// 訓練部位的篩選列（**只有動作那一側在用**）。
///
/// ## 為什麼課表頁沒有用它
///
/// 2026-09-28 使用者要求課表頁也能依部位篩，我把這個元件抽出來想共用。
/// 使用者看了截圖回報：「**能不能跟上面的篩選欄一樣**」——
/// 課表頁的器材／經驗／時長是「白面板 ＋ 左側標題 ＋ 一排鍵」，
/// 而這個元件是「標題列 ＋ 圓角鍵」。兩種樣式擺在同一頁就是不一致。
///
/// 所以課表頁的部位篩選是它自己那個 `_Filters` 的第四排，
/// 不是這個元件。**一頁之內只該有一種篩選列。**
///
/// 留著這一份是因為動作那一側還在用它，不是因為它被共用了 ——
/// 想「統一」兩邊之前請先看這段：那會把課表頁的版面弄回不一致。
///
/// 兩邊唯一要保持一致的是測試接縫 `ValueKey('part-…')`，
/// 課表頁的 `_Filters._row` 也用同一組鍵名。
class PartFilterBar extends StatelessWidget {
  final List<String> parts;
  final String? picked;
  final ValueChanged<String?> onPick;

  const PartFilterBar({
    super.key,
    required this.parts,
    required this.picked,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.accessibility_new_rounded,
                  size: 15, color: C.textSecondary),
              const SizedBox(width: 6),
              Text(picked == null ? '部位：全部' : '部位：$picked',
                  style: T.caption()),
            ],
          ),
          const SizedBox(height: S.sm),
          Wrap(
            spacing: S.sm,
            runSpacing: S.sm,
            children: [
              // key 是測試接縫：鍵面文字在動作與課表名稱裡也找得到
              // （「腿」對上「俯臥屈腿 · 啞鈴」、「無器材-腿部」），
              // 用文字定位會一次命中十幾個。
              _chip('全部', picked == null, () => onPick(null),
                  key: const ValueKey('part-all')),
              for (final k in parts)
                _chip(k, picked == k, () => onPick(k), key: ValueKey('part-$k')),
            ],
          ),
        ],
      );

  Widget _chip(String text, bool on, VoidCallback onTap, {required Key key}) =>
      GestureDetector(
        key: key,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: S.md, vertical: 6),
          decoration: BoxDecoration(
            color: on ? C.actionOutline : C.bgSurface,
            borderRadius: BorderRadius.circular(R.child),
            border: Border.all(color: on ? C.actionOutline : C.lineDivider),
          ),
          child: Text(
            text,
            style: T.caption(color: on ? C.textOnDark : C.textPrimary),
          ),
        ),
      );
}
