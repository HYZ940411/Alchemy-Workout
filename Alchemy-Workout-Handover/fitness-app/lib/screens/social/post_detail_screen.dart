import '../../domain/clock.dart';
import 'package:flutter/material.dart';

import '../../design/image_library.dart';
import '../../design/tokens.dart';
import '../../domain/community.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import 'post_menu.dart';
import '../me/profile_screen.dart';
import 'social_lock.dart';

/// 貼文詳情頁（〈發文與互動流程〉）
///
/// 支撐的 Command：按讚、留言、檢舉、封鎖。
/// 動態牆只放前兩則留言，這裡放全部 —— 「看留言」正是點進來的理由。
class PostDetailScreen extends StatefulWidget {
  final Post post;
  const PostDetailScreen({super.key, required this.post});

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final ctrl = TextEditingController();

  /// 留言圖示點下去要把游標送進輸入框 —— 原本它綁的是一個空函式，
  /// 看起來可點、按了什麼都不會發生。
  final commentFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    ctrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    ctrl.dispose();
    commentFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = widget.post;

    return Scaffold(
      backgroundColor: C.bgPage,
      appBar: AppBar(
        title: const Text('貼文'),
        actions: [
          // 自己的貼文沒有檢舉與封鎖 —— 那兩個 Command 的對象是別人；
          // 有的是編輯與刪除，那兩個的對象只能是自己。
          IconButton(
            // 自己的貼文開編輯／刪除，別人的開檢舉／封鎖。判斷與選單
            // 內容都在 `showPostMenu` 裡，與動態牆共用同一支。
            onPressed: () => showPostMenu(context, s, p,
                // 貼文都刪了，這一頁沒有東西可看 —— 關掉它。
                onDeleted: () => Navigator.of(context).pop()),
            icon: const Icon(Icons.more_vert, size: Sz.iconDefault),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                  S.base, S.base, S.base, S.scrollBottom),
              children: [
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 整條點進作者的公開檔案（`[QA-02i]`）。
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => openProfile(context, p.author, uid: p.authorUid),
                        child: Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: C.bgPage,
                            child: Text(p.author.characters.first,
                                style: T.body(weight: FontWeight.w700)),
                          ),
                          const SizedBox(width: S.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(p.author,
                                    style: T.body(weight: FontWeight.w700)),
                                const SizedBox(height: 2),
                                Text(
                                  // 作者現在的階級，不是發文當下那個。
                                  '${s.rankOf(p.author, uid: p.authorUid, fallback: p.authorRank)} 階　·　'
                                  '${_ago(p.at)}',
                                  style: T.caption(),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      ),
                      const SizedBox(height: S.base),
                      Text(p.text, style: T.body()),
                      if (p.images.isNotEmpty) ...[
                        const SizedBox(height: S.base),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              for (final id in p.images) ...[
                                AppImageView(id: id, size: 140),
                                const SizedBox(width: S.md),
                              ],
                            ],
                          ),
                        ),
                      ],
                      if (p.attachedWorkout != null) ...[
                        const SizedBox(height: S.base),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(S.md),
                          decoration: BoxDecoration(
                            color: C.bgPage,
                            borderRadius: BorderRadius.circular(R.child),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.fitness_center,
                                  size: Sz.iconDense, color: C.textSecondary),
                              const SizedBox(width: S.sm),
                              Expanded(
                                child: Text(p.attachedWorkout!,
                                    style: T.caption()),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (p.pendingReview) ...[
                        const SizedBox(height: S.md),
                        Text('本篇已自動送審，審核期間仍為已發布。',
                            style: T.caption(color: C.accentDeep)),
                      ],
                      const Divider(height: S.lg, color: C.lineDivider),
                      Row(
                        children: [
                          _Action(
                            icon: p.likedByMe
                                ? Icons.favorite
                                : Icons.favorite_border,
                            label: '${p.likes}',
                            active: p.likedByMe,
                            onTap: () {
                              final blocked = s.communityBlockedReason;
                              if (blocked != null) {
                                showToast(context, blocked);
                                return;
                              }
                              if (socialLocked(context, '按讚')) return;
                              setState(() => s.toggleLike(p));
                            },
                          ),
                          const SizedBox(width: S.lg),
                          _Action(
                            icon: Icons.mode_comment_outlined,
                            label: '${p.comments.where((c) => !c.deleted).length}',
                            onTap: () => commentFocus.requestFocus(),
                          ),
                          const SizedBox(width: S.lg),
                          _Action(
                            icon: Icons.ios_share_rounded,
                            label: '分享',
                            // 分享把內容交給系統的分享面板，屬系統邊界之外。
                            onTap: () => showToast(context, '已開啟分享面板'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                SectionTitle('留言',
                    trailing: '${p.visibleComments.length} 則'),
                if (p.visibleComments.isEmpty)
                  AppCard(child: Text('還沒有人留言。', style: T.caption()))
                else
                  ListGroup(rows: [
                    for (var i = 0; i < p.visibleComments.length; i++)
                      () {
                        final c = p.visibleComments[i];
                        final mine = c.author == s.displayName;
                        return ListRow(
                          leading: CircleAvatar(
                            radius: 16,
                            backgroundColor: C.bgPage,
                            child: Text(c.author.characters.first,
                                style: T.caption()),
                          ),
                          title: c.author,
                          // 已編輯旗標要對讀者顯示，不是只留在資料裡。
                          subtitle: '${c.text}${c.edited ? '（已編輯）' : ''}'
                              '　·　${_ago(c.at)}',
                          trailing: mine
                              ? GestureDetector(
                                  onTap: () => _commentMenu(context, s, c),
                                  child: const Icon(Icons.more_horiz,
                                      size: Sz.iconDense,
                                      color: C.textSecondary),
                                )
                              : null,
                          showDivider: i != p.visibleComments.length - 1,
                        );
                      }(),
                  ]),
              ],
            ),
          ),
          Container(
            decoration: const BoxDecoration(
              color: C.bgSurface,
              border: Border(top: BorderSide(color: C.lineDivider)),
            ),
            padding: EdgeInsets.fromLTRB(S.base, S.md, S.base,
                MediaQuery.of(context).padding.bottom + S.base),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: ctrl,
                    focusNode: commentFocus,
                    style: T.body(),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: '寫下留言',
                      hintStyle: T.body(color: C.textDisabled),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: S.base, vertical: S.md),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(R.control),
                        borderSide: const BorderSide(color: C.lineDivider),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(R.control),
                        borderSide: const BorderSide(color: C.lineDivider),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(R.control),
                        borderSide:
                            const BorderSide(color: C.actionOutline, width: 2),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: S.md),
                _Send(
                  enabled: ctrl.text.trim().isNotEmpty,
                  onTap: () {
                    // 停權中的社群互動要說得出理由 —— 靜靜地什麼都不發生，
                    // 使用者只會以為 App 壞了。
                    final blocked = s.communityBlockedReason;
                    if (blocked != null) {
                      showToast(context, blocked);
                      return;
                    }
                    // 留言同樣先過自動過濾 —— 明顯違規當場攔截。
                    if (s.screenContent(ctrl.text) == FilterVerdict.blocked) {
                      showToast(context, '留言含明顯違規內容，已攔截');
                      return;
                    }
                    if (socialLocked(context, '留言')) return;
                    s.addComment(p, ctrl.text);
                    ctrl.clear();
                    setState(() {});
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _ago(DateTime t) {
    final d = appNow().difference(t);
    if (d.inMinutes < 60) return '${d.inMinutes} 分鐘前';
    if (d.inHours < 24) return '${d.inHours} 小時前';
    return '${d.inDays} 天前';
  }
}

Future<void> _commentMenu(
    BuildContext context, AppState s, Comment c) async {
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
            title: '編輯留言',
            onTap: () async {
              Navigator.of(sheetContext).pop();
              await editTextDialog(context, '編輯留言', c.text,
                  (v) => s.editComment(c, v));
            },
          ),
          ListRow(
            title: '刪除留言',
            subtitle: '已發放的獎勵不回收；重新留言算新的一次互動',
            showDivider: false,
            onTap: () async {
              Navigator.of(sheetContext).pop();
              final failed = await s.deleteComment(c);
              if (failed != null && context.mounted) {
                showToast(context, failed);
              }
            },
          ),
        ],
      ),
    ),
  );
}

class _Action extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _Action({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: Sz.iconDefault,
                color: active ? C.statusError : C.textSecondary),
            const SizedBox(width: S.xs),
            Text(label, style: T.caption()),
          ],
        ),
      );
}

class _Send extends StatelessWidget {
  final bool enabled;
  final VoidCallback onTap;
  const _Send({required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
        color: enabled ? C.actionPrimary : C.actionPrimaryDisabled,
        borderRadius: BorderRadius.circular(R.control),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: SizedBox(
            width: Sz.tapTarget,
            height: Sz.tapTarget,
            child: Icon(Icons.arrow_forward_rounded,
                size: Sz.iconDefault, color: C.onFill(C.actionPrimary)),
          ),
        ),
      );
}
