import 'package:flutter/material.dart';

import 'components.dart';
import 'tokens.dart';
import 'typography.dart';

/// 載入失敗（Figma E1／E2）
///
/// 版面與空狀態同一套（圖示 64 ／ H3 ／ Body 兩行 ／ 外框按鈕，垂直置中），
/// **差別只有兩處**：圖示為 `status/error` 的驚嘆號，且一定有「重新載入」。
///
/// E1（次層頁）與 E2（著陸頁）在版面上是同一個東西 —— 兩者的差異來自外殼：
/// 著陸頁保留底部導覽列、次層頁保留返回鍵。故本元件不分兩份。
///
/// 【必須】錯誤必須有文字，不可只靠紅色（P6 §2.5）：標題與說明都在，
/// 紅色只是輔助。
class ErrorState extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback onRetry;
  final String retryLabel;

  /// 次要出口。**預設沒有** —— §8.5 的錯誤頁只有「重新載入」一顆。
  ///
  /// 只有一種情況需要它：重試永遠不會成功、而使用者又必須進得去
  /// （例如存檔本身壞掉）。此時只給重試等於把人鎖在門外。
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  const ErrorState({
    super.key,
    this.title = '載入失敗',
    this.message = '網路好像不太穩，檢查連線後再試一次',
    required this.onRetry,
    this.retryLabel = '重新載入',
    this.secondaryLabel,
    this.onSecondary,
  });

  /// 著陸頁的文案 —— 整個分頁都空了，講的是連線本身，不是某一份清單。
  const ErrorState.landing({
    super.key,
    this.title = '暫時連不上',
    this.message = '資料載不出來，先檢查一下網路',
    required this.onRetry,
    this.retryLabel = '重新載入',
    this.secondaryLabel,
    this.onSecondary,
  });

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(S.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 64, color: C.statusError),
              const SizedBox(height: S.lg),
              Text(title, style: T.h3(), textAlign: TextAlign.center),
              const SizedBox(height: S.sm),
              Text(message,
                  style: T.body(color: C.textSecondary),
                  textAlign: TextAlign.center,
                  maxLines: secondaryLabel == null ? 2 : 5),
              const SizedBox(height: S.lg),
              // 寬度依內容，最小 120（§8.5）。
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 120),
                child: IntrinsicWidth(
                  child: AppButton(
                    label: retryLabel,
                    kind: BtnKind.secondary,
                    onPressed: onRetry,
                  ),
                ),
              ),
              if (secondaryLabel != null) ...[
                const SizedBox(height: S.md),
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 120),
                  child: IntrinsicWidth(
                    child: AppButton(
                      label: secondaryLabel!,
                      kind: BtnKind.secondary,
                      onPressed: onSecondary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
}
