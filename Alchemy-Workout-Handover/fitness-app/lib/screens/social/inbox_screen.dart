import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../domain/inbound.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

/// 收件匣 —— 對方發起、等我回應的請求。
///
/// 三種請求共用一頁：模型上它們是同一個形狀（對方送出、我接受或拒絕、
/// 168 小時逾期），分三頁只會讓「還剩幾天」散在三個地方。
class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final items = s.liveInbox;

    return Scaffold(
      backgroundColor: C.bgPage,
      appBar: AppBar(title: const Text('收件匣')),
      // 下拉重新整理 —— 沒有即時訂閱，對方送出申請時我這邊不會自己跳出來。
      body: RefreshIndicator(
        onRefresh: AppScope.of(context).refreshInbound,
        child: items.isEmpty
          // 空的時候也要拉得動：收件匣沒東西才最需要「再看一次」。
          ? ListView(children: [SizedBox(
              height: MediaQuery.of(context).size.height * 0.7,
              child: _empty())])
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                  S.base, S.base, S.base, S.scrollBottom),
              children: [
                Text(
                  '每一筆自送出起算 7 天，逾期未回應即失效。',
                  style: T.caption(),
                ),
                for (final r in items) ...[
                  const SizedBox(height: S.base),
                  _card(context, s, r),
                ],
              ],
            ),
      ),
    );
  }

  Widget _empty() => Center(
        child: Padding(
          padding: const EdgeInsets.all(S.xl),
          child: Text(
            '沒有等你回應的請求。\n團隊邀請與師徒申請會出現在這裡。',
            style: T.caption(),
            textAlign: TextAlign.center,
          ),
        ),
      );

  Widget _card(BuildContext context, AppState s, InboundRequest r) {
    final blocked = s.inboundBlockedReason(r);
    final left = r.leftAt(s.now);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Pill(r.kindName),
              const Spacer(),
              Text(_left(left), style: T.caption()),
            ],
          ),
          const SizedBox(height: S.md),
          Text(_title(r), style: T.h3()),
          const SizedBox(height: S.xs),
          Text(_detail(r), style: T.caption()),
          // 不能接受的理由要講出來，否則使用者只看到一顆按不下去的按鈕。
          if (blocked != null) ...[
            const SizedBox(height: S.md),
            Text(blocked, style: T.caption().copyWith(color: C.statusWarning)),
          ],
          const SizedBox(height: S.base),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: '拒絕',
                  kind: BtnKind.secondary,
                  onPressed: () {
                    s.declineInbound(r);
                    showToast(context, '已拒絕');
                    setState(() {});
                  },
                ),
              ),
              const SizedBox(width: S.md),
              Expanded(
                child: AppButton(
                  label: '接受',
                  onPressed: blocked != null
                      ? null
                      : () {
                          final ok = s.acceptInbound(r);
                          showToast(context, ok ? '已接受' : '沒有成功');
                          setState(() {});
                        },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _title(InboundRequest r) => switch (r.kind) {
        InboundKind.teamInvite => '${r.from} 邀你加入「${r.subject}」',
        InboundKind.mentorInvite => '${r.from} 想收你為徒',
        InboundKind.apprenticeApply => '${r.from} 想拜你為師',
      };

  static String _detail(InboundRequest r) => switch (r.kind) {
        InboundKind.teamInvite =>
          '隊長 ${r.from}（${r.fromRank} 階）。一次只能屬於一個團隊。',
        InboundKind.mentorInvite =>
          '${r.fromRank} 階教官。一位學徒同時只能有一位教官。',
        InboundKind.apprenticeApply => '${r.fromRank} 階。接受後佔用一個帶徒名額。',
      };

  static String _left(Duration d) {
    if (d.inDays >= 1) return '還剩 ${d.inDays} 天';
    if (d.inHours >= 1) return '還剩 ${d.inHours} 小時';
    return '不到 1 小時';
  }
}
