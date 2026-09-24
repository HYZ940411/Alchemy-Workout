import 'package:flutter/material.dart';

import '../../design/image_library.dart';
import '../../domain/clock.dart';
import '../../domain/community.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../me/profile_screen.dart';
import 'post_detail_screen.dart';
import 'post_menu.dart';
import 'social_lock.dart';

/// 一張貼文卡 —— 動態牆與個人檔案頁**共用同一張**。
///
/// 原本只有動態牆有這張卡，檔案頁自己畫了一段「作者的公開貼文」：
/// 兩行純文字、`take(2)`、沒有按讚留言檢舉，也點不進貼文詳情。
/// 使用者回報「公開貼文顯示不完整，少了更早發布的文章」。
///
/// **修法不是把 `take(2)` 拿掉再補幾顆按鈕上去** —— 那會做出第二張
/// 慢慢長歪的卡片。這個專案的 bug 有一整排正是「同一個決定寫在兩個
/// 地方，只有一處做對」：貼文選單漏了分支、條款閘門只加在一條路上。
/// 所以把動態牆那張抽出來共用，兩邊一定一樣。
class PostCard extends StatelessWidget {
  final Post post;
  const PostCard({super.key, required this.post});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        // 點卡片進貼文詳情；按讚與留言的觸控區在下面各自攔截。
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => PostDetailScreen(post: post))),
        behavior: HitTestBehavior.opaque,
        child: Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // 頭像與名字點進作者的公開檔案（`[QA-02i]`）——
                  // 卡片本身點進貼文詳情，兩個觸控區分開；
                  // 右邊的檢舉鍵留在這個 GestureDetector 之外。
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => openProfile(context, post.author, uid: post.authorUid),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 17,
                            backgroundColor: AppColors.surfaceAlt,
                            child: Text(
                              post.author.characters.first,
                              style: const TextStyle(
                                color: AppColors.accent,
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      post.author,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    // 作者**現在**的教官聲望。被撤銷教官身分
                                    // 的人不該還掛著這枚徽章；發文後才當上
                                    // 教官的人則該有。貼文上那份只在查不到
                                    // 他的公開檔案時墊底。
                                    if (s.reputationOf(post.author,
                                            uid: post.authorUid,
                                            fallback: post.authorReputation)
                                        case final rep?) ...[
                                      const SizedBox(width: 6),
                                      Pill('教官 $rep'),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        // **作者現在的階級，不是發文當下那個。**
                                        // `post.authorRank` 只在查不到作者的
                                        // 公開檔案時墊底（見 `Post.authorRank`）。
                                        '${s.rankOf(post.author, uid: post.authorUid, fallback: post.authorRank)} 階　·　'
                                        '${_ago(post.at)}　·　'
                                        '${postVisibilityNames[post.visibility]}',
                                        style: T.caption(),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (post.pendingReview) ...[
                                      const SizedBox(width: S.sm),
                                      const TagBadge('審核中'),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    // **自己的貼文開的是編輯／刪除，不是檢舉。**
                    // 在此之前這裡無條件開檢舉單 —— 點自己的貼文會看到
                    // 「檢舉這篇貼文」。判斷在 `showPostMenu` 裡，
                    // 與貼文詳情頁共用同一支，不再各寫一次。
                    onPressed: () => showPostMenu(context, s, post),
                    icon: const Icon(
                      Icons.more_horiz,
                      size: 18,
                      color: AppColors.textFaint,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                post.text,
                style: const TextStyle(fontSize: 13.5, height: 1.65),
              ),
              // 貼文的圖片集合。橫向捲動，不讓多張圖把整篇貼文撐得很長。
              if (post.images.isNotEmpty) ...[
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final id in post.images) ...[
                        AppImageView(id: id, size: 112),
                        const SizedBox(width: S.md),
                      ],
                    ],
                  ),
                ),
              ],
              if (post.attachedWorkout != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.fitness_center,
                        size: 15,
                        color: AppColors.accent,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          post.attachedWorkout!,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppColors.textDim,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const Divider(height: 22, color: AppColors.line),
              Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      final blocked = s.communityBlockedReason;
                      if (blocked != null) {
                        showToast(context, blocked);
                        return;
                      }
                      if (socialLocked(context, '按讚')) return;
                      s.toggleLike(post);
                    },
                    child: Row(
                      children: [
                        Icon(
                          post.likedByMe
                              ? Icons.favorite
                              : Icons.favorite_border,
                          size: 17,
                          color: post.likedByMe
                              ? C.accentDeep
                              : C.textSecondary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${post.likes}',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: post.likedByMe
                                ? C.accentDeep
                                : C.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 20),
                  Icon(
                    Icons.mode_comment_outlined,
                    size: 16,
                    color: AppColors.textDim,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${post.comments.where((c) => !c.deleted).length}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textDim,
                    ),
                  ),
                ],
              ),
              // 已下架與已刪除的留言不顯示。
              for (final c in post.comments.where((c) => !c.deleted)) ...[
                const SizedBox(height: 10),
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: '${c.author}　',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                        ),
                      ),
                      TextSpan(
                        text: c.text,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textDim,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              _CommentBox(post: post),
            ],
          ),
        ),
      ),
    );
  }

  static String _ago(DateTime d) {
    final diff = appNow().difference(d);
    if (diff.inHours < 1) return '${diff.inMinutes} 分鐘前';
    if (diff.inDays < 1) return '${diff.inHours} 小時前';
    return '${diff.inDays} 天前';
  }
}

class _CommentBox extends StatefulWidget {
  final Post post;
  const _CommentBox({required this.post});
  @override
  State<_CommentBox> createState() => _CommentBoxState();
}

class _CommentBoxState extends State<_CommentBox> {
  final ctrl = TextEditingController();

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: ctrl,
            style: const TextStyle(fontSize: 12.5),
            decoration: InputDecoration(
              isDense: true,
              hintText: '留言…',
              hintStyle: const TextStyle(
                color: AppColors.textFaint,
                fontSize: 12.5,
              ),
              filled: true,
              fillColor: AppColors.surfaceAlt,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        IconButton(
          onPressed: () {
            final blocked = s.communityBlockedReason;
            if (blocked != null) {
              showToast(context, blocked);
              return;
            }
            if (socialLocked(context, '留言')) return;
            s.addComment(widget.post, ctrl.text);
            ctrl.clear();
          },
          icon: const Icon(
            Icons.send_rounded,
            size: 18,
            color: AppColors.accent,
          ),
        ),
      ],
    );
  }
}
