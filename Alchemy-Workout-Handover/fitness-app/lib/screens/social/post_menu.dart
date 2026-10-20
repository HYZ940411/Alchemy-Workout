import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../domain/admin.dart';
import '../../domain/community.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import 'report_sheet.dart';

/// 貼文右上角那顆「⋯」。
///
/// **看的人是不是作者，決定的是兩組完全不同的 Command。**
/// 自己的貼文：編輯、刪除。別人的貼文：檢舉、封鎖。
/// 「檢舉自己的貼文」與「封鎖自己」都不是模型裡存在的東西。
///
/// ## 為什麼要有這個檔案
///
/// 這個判斷原本寫在兩個地方：貼文詳情頁分支正確，**動態牆那張卡片
/// 沒有分支**，直接開檢舉單 —— 於是使用者點自己貼文上的「⋯」，
/// 看到的是「檢舉這篇貼文」。
///
/// 同一個決定在兩處各寫一次，遲早會有一處漏掉；漏掉的那一處不會報錯，
/// 只會安靜地做錯事。所以收斂成一支，兩個畫面都呼叫它。
///
/// [onDeleted] 在刪除成功後呼叫。**詳情頁要用它把自己關掉**（貼文都沒了，
/// 這一頁沒有東西可看），動態牆則不必 —— 那裡刪完只要原地重畫。
/// 寫死一個 `Navigator.pop()` 的話，從動態牆刪貼文會把動態牆整頁關掉。
Future<void> showPostMenu(
  BuildContext context,
  AppState s,
  Post p, {
  VoidCallback? onDeleted,
}) =>
    s.isMyPost(p)
        ? _mineMenu(context, s, p, onDeleted)
        : _othersMenu(context, s, p);

/// 自己的貼文：編輯與刪除。
///
/// 刪除為**軟刪除** —— 貼文可被檢舉，硬刪除會使案件失去證據。
Future<void> _mineMenu(
  BuildContext context,
  AppState s,
  Post p,
  VoidCallback? onDeleted,
) async {
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: C.bgSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(R.sheet)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListRow(
            title: '編輯貼文',
            onTap: () async {
              Navigator.of(sheetContext).pop();
              await editTextDialog(context, '編輯貼文', p.text, (v) {
                if (s.screenContent(v) == FilterVerdict.blocked) {
                  showToast(context, '內容含明顯違規字詞，無法儲存');
                  return false;
                }
                return s.editPost(p, v);
              });
            },
          ),
          ListRow(
            title: '刪除貼文',
            showDivider: false,
            onTap: () async {
              Navigator.of(sheetContext).pop();
              final ok = await showAppDialog(
                context,
                title: '刪除這則貼文？',
                message: '刪除後動態牆不再呈現。既有的按讚與留言會一起隱藏，'
                    '但資料保留 —— 貼文可能被檢舉，證據不能跟著消失。',
                confirmLabel: '刪除',
                destructive: true,
              );
              if (ok != true || !context.mounted) return;

              // **等雲端確認再說「刪掉了」。** 寫不進去的話 `deletePost`
              // 會把本機的刪除收回，貼文重新出現 —— 這裡要把原因講出來，
              // 否則使用者看到的是「按了刪除、貼文卻閃一下又回來」。
              final failed = await s.deletePost(p);
              if (!context.mounted) return;
              if (failed != null) {
                showToast(context, failed);
                return;
              }
              onDeleted?.call();
            },
          ),
        ],
      ),
    ),
  );
}

/// 別人的貼文：檢舉與封鎖。兩個 Command 的對象都只能是別人。
Future<void> _othersMenu(BuildContext context, AppState s, Post p) async {
  // 作者現在的名字 —— 標題、確認視窗、提示訊息一律用它。
  final author = s.nameOf(p.author, uid: p.authorUid);
  final action = await showAppSheet<String>(
    context,
    title: author,
    child: Column(
      children: [
        ListRow(
          title: '檢舉這篇貼文',
          onTap: () => Navigator.pop(context, 'report'),
        ),
        ListRow(
          title: s.isBlocked(p.author, uid: p.authorUid)
              ? '解除封鎖'
              : '封鎖這個人',
          showDivider: false,
          onTap: () => Navigator.pop(context, 'block'),
        ),
      ],
    ),
  );
  if (!context.mounted || action == null) return;

  if (action == 'report') {
    await showReportSheet(
      context,
      target: ReportTarget.post,
      targetKey: reportKey(ReportTarget.post, p.id),
      content: p.text,
      accused: p.author,
      accusedUid: p.authorUid,
    );
    return;
  }

  if (s.isBlocked(p.author, uid: p.authorUid)) {
    s.unblockUser(p.author, uid: p.authorUid);
    // 解除封鎖不自動恢復任何已解除的關注或師徒關係。
    showToast(context, '已解除封鎖。原本的關注與師徒關係不會自動回復。');
    return;
  }

  // 同隊的人不能封鎖 —— 擋下時要講得出為什麼，不能靜靜地沒反應。
  final blocked = s.blockBlockedReason(p.author, uid: p.authorUid);
  if (blocked != null) {
    showToast(context, blocked);
    return;
  }

  // **封鎖要先確認。** 它是破壞性的、而且會連帶動到第三方關係：
  // 雙方的關注一併解除、師徒關係一併解除、未完成的師徒任務作廢。
  // 解除封鎖**不會**把這些恢復 —— 所以按錯一次就回不去了，
  // 不能是點一下就生效。
  final wasFollowing = s.isFollowing(p.author, uid: p.authorUid);
  final wasFollower = s.isFollower(p.author, uid: p.authorUid);
  final wasMentor = s.myInstructor?.name == p.author;
  final ok = await showAppDialog(
    context,
    title: '封鎖 $author？',
    // **「他關注我」那一半只解得掉你這邊看到的。** 那筆關注是他建立的，
    // 只有他自己取消得了 —— 別人看你的檔案時仍會把他算進粉絲數。
    // 使用者裁決 2026-09-28：不改安全規則，改成在這裡講清楚。
    message: '對方看不到你的貼文，也無法傳私訊給你。'
        '${wasFollowing ? '\n\n雙方的關注會一併解除。' : ''}'
        '${wasFollower ? '\n\n他不會再出現在你的粉絲名單，'
            '但別人看你的檔案時仍會把他算進粉絲數 —— '
            '那筆關注只有他自己取消得了。' : ''}'
        '${wasMentor ? '\n\n師徒關係會一併解除，未完成的任務作廢。' : ''}'
        '\n\n解除封鎖不會把這些恢復。',
    confirmLabel: '封鎖',
    destructive: true,
  );
  if (ok != true || !context.mounted) return;

  s.blockUser(p.author, uid: p.authorUid);
  showToast(
    context,
    '已封鎖 $author'
    '${wasMentor ? '，師徒關係一併解除' : (wasFollowing ? '，關注一併取消' : '')}',
  );
}

/// 編輯貼文／留言共用的那個輸入框。
Future<void> editTextDialog(BuildContext context, String title, String initial,
    bool Function(String) apply) async {
  final ctrl = TextEditingController(text: initial);
  final ok = await showAppDialog(
    context,
    title: title,
    confirmLabel: '儲存',
    content: TextField(
      controller: ctrl,
      style: T.body(),
      maxLines: 4,
      decoration: InputDecoration(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(R.control),
        ),
      ),
    ),
  );
  if (ok == true) apply(ctrl.text);
  ctrl.dispose();
}
