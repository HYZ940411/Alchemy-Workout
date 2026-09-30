import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

/// 封鎖名單（〈封鎖 Aggregate〉）
///
/// 封鎖為**獨立 Aggregate，不附屬於對話** —— 可封鎖從未與其對話過的對象，
/// 掛在對話之下就表達不出這件事。單向關係，唯一鍵為 封鎖者 ＋ 被封鎖者。
class BlockedListScreen extends StatefulWidget {
  const BlockedListScreen({super.key});

  @override
  State<BlockedListScreen> createState() => _BlockedListScreenState();
}

class _BlockedListScreenState extends State<BlockedListScreen> {
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final list = s.blockedUsers;

    return Scaffold(
      backgroundColor: C.bgPage,
      appBar: AppBar(title: const Text('封鎖名單')),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: C.bgSurface,
            padding: const EdgeInsets.all(S.base),
            child: Text('被封鎖的人看不到你的貼文，也無法傳私訊給你。',
                style: T.caption()),
          ),
          Expanded(
            child: list.isEmpty
                ? const EmptyState(
                    icon: Icons.block_outlined,
                    title: '沒有封鎖任何人',
                    message: '在貼文或私訊的更多選單裡可以封鎖對方。',
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(
                        S.base, S.base, S.base, S.scrollBottom),
                    children: [
                      ListGroup(rows: [
                        for (var i = 0; i < list.length; i++)
                          ListRow(
                            leading: CircleAvatar(
                              radius: 18,
                              backgroundColor: C.bgPage,
                              child: const Icon(Icons.person_off_outlined,
                                  size: Sz.iconDense, color: C.textSecondary),
                            ),
                            title: list[i].name,
                            subtitle: '封鎖於 '
                                '${list[i].at.month}/'
                                '${list[i].at.day.toString().padLeft(2, '0')}',
                            trailing: SizedBox(
                              width: 88,
                              child: AppButton(
                                label: '解除',
                                kind: BtnKind.secondary,
                                onPressed: () => _unblock(context, s, i),
                              ),
                            ),
                            showDivider: i != list.length - 1,
                          ),
                      ]),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _unblock(BuildContext context, AppState s, int i) async {
    final b = s.blockedUsers[i];
    final name = b.name;
    final ok = await showAppDialog(
      context,
      // 對方現在的名字。封鎖清單上那份是封鎖當下存的。
      title: '解除封鎖 ${s.nameOf(name, uid: b.uid)}？',
      message: '解除後對方可以再看到你的貼文，也能傳私訊給你。',
      confirmLabel: '解除封鎖',
      destructive: true,
    );
    if (ok != true || !context.mounted) return;
    s.unblockUser(name, uid: b.uid);
    showToast(context, '已解除封鎖');
    setState(() {});
  }
}
