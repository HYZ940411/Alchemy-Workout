import 'package:flutter/material.dart';

import '../../design/overlays.dart';
import '../../state/app_state.dart';
import '../train/tasks_screen.dart';

/// 社群互動功能的解鎖閘門（〈新手任務流程〉）。
///
/// 規格明訂解鎖範圍為**發文、按讚、留言、分享、關注**五項，
/// 由「使用者已完成新手任務」解開；單調遞增，一經解鎖永久不可撤銷。
///
/// **不鎖社群分頁本身。** 規格鎖的是那五個動作，不是「看」——
/// 把整個分頁擋掉的話，新使用者連社群長什麼樣都不知道，
/// 也就沒有動機去把新手任務做完。這條界線是這個檔案存在的理由。
///
/// **與處罰是兩件事。** 停權以〈使用者 Aggregate〉的處罰狀態欄位表達
/// （`communityBlockedReason`），規格明文「不得以撤銷解鎖旗標實作」。
/// 兩道閘門各自獨立，呼叫端兩個都要過。
library;

/// 這次動作有沒有被解鎖閘門擋下來。
///
/// 回傳 true 代表已擋下並且已經向使用者說明了，呼叫端應立即 `return`。
///
/// 擋下來時開一個彈窗而不是只給一句 toast：使用者需要知道**怎麼解開**，
/// 而不只是「你不能做這件事」。彈窗直接通到新手任務那一頁。
bool socialLocked(BuildContext context, String action) {
  final s = AppScope.of(context);
  if (s.socialUnlocked) return false;

  showAppDialog(
    context,
    title: '完成新手任務就能$action',
    message: '發文、按讚、留言、分享、關注這五項，會在你做完新手任務之後一起解開。'
        '任務是三選一，做一次就好。\n\n'
        '在那之前社群照樣看得到，只是還不能互動。',
    confirmLabel: '去看新手任務',
    cancelLabel: '知道了',
  ).then((go) {
    if (go != true || !context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const TasksScreen()),
    );
  });
  return true;
}
