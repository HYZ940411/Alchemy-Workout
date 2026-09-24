import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import '../me/profile_screen.dart';
import 'social_lock.dart';

/// 關注／粉絲清單（〈關注流程〉）
///
/// 關注為**單向關係**：關注別人與被別人關注是兩件事，故兩個分頁分開。
/// 粉絲數為使用者 Aggregate 的儲存欄位，不變條件為
/// 「粉絲數 ＝ 關注關係中被關注者為本人的筆數」。
class FollowListScreen extends StatefulWidget {
  final int initialTab;
  const FollowListScreen({super.key, this.initialTab = 0});

  @override
  State<FollowListScreen> createState() => _FollowListScreenState();
}

class _FollowListScreenState extends State<FollowListScreen> {
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);

    return DefaultTabController(
      length: 2,
      initialIndex: widget.initialTab,
      child: Scaffold(
        backgroundColor: C.bgPage,
        appBar: AppBar(
          title: const Text('關注與粉絲'),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(Sz.tapTarget),
            child: AppTabBar(
              tabs: ['關注 ${s.following.length}', '粉絲 ${s.followerCount}'],
            ),
          ),
        ),
        body: TabBarView(
          children: [
            _List(
              names: s.following.toList(),
              emptyTitle: '還沒有關注任何人',
              emptyMessage: '在動態牆或教官清單看到喜歡的人，關注他就會出現在這裡。',
              onChanged: () => setState(() {}),
            ),
            _List(
              names: s.followers,
              emptyTitle: '還沒有粉絲',
              emptyMessage: '持續發文與互動，會慢慢累積粉絲。',
              onChanged: () => setState(() {}),
            ),
          ],
        ),
      ),
    );
  }
}

class _List extends StatelessWidget {
  final List<String> names;
  final String emptyTitle;
  final String emptyMessage;
  final VoidCallback onChanged;
  const _List({
    required this.names,
    required this.emptyTitle,
    required this.emptyMessage,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    if (names.isEmpty) {
      return EmptyState(
        icon: Icons.people_outline,
        title: emptyTitle,
        message: emptyMessage,
      );
    }
    return ListView(
      padding:
          const EdgeInsets.fromLTRB(S.base, S.base, S.base, S.scrollBottom),
      children: [
        ListGroup(rows: [
          for (var i = 0; i < names.length; i++)
            _row(context, s, names[i], i != names.length - 1),
        ]),
      ],
    );
  }

  ListRow _row(
      BuildContext context, AppState s, String name, bool divider) {
    final u = s.userOf(name);
    final followed = s.following.contains(name);
    return ListRow(
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: C.bgPage,
        child:
            Text(name.characters.first, style: T.body(weight: FontWeight.w700)),
      ),
      title: name,
      // 現在的階級與綜合等級。`u` 那份是我第一次見到他時存下來的 ——
      // 在此之前 `applyPublicProfiles` 對已在清單裡的人直接跳過，
      // 所以這裡顯示的比貼文上那個凍結值還舊。
      subtitle: '階級 ${s.rankOf(name, uid: u.uid, fallback: u.rank)}'
          '　·　綜合 ${s.gradeOf(name, uid: u.uid) ?? u.grade}',
      // 點整列進他的公開檔案（`[QA-02i]`）。關注鍵在右邊，各自的觸控區。
      onTap: () => openProfile(context, name, uid: u.uid),
      // 取消關注屬破壞性動作，用次要樣式（§4.5 R-23）；
      // 兩種狀態共用同一顆按鈕，寬度固定才不會左右跳動。
      trailing: SizedBox(
        width: 88,
        child: AppButton(
          label: followed ? '追蹤中' : '關注',
          kind: BtnKind.secondary,
          onPressed: () {
            if (socialLocked(context, '關注')) return;
            s.toggleFollow(name);
            onChanged();
          },
        ),
      ),
      showDivider: divider,
    );
  }
}
