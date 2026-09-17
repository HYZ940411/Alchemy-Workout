import '../../domain/clock.dart';
import 'package:flutter/material.dart';

import '../../design/image_library.dart';
import '../../domain/community.dart';
import '../../domain/admin.dart';
import '../../state/app_state.dart';
import 'report_sheet.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../me/profile_screen.dart';
import 'compose_post_screen.dart';
import 'post_detail_screen.dart';

/// Read Model：社群動態牆 —— 分頁為「關注」與「探索」。
class FeedScreen extends StatelessWidget {
  const FeedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(11),
            ),
            child: const TabBar(
              indicator: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.all(Radius.circular(8)),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              labelColor: AppColors.onAccent,
              unselectedLabelColor: AppColors.textDim,
              labelStyle: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
              tabs: [
                Tab(text: '關注'),
                Tab(text: '探索'),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(S.base, 0, S.base, S.sm),
            child: s.communityBlocked
                ? SuspensionNotice(s.communityBlockedReason!)
                : AppButton(
                    label: '發文',
                    kind: BtnKind.secondary,
                    icon: Icons.edit_outlined,
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const ComposePostScreen()),
                    ),
                  ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                // 關注：已關注帳號的貼文 ＋ 自己的貼文
                _PostList(
                  posts: s.visiblePosts
                      .where(
                        (p) =>
                            p.author == s.displayName ||
                            (s.following.contains(p.author) &&
                                p.visibility != PostVisibility.private),
                      )
                      .toList(),
                  empty: '你關注的人還沒有新貼文。',
                ),
                // 探索：全平台**公開**貼文
                _PostList(
                  posts: s.visiblePosts
                      .where((p) => p.visibility == PostVisibility.public)
                      .toList(),
                  empty: '目前沒有公開貼文。',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PostList extends StatelessWidget {
  final List<Post> posts;
  final String empty;
  const _PostList({required this.posts, required this.empty});

  @override
  Widget build(BuildContext context) {
    if (posts.isEmpty) {
      return EmptyState(
        icon: Icons.forum_outlined,
        title: '這裡還沒有貼文',
        message: empty,
        action: AppButton(
          label: '發第一篇',
          icon: Icons.edit_outlined,
          onPressed: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const ComposePostScreen())),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 50),
      children: [for (final p in posts) _PostCard(post: p)],
    );
  }
}

class _PostCard extends StatelessWidget {
  final Post post;
  const _PostCard({required this.post});

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
                      onTap: () => openProfile(context, post.author),
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
                                    if (post.authorReputation != null) ...[
                                      const SizedBox(width: 6),
                                      Pill('教官 ${post.authorReputation}'),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        '${post.authorRank} 階　·　'
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
                    onPressed: () => showReportSheet(
                      context,
                      target: ReportTarget.post,
                      targetKey: reportKey(ReportTarget.post, post.id),
                      content: post.text,
                      accused: post.author,
                    ),
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
