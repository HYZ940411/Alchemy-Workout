import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../design/typography.dart';

/// 訓練部位的篩選列（動作與課表共用）。
///
/// 原本只長在「加入動作至本次訓練」那一頁（`exercise_picker.dart`）。
/// 2026-09-28 使用者要求課表頁也要能依部位篩 —— **抽出來共用而不是
/// 再寫一份**：兩處的鍵面、選取樣式、`ValueKey` 測試接縫都要一樣，
/// 而「同一個東西寫在兩個地方」是這個專案最常出事的形狀。
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
