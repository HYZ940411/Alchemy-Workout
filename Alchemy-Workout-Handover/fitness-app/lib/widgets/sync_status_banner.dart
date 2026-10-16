import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../design/typography.dart';
import '../state/app_state.dart';

/// 離線提示：資料送出超過 3 秒還沒完成時，疊在畫面最上方。
///
/// 不擋點擊（[IgnorePointer]）、不改底下的版面；連上網、資料送完就自己消失。
/// 它講的是「資料還沒同步」，不是「現在沒網路」—— 後者我們沒有可靠的訊號。
/// 必須是 [Stack] 的直接子層（用 [Positioned]）。
class SyncStatusBanner extends StatelessWidget {
  const SyncStatusBanner({super.key});

  static const text = '離線中或網路不穩 · 資料尚未同步';

  @override
  Widget build(BuildContext context) {
    // AppScope 是 InheritedNotifier：狀態一變，這裡自動重建，不必另外聽。
    final state =
        context.dependOnInheritedWidgetOfExactType<AppScope>()?.notifier;
    if (state == null || !state.syncStalled) {
      return const Positioned(left: 0, top: 0, child: SizedBox.shrink());
    }
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: SafeArea(
          bottom: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: Container(
              margin: const EdgeInsets.only(top: S.sm),
              padding: const EdgeInsets.symmetric(
                horizontal: S.md,
                vertical: S.sm,
              ),
              decoration: BoxDecoration(
                color: C.accentDeep,
                borderRadius: BorderRadius.circular(R.control),
              ),
              child: Material(
                type: MaterialType.transparency,
                child: Text(
                  text,
                  key: const ValueKey('sync-banner'),
                  style: T.caption(color: C.textOnDark),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
