import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../domain/admin.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

/// 管理員帳號維護（新增管理員、停用管理員、調整管理員權限組）
///
/// 三個 Command 的所需權限組皆為平台設定。停用者不實體刪除 ——
/// 其既往的判定紀錄仍須可稽核。
class AdminAccountsScreen extends StatefulWidget {
  const AdminAccountsScreen({super.key});

  @override
  State<AdminAccountsScreen> createState() => _AdminAccountsScreenState();
}

class _AdminAccountsScreenState extends State<AdminAccountsScreen> {
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final allowed = s.canConfigure;

    return Scaffold(
      backgroundColor: C.bgPage,
      appBar: AppBar(title: const Text('管理員帳號')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          S.base,
          S.base,
          S.base,
          S.scrollBottom,
        ),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('管理員為獨立 Aggregate，與使用者帳號分離',
                    style: T.body(weight: FontWeight.w600)),
                const SizedBox(height: S.sm),
                Text(
                  '管理員不必是平台使用者。停用者不實體刪除 —— 其既往的判定紀錄仍須可稽核。',
                  style: T.caption(),
                ),
              ],
            ),
          ),
          SectionTitle('帳號', trailing: '${s.admins.length} 位'),
          for (final a in s.admins) ...[
            _AdminCard(
              admin: a,
              isMe: a.id == s.admin.id,
              enabled: allowed,
              onScopes: () => _scopes(context, s, a),
              onToggle: () => _toggle(context, s, a),
            ),
            const SizedBox(height: S.md),
          ],
          AppButton(
            label: '新增管理員',
            kind: BtnKind.secondary,
            icon: Icons.person_add_alt_1_outlined,
            onPressed: allowed ? () => _add(context, s) : null,
          ),
        ],
      ),
    );
  }

  Future<void> _add(BuildContext context, AppState s) async {
    final name = TextEditingController();
    final scopes = <AdminScope>{AdminScope.contentReview};
    final ok = await showAppDialog(
      context,
      title: '新增管理員',
      size: DialogSize.medium,
      confirmLabel: '新增',
      content: StatefulBuilder(
        builder: (_, setInner) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: name,
              style: T.body(),
              decoration: InputDecoration(
                hintText: '管理員名稱',
                hintStyle: T.body(color: C.textDisabled),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(R.control),
                ),
              ),
            ),
            const SizedBox(height: S.base),
            Text('權限組（至少 1 項）', style: T.caption()),
            const SizedBox(height: S.sm),
            _ScopeChips(
              selected: scopes,
              onToggle: (sc) => setInner(() {
                scopes.contains(sc) ? scopes.remove(sc) : scopes.add(sc);
              }),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    final failure = s.addAdmin(name.text, scopes);
    showToast(context, failure ?? '已新增管理員');
    setState(() {});
  }

  Future<void> _scopes(BuildContext context, AppState s, Admin a) async {
    final next = {...a.scopes};
    final ok = await showAppDialog(
      context,
      title: '調整權限組',
      message: a.name,
      size: DialogSize.medium,
      confirmLabel: '儲存',
      content: StatefulBuilder(
        builder: (_, setInner) => _ScopeChips(
          selected: next,
          onToggle: (sc) => setInner(() {
            next.contains(sc) ? next.remove(sc) : next.add(sc);
          }),
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    final failure = s.setAdminScopesOf(a, next);
    showToast(context, failure ?? '已調整權限組');
    setState(() {});
  }

  Future<void> _toggle(BuildContext context, AppState s, Admin a) async {
    if (a.status == AdminStatus.disabled) {
      final failure = s.enableAdmin(a);
      showToast(context, failure ?? '已恢復為生效中');
      setState(() {});
      return;
    }
    final ok = await showAppDialog(
      context,
      title: '停用 ${a.name}？',
      message: '停用後不得執行任何管理員 Command。帳號不刪除，既往的判定紀錄仍可稽核。',
      confirmLabel: '停用',
      // 破壞性動作仍用次要樣式（§4.5 R-23），安全由本彈窗承擔。
      destructive: true,
    );
    if (ok != true || !context.mounted) return;
    final failure = s.disableAdmin(a);
    showToast(context, failure ?? '已停用');
    setState(() {});
  }
}

class _AdminCard extends StatelessWidget {
  final Admin admin;
  final bool isMe;
  final bool enabled;
  final VoidCallback onScopes;
  final VoidCallback onToggle;
  const _AdminCard({
    required this.admin,
    required this.isMe,
    required this.enabled,
    required this.onScopes,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = admin.status == AdminStatus.disabled;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(admin.name, style: T.body(weight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(admin.id, style: T.caption()),
                  ],
                ),
              ),
              if (isMe) ...[
                const TagBadge('本人'),
                const SizedBox(width: S.sm),
              ],
              TagBadge(
                disabled ? '已停用' : '生效中',
                borderColor: disabled ? C.statusError : C.statusSuccess,
              ),
            ],
          ),
          const SizedBox(height: S.md),
          Wrap(
            spacing: S.sm,
            runSpacing: S.sm,
            children: [
              for (final sc in AdminScope.values)
                if (admin.scopes.contains(sc))
                  TagBadge(adminScopeNames[sc]!, borderColor: C.actionOutline),
            ],
          ),
          const SizedBox(height: S.base),
          ButtonRow(
            left: AppButton(
              label: '調整權限組',
              kind: BtnKind.secondary,
              onPressed: enabled ? onScopes : null,
            ),
            right: AppButton(
              label: disabled ? '恢復' : '停用',
              kind: BtnKind.secondary,
              onPressed: enabled ? onToggle : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScopeChips extends StatelessWidget {
  final Set<AdminScope> selected;
  final void Function(AdminScope) onToggle;
  const _ScopeChips({required this.selected, required this.onToggle});

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: S.sm,
        runSpacing: S.sm,
        children: [
          for (final sc in AdminScope.values)
            GestureDetector(
              onTap: () => onToggle(sc),
              child: TagBadge(
                '${adminScopeNames[sc]}（${adminScopeCommandCount[sc]}）',
                borderColor:
                    selected.contains(sc) ? C.actionOutline : C.lineDivider,
                fill: selected.contains(sc) ? C.actionOutline : null,
              ),
            ),
        ],
      );
}
