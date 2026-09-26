import 'package:flutter/material.dart';

import '../design/typography.dart';
import '../mock/mock_equipment.dart';
import '../theme.dart';

/// 器材篩選 —— 列舉複選。全部取消即為不篩選。
///
/// **動作庫與「加入動作至本次訓練」共用這一條。**
/// 原本它是動作庫頁的私有 widget，於是訓練中的動作選擇抽屜
/// 沒有篩選可用 —— 使用者回報想要。判準那一半見 `exerciseMatchesFilter`。
class EquipmentFilterBar extends StatelessWidget {
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  final VoidCallback? onClear;
  const EquipmentFilterBar({
    super.key,
    required this.selected,
    required this.onToggle,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.tune_rounded,
                  size: 15, color: AppColors.textDim),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  selected.isEmpty
                      ? '器材篩選：全部動作'
                      : '器材篩選：${selected.length} 項',
                  style: T.caption(),
                ),
              ),
              if (onClear != null)
                GestureDetector(
                  onTap: onClear,
                  child: Text('清除', style: T.caption(color: C.actionOutline)),
                ),
            ],
          ),
          const SizedBox(height: S.sm),
          SizedBox(
            height: 32,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: kEquipmentItems.length,
              separatorBuilder: (_, _) => const SizedBox(width: S.sm),
              itemBuilder: (_, i) {
                final item = kEquipmentItems[i];
                final on = selected.contains(item);
                return GestureDetector(
                  onTap: () => onToggle(item),
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: S.md),
                    decoration: BoxDecoration(
                      color: on ? C.actionOutline : C.bgSurface,
                      borderRadius: BorderRadius.circular(R.child),
                      border: Border.all(
                          color: on ? C.actionOutline : C.lineDivider),
                    ),
                    child: Text(
                      item,
                      style: T.caption(
                          color: on ? C.textOnDark : C.textPrimary),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      );
}
