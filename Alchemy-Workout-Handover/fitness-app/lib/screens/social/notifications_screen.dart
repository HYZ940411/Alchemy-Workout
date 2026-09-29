import '../../domain/clock.dart';
import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../domain/social.dart';
import '../../design/skeleton.dart';
import '../../state/app_state.dart';
import '../../widgets/load_boundary.dart';
import '../../widgets/common.dart';

/// 通知中心
///
/// 推播類與 App 內通知類是**兩種不同的東西**，只有推播類受同日總量上限約束。
/// 判準是「不看會不會失去東西」：推播類＝不看就失去（天數歸零、能力值退步）；
/// App 內通知類＝東西不會跑掉（獎勵在信箱等、成就解鎖即為己有）。
///
/// 超出上限者依優先序**由低至高捨棄** —— 本頁把被捨棄的那些也列出來，
/// 否則「為什麼我沒收到提醒」永遠答不出來。
///
/// 「先前的推播」同理：紅點數的是全部的未讀，本頁若只列今天的，
/// 昨天那則未讀就從畫面上消失，而紅點還在數它。
/// **紅點數得到的每一則，這一頁都要列得出來。**
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final sent = s.todaysPushes;
    final suppressed = s.suppressedPushes;
    final earlier = s.earlierPushes;
    final inApp = s.notifications
        .where((n) => n.kind == NotifyKind.inApp)
        .toList();

    return Scaffold(
      backgroundColor: C.bgPage,
      appBar: AppBar(
        title: const Text('通知'),
        actions: [
          TextButton(
            onPressed: s.unreadNotifications == 0
                ? null
                : () {
                    s.markAllNotificationsRead();
                    setState(() {});
                  },
            child: Text(
              '全部已讀',
              style: T.body(
                color: s.unreadNotifications == 0
                    ? C.textDisabled
                    : C.actionOutline,
              ),
            ),
          ),
        ],
      ),
      // A 清單型骨架：首屏約六列通知。
      body: LoadBoundary(
        id: 'notifications',
        kind: SkeletonKind.listA,
        rows: 6,
        padding: EdgeInsets.zero,
        builder: (context) => ListView(
          padding: const EdgeInsets.fromLTRB(
            S.base,
            S.base,
            S.base,
            S.scrollBottom,
          ),
          children: [
            const SectionTitle('今日推播'),
            if (sent.isEmpty)
              AppCard(child: Text('今天沒有推播。', style: T.caption()))
            else
              ListGroup(
                rows: [
                  for (var i = 0; i < sent.length; i++)
                    _row(s, sent[i], i != sent.length - 1),
                ],
              ),

            if (suppressed.isNotEmpty) ...[
              const SectionTitle('今日未送出', trailing: '超出上限'),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '同日推播已達上限，以下依優先序由低至高被捨棄。'
                      '任務仍在，只是不另外打斷你。',
                      style: T.caption(),
                    ),
                    const SizedBox(height: S.md),
                    for (final n in suppressed) ...[
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              n.title,
                              style: T.body(color: C.textSecondary),
                            ),
                          ),
                          TagBadge(notifyPriorityNames[n.priority]!),
                        ],
                      ),
                      const SizedBox(height: S.sm),
                    ],
                  ],
                ),
              ),
            ],

            if (earlier.isNotEmpty) ...[
              const SectionTitle('先前的推播'),
              ListGroup(
                rows: [
                  for (var i = 0; i < earlier.length; i++)
                    _row(s, earlier[i], i != earlier.length - 1),
                ],
              ),
            ],

            const SectionTitle('App 內通知'),
            if (inApp.isEmpty)
              AppCard(child: Text('沒有 App 內通知。', style: T.caption()))
            else
              ListGroup(
                rows: [
                  for (var i = 0; i < inApp.length; i++)
                    _row(s, inApp[i], i != inApp.length - 1),
                ],
              ),
          ],
        ),
      ),
    );
  }

  ListRow _row(AppState s, AppNotification n, bool divider) => ListRow(
    // 未讀紅點。已讀的不留空位，否則整排文字會對不齊。
    leading: n.read
        ? null
        : Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: S.sm),
            decoration: const BoxDecoration(
              color: C.statusError,
              shape: BoxShape.circle,
            ),
          ),
    title: n.title,
    subtitle: '${n.body}　·　${_stamp(n.at)}',
    trailing: n.priority == null
        ? null
        : TagBadge(notifyPriorityNames[n.priority]!),
    showDivider: divider,
    onTap: () {
      s.markNotificationRead(n);
      setState(() {});
    },
  );

  static String _stamp(DateTime t) {
    final now = appNow();
    final sameDay =
        t.year == now.year && t.month == now.month && t.day == now.day;
    final hm =
        '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
    return sameDay ? '今天 $hm' : '${t.month}/${t.day} $hm';
  }
}
