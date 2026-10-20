import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../domain/community.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

/// 內容被自動過濾攔下時的彈窗（Event「內容已攔截」）。
///
/// 「申訴」按鈕要真的能申訴：先收理由，再把這次被攔下的原文連同理由送給管理員。
/// 貼文、留言、私訊共用同一個入口，免得三處各寫一次、其中一處漏掉。
Future<void> showBlockedDialog(
  BuildContext context,
  AppState s, {
  required BlockedKind kind,
}) async {
  final name = blockedKindNames[kind]!;
  final appeal = await showAppDialog(
    context,
    title: '內容已攔截',
    message:
        '這則$name判定為明顯違規，未送出，'
        '也不發放任何互動獎勵。你可以修改後重送，或提出申訴。',
    confirmLabel: '我知道了',
    cancelLabel: '申訴',
  );
  if (appeal != false || !context.mounted) return;

  final controller = TextEditingController();
  final ok = await showAppDialog(
    context,
    title: '申訴這次攔截',
    confirmLabel: '送出申訴',
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '同一次攔截只能申訴一次。送出後由管理員審視，成立的話這段原文就可以發布。',
          style: T.body(color: C.textSecondary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: S.md),
        TextField(
          controller: controller,
          style: T.body(),
          maxLines: 3,
          decoration: InputDecoration(
            hintText: '說明為什麼你認為這則內容沒有違規',
            hintStyle: T.body(color: C.textDisabled),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(R.control),
            ),
          ),
        ),
      ],
    ),
  );
  final reason = controller.text.trim();
  // 這裡不 dispose：彈窗關閉動畫還在跑，輸入框仍在使用這個 controller，
  // 提早釋放會在動畫期間拋「用了已釋放的 controller」。處罰申訴那一頁同樣不釋放。
  if (ok != true || !context.mounted) return;

  final sent = s.fileBlockedAppeal(reason.isEmpty ? '（未填理由）' : reason);
  showToast(context, sent ? '申訴已送出' : '這次攔截已經申訴過了');
}
