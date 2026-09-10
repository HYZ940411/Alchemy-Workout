import 'package:flutter/material.dart';

import '../../domain/models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// 「本次訓練器材已解鎖」——快照產生後系統自動比對器材明細，
/// 有動作做不了就解鎖本次訓練的全部器材。
///
/// **沒有「否」的分支**：使用者選了健身房課表即代表他今天在健身房；
/// 若容許否認，系統就得把整份健身房課表換成居家課表，那已不是同一份課表。
///
/// 「套用至未來所有訓練」**預設不勾**：使用者可能只是今天借用場地，
/// 系統自行寫回會使其後的課表推薦與動作庫篩選全部跟著錯，而他不會知道系統改過。
Future<void> showEquipmentUnlockSheet(BuildContext context) async {
  final s = AppScope.of(context);
  final blocked = s.unavailableExercises();
  if (blocked.isEmpty) return;
  final missing = s.missingEquipment();

  final applyToFuture = await showAppSheet<bool>(
    context,
    title: '本次訓練器材已解鎖',
    child: _Body(blocked: blocked, missing: missing),
  );
  if (applyToFuture == null) {
    // 抽屜被滑掉也視為解鎖 —— 解鎖無「否」的分支，只有要不要寫回的差別。
    s.unlockSessionEquipment();
    return;
  }
  s.unlockSessionEquipment(applyToFuture: applyToFuture);
}

class _Body extends StatefulWidget {
  final List<PlanExercise> blocked;
  final Set<String> missing;
  const _Body({required this.blocked, required this.missing});
  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  bool apply = false; // 預設不勾選

  @override
  Widget build(BuildContext context) {
    final names = widget.blocked.map((e) => e.exercise.name).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '這份課表有 ${names.length} 個動作用到你沒登記的器材，'
          '本次訓練已把全部器材視為可用。',
          style: T.body(),
        ),
        const SizedBox(height: S.md),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final n in names.take(5))
                Padding(
                  padding: const EdgeInsets.only(bottom: S.xs),
                  child: Text(n, style: T.body(color: C.textSecondary)),
                ),
              if (names.length > 5)
                Text('…等 ${names.length} 個', style: T.caption()),
              const Divider(height: S.lg, color: C.lineDivider),
              Text(
                '缺少的器材：${widget.missing.join('、')}',
                style: T.caption(),
              ),
            ],
          ),
        ),
        const SizedBox(height: S.md),
        // 【必須】預設不勾選。
        InkWell(
          onTap: () => setState(() => apply = !apply),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppCheckbox(
                value: apply,
                onChanged: (v) => setState(() => apply = v),
              ),
              const SizedBox(width: S.xs),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: S.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('套用至未來所有訓練', style: T.body()),
                      const SizedBox(height: 2),
                      Text(
                        apply
                            ? '會把 ${widget.missing.join('、')} 寫進你的持有器材明細，'
                                '之後的課表推薦與動作庫篩選都會跟著改。'
                            : '不勾選的話，這次解鎖只對本次訓練有效，'
                                '訓練結束就失效，你的設定不會被改動。',
                        style: T.caption(),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: S.md),
        AppButton(
          label: '知道了，開始訓練',
          onPressed: () => Navigator.of(context).pop(apply),
        ),
        const SizedBox(height: S.md),
      ],
    );
  }
}
