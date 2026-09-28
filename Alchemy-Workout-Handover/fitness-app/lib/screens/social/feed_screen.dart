import 'package:flutter/material.dart';

import '../../domain/community.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'compose_post_screen.dart';
import 'post_card.dart';
import 'social_lock.dart';

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
                    onPressed: () {
                      if (socialLocked(context, '發文')) return;
                      Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const ComposePostScreen()),
                      );
                    },
                  ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                // 關注：已關注帳號的貼文 ＋ 自己的貼文
                //
                // **不再依可見範圍過濾**（使用者裁決 2026-09-26，
                // 貼文一律公開）。過濾掉了也沒有用 —— 安全規則那一側是
                // `allow read: if request.auth != null`，任何登入者本來就
                // 讀得到每一篇。前端濾掉只是讓自己看不到，不是讓別人看不到。
                _PostList(
                  posts: s.visiblePosts
                      .where((p) =>
                          p.author == s.displayName ||
                          s.isFollowing(p.author, uid: p.authorUid))
                      .toList(),
                  empty: '你關注的人還沒有新貼文。',
                ),
                // 探索：全平台貼文
                _PostList(
                  posts: s.visiblePosts,
                  empty: '目前沒有貼文。',
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

  /// 下拉重新整理。
  ///
  /// 貼文原本只在登入那一刻讀一次，所以 B 已經登入著、A 這時發文，
  /// B 要把 App 完全重新載入才看得到（`[QA-01]` 第 6 項的前半）。
  ///
  /// **沒接後端時不掛這個**：示範模式的貼文就在記憶體裡，
  /// 給一個下拉了什麼都不會變的手勢，比沒有這個手勢更糟。
  Widget _refreshable(BuildContext context, Widget child) {
    final s = AppScope.of(context);
    if (s.postSource == null) return child;
    return RefreshIndicator(
      onRefresh: s.refreshCloudPosts,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (posts.isEmpty) {
      // 空狀態也要能下拉 —— 「還沒有貼文」與「別人發了但我還沒讀到」
      // 在畫面上長得一模一樣，而後者正是這次要修的問題。
      // EmptyState 本身不捲動，所以包一層撐滿高度的可捲區。
      return _refreshable(
        context,
        LayoutBuilder(
          builder: (context, box) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(minHeight: box.maxHeight),
                child: EmptyState(
                  icon: Icons.forum_outlined,
                  title: '這裡還沒有貼文',
                  message: empty,
                  action: AppButton(
                    label: '發第一篇',
                    icon: Icons.edit_outlined,
                    onPressed: () {
                      if (socialLocked(context, '發文')) return;
                      Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const ComposePostScreen()));
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return _refreshable(
      context,
      ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 50),
        children: [for (final p in posts) PostCard(post: p)],
      ),
    );
  }
}
