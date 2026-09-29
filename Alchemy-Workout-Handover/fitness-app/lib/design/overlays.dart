import 'package:flutter/material.dart';

import 'components.dart';
import 'tokens.dart';
import 'typography.dart';

/// 三種容器的使用時機（§5.7）【必須】
/// - 需要選東西 → 底部抽屜
/// - 需要確認或警告 → 彈窗
/// - 只是告知結果 → Toast

enum DialogSize { small, medium, large }

const _dialogWidth = {
  DialogSize.small: 280.0,
  DialogSize.medium: 312.0,
  DialogSize.large: 340.0,
};
const _dialogRadius = {
  DialogSize.small: R.card,
  DialogSize.medium: R.dialogM,
  DialogSize.large: R.dialogL,
};
const _dialogMinHeight = {
  DialogSize.small: 176.0,
  DialogSize.medium: 260.0,
  DialogSize.large: 320.0,
};

/// 確認類彈窗。標題固定在上、按鈕列固定在下，只有中間內容區捲動。
/// 【必須】任何情況下使用者都必須看得到底部按鈕。
Future<bool?> showAppDialog(
  BuildContext context, {
  required String title,
  String? message,
  Widget? content,
  IconData? icon,
  String confirmLabel = '確定',
  String cancelLabel = '取消',
  DialogSize size = DialogSize.small,

  /// 破壞性動作仍用次要樣式（§4.5 R-23），安全由本彈窗承擔。
  bool destructive = false,
}) {
  return showDialog<bool>(
    context: context,
    barrierColor: C.overlay,
    builder: (ctx) {
      final media = MediaQuery.of(ctx);
      // 可視高度 ＝ 螢幕高 − 鍵盤高
      final visible = media.size.height - media.viewInsets.bottom;
      return Center(
        child: Padding(
          padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
          child: Material(
            color: C.bgSurface,
            borderRadius: BorderRadius.circular(_dialogRadius[size]!),
            child: Container(
              width: _dialogWidth[size],
              constraints: BoxConstraints(
                minHeight: _dialogMinHeight[size]!,
                maxHeight: visible * 0.8,
              ),
              padding: const EdgeInsets.all(S.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 64, color: C.actionPrimary),
                    const SizedBox(height: S.base),
                  ],
                  Text(title,
                      style: size == DialogSize.small ? T.h3() : T.h2(),
                      textAlign: TextAlign.center),
                  const SizedBox(height: S.sm),
                  // 只有中間內容區捲動
                  Flexible(
                    child: SingleChildScrollView(
                      child: content ??
                          Text(
                            message ?? '',
                            style: T.body(color: C.textSecondary),
                            textAlign: TextAlign.center,
                          ),
                    ),
                  ),
                  const SizedBox(height: S.lg),
                  ButtonRow(
                    left: AppButton(
                      label: cancelLabel,
                      kind: BtnKind.secondary,
                      onPressed: () => Navigator.pop(ctx, false),
                    ),
                    right: AppButton(
                      label: confirmLabel,
                      // 破壞性動作不給最顯眼的樣式
                      kind: destructive ? BtnKind.secondary : BtnKind.primary,
                      onPressed: () => Navigator.pop(ctx, true),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// 底部抽屜 —— 用於「需要選東西」。
Future<R2?> showAppSheet<R2>(
  BuildContext context, {
  required String title,
  required Widget child,
}) {
  return showModalBottomSheet<R2>(
    context: context,
    backgroundColor: C.bgSurface,
    barrierColor: C.overlay,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(R.sheet)),
    ),
    builder: (ctx) {
      final maxH = MediaQuery.of(ctx).size.height * 0.8;
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 頂部拖曳把手：寬 36 × 高 4，圓角 2，距抽屜頂 8px
            const SizedBox(height: S.sm),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: C.lineDivider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: S.base),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: S.base),
              child: Row(
                children: [Expanded(child: Text(title, style: T.h3()))],
              ),
            ),
            const SizedBox(height: S.md),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                    S.base, 0, S.base, S.scrollBottom),
                child: child,
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// Toast —— 只是告知結果。停留 2 秒，同時只有 1 個，新的取代舊的。
void showToast(BuildContext context, String message) {
  final m = ScaffoldMessenger.of(context);
  m.clearSnackBars(); // 不堆疊
  m.showSnackBar(
    SnackBar(
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 120, maxWidth: 343),
        child: Text(message, style: T.body(color: C.textOnDark)),
      ),
      backgroundColor: C.actionOutline,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(R.control),
      ),
      padding: const EdgeInsets.symmetric(horizontal: S.base, vertical: S.md),
      // **底部留出一整個底部按鈕列的高度**（`S.footerClear`）。
      //
      // 原本是 `S.md`，提示就貼在畫面最底 —— 而本專案的主按鈕一律在
      // `_Footer` 裡，也在最底。兩者重疊的那兩秒，使用者按了沒反應
      // （第 5 節 12c；註冊流程那一處 2026-09-17 是靠移除該提示繞過的，
      // 但同一個陷阱在任何「動作完成 → 換頁 → 新頁底部有按鈕」的組合都在）。
      //
      // **為什麼不是讓提示不攔截點擊** —— 那才是根治，但 2026-09-29 實測過
      // 兩條路都無效：`hitTestBehavior: translucent` 沒用，把 `content`
      // 包進 `IgnorePointer` 也沒用，吃掉點擊的在 Flutter 的 SnackBar 內部。
      // 真要根治得自己寫 OverlayEntry，那會動到全站 showToast 的計時器
      // 生命週期（2,400 多個測試裡有大量間接呼叫它的）。留在 12c。
      margin: const EdgeInsets.fromLTRB(S.base, 0, S.base, S.footerClear),
      width: null,
    ),
  );
}
