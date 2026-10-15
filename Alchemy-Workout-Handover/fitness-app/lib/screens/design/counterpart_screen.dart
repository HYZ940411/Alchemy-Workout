import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../domain/admin.dart';
import '../../domain/community.dart';
import '../../domain/commerce.dart';
import '../../domain/custom_plan.dart';
import '../../domain/inbound.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

/// 模擬對方
///
/// 事件風暴裡有一半的流程需要第二個人 —— 隊長核准我的申請、教官接受我的
/// 拜師、隊友完成限時任務、對方回我私訊。這個 demo 只有一位使用者，
/// 那一半永遠不會發生，於是那些畫面看起來是活的，實際上是死路。
///
/// 這一頁把「別人那一側」的每個動作列成按鈕，讓一台機器上就能把兩邊都走完。
/// **它不是後門**：每個按鈕呼叫的都是與真實路徑同一個方法，
/// 我這一側的 Precondition 一條都不繞過 —— 差別只在誰按下送出。
class CounterpartScreen extends StatefulWidget {
  const CounterpartScreen({super.key});

  @override
  State<CounterpartScreen> createState() => _CounterpartScreenState();
}

class _CounterpartScreenState extends State<CounterpartScreen> {
  /// 假名字池。用既有的關注者名單，畫面上才不會冒出憑空的人。
  static const _pool = ['林彥廷', '陳怡君', '張家豪', '李宛蓉', '王柏森'];

  int _seq = 0;
  String _name(AppState s) {
    final used = {
      ...s.followers.map(s.followName),
      ...s.following.map(s.followName),
      ...?s.myTeam?.members.map((m) => m.name),
      ...s.apprentices.map((a) => a.name),
      ...s.inbox.map((r) => r.from),
    };
    for (final n in _pool) {
      if (!used.contains(n)) return n;
    }
    return '路人${++_seq}';
  }

  void _do(String message, void Function() action) {
    action();
    if (!mounted) return;
    showToast(context, message);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return Scaffold(
      backgroundColor: C.bgPage,
      appBar: AppBar(title: const Text('模擬對方')),
      body: ListView(
        padding:
            const EdgeInsets.fromLTRB(S.base, S.base, S.base, S.scrollBottom),
        children: [
          AppCard(
            child: Text(
              '這一頁扮演「另一個使用者」。每個按鈕走的都是真實路徑，'
              '我這一側的 Precondition 一條都不放行 —— '
              '接不了的請求照樣接不了，只是現在對方真的會動了。',
              style: T.caption(),
            ),
          ),
          ..._team(s),
          ..._mentor(s),
          ..._social(s),
          ..._admin(s),
          ..._time(s),
        ],
      ),
    );
  }

  // ── 團隊 ────────────────────────────────────────────────────

  List<Widget> _team(AppState s) {
    final t = s.myTeam;
    final rows = <ListRow>[];

    // 我送出的加入申請 —— 隊長那一側的兩個分支。
    for (final a in s.sentApplications) {
      rows.add(ListRow(
        title: '「${a.name}」的隊長核准我',
        subtitle: '我在 ${_left(a.expiresAt, s)}內等回應',
        trailing: const Icon(Icons.check, size: Sz.iconDense),
        onTap: () => _do('隊長核准了', () {
          s.resolveTeamApplication(a.name, RequestVerdict.accepted);
        }),
      ));
      rows.add(ListRow(
        title: '「${a.name}」的隊長拒絕我',
        trailing: const Icon(Icons.close, size: Sz.iconDense),
        onTap: () => _do('隊長拒絕了', () {
          s.resolveTeamApplication(a.name, RequestVerdict.rejected);
        }),
      ));
    }

    // 隊長邀請我 —— 模型有這條路徑，先前 App 完全沒有。
    if (t == null) {
      for (final p in s.publicTeams.take(3)) {
        if (s.inbox.any((r) =>
            r.kind == InboundKind.teamInvite && r.subject == p.name)) {
          continue;
        }
        final leader = p.members
            .where((m) => m.role == TeamRole.leader)
            .firstOrNull;
        rows.add(ListRow(
          title: '「${p.name}」的隊長邀請我',
          subtitle: p.isFull ? '這支已滿，接受時會被擋下' : '進收件匣，7 天內回應',
          onTap: () => _do('邀請已寄到收件匣', () {
            s.receiveInbound(InboundRequest(
              id: s.newId('in-'),
              kind: InboundKind.teamInvite,
              from: leader?.name ?? p.name,
              fromRank: leader?.rank ?? 1,
              subject: p.name,
              sentAt: s.now,
            ));
          }),
        ));
      }
    }

    // 我是隊長那一側 —— 有人申請、有人完成限時任務。
    if (t != null) {
      if (s.iAmLeader && t.isPublic && !t.isFull) {
        rows.add(ListRow(
          title: '有人申請加入「${t.name}」',
          subtitle: '進團隊頁的待處理申請，你可以核准或拒絕',
          onTap: () => _do('收到一筆加入申請', () {
            s.peerAppliesToMyTeam(_name(s), math.max(1, s.rank - 5));
          }),
        ));
      }
      for (final m in t.members) {
        if (m.name == s.displayName) continue;
        if (t.timedCredited.contains(m.name)) continue;
        rows.add(ListRow(
          title: '${m.name} 完成了今日限時任務',
          subtitle: '團隊限時分數 +$kTimedTaskPerMember，全員完成再加 $kTimedTaskAllBonus',
          onTap: () => _do('${m.name} 完成了', () {
            s.teammateCompletesTimedTask(m.name);
          }),
        ));
      }
    }

    if (rows.isEmpty) return const [];
    return [
      const SectionTitle('團隊'),
      ListGroup(rows: rows),
    ];
  }

  // ── 師徒 ────────────────────────────────────────────────────

  List<Widget> _mentor(AppState s) {
    final rows = <ListRow>[];

    for (final a in s.mentorApplications) {
      rows.add(ListRow(
        title: '${a.name} 接受我的拜師申請',
        onTap: () => _do('${a.name} 收你為徒了', () {
          s.resolveMentorApplication(a.name, RequestVerdict.accepted);
        }),
      ));
      rows.add(ListRow(
        title: '${a.name} 拒絕我的拜師申請',
        subtitle: '拒絕後釋放對方的帶徒名額，可再次申請',
        onTap: () => _do('${a.name} 拒絕了', () {
          s.resolveMentorApplication(a.name, RequestVerdict.rejected);
        }),
      ));
    }

    // 申請方角色＝教官的那一向。〈師徒申請 Aggregate〉明載雙向皆可。
    if (s.myInstructor == null) {
      final i = s.instructors
          .where((x) => !s.inbox.any((r) => r.from == x.name))
          .firstOrNull;
      if (i != null) {
        rows.add(ListRow(
          title: '${i.name} 主動邀我當學徒',
          subtitle: '進收件匣。這是模型裡「申請方角色＝教官」的那一向',
          onTap: () => _do('邀請已寄到收件匣', () {
            s.receiveInbound(InboundRequest(
              id: s.newId('in-'),
              kind: InboundKind.mentorInvite,
              from: i.name,
              fromRank: i.rank,
              subject: i.name,
              sentAt: s.now,
            ));
          }),
        ));
      }
    }

    for (final a in s.apprentices) {
      rows.add(ListRow(
        title: '${a.name} 給我的任務 5 星',
        subtitle: '我的聲望 ${s.instructorReputation}　'
            '本週已計 ${s.apprenticeTaskRatings[a.name] ?? 0} / '
            '$kMentorTaskRatingWeeklyCap 次',
        onTap: () => _do('聲望上升', () => s.apprenticeRatesMe(a.name, 5)),
      ));
      rows.add(ListRow(
        title: '${a.name} 給我的任務 1 星',
        onTap: () => _do('聲望下降', () => s.apprenticeRatesMe(a.name, 1)),
      ));
      if (!s.apprenticeWeeklyRated.contains(a.name)) {
        rows.add(ListRow(
          title: '${a.name} 評本週互動 5 星',
          subtitle: '每人每週一次，幅度比單次任務大得多',
          onTap: () => _do('聲望大幅上升',
              () => s.apprenticeRatesMe(a.name, 5, weekly: true)),
        ));
      }
    }

    if (s.isInstructor) {
      rows.add(ListRow(
        title: '有人想拜我為師',
        subtitle: '帶徒名額 ${s.apprentices.length} / ${s.apprenticeCap}',
        onTap: () => _do('拜師申請已寄到收件匣', () {
          final n = _name(s);
          s.receiveInbound(InboundRequest(
            id: s.newId('in-'),
            kind: InboundKind.apprenticeApply,
            from: n,
            fromRank: math.max(1, s.rank - 12),
            subject: n,
            sentAt: s.now,
          ));
        }),
      ));
    }

    if (rows.isEmpty) return const [];
    return [
      const SectionTitle('師徒'),
      ListGroup(rows: rows),
    ];
  }

  // ── 社群 ────────────────────────────────────────────────────

  List<Widget> _social(AppState s) {
    final myPost =
        s.visiblePosts.where((p) => p.author == s.displayName).firstOrNull;
    final chat = s.conversations.where((c) => !c.deletedByMe).firstOrNull;

    return [
      const SectionTitle('社群'),
      ListGroup(rows: [
        ListRow(
          title: '有人關注我',
          subtitle: '目前 ${s.followers.length} 位，歷史最高 ${s.peakFollowerCount}',
          onTap: () => _do('多了一位追蹤者', () => s.gainFollower(_name(s))),
        ),
        if (s.followers.isNotEmpty)
          ListRow(
            title: '${s.followName(s.followers.first)} 取消關注我',
            subtitle: '粉絲數會少一位，但已解鎖的粉絲成就不撤銷',
            onTap: () => _do('少了一位追蹤者',
                () => s.loseFollower(s.followers.first)),
          ),
        if (myPost != null)
          ListRow(
            title: '有人按讚我的貼文',
            subtitle: '目前 ${myPost.likes} 讚。獎勵發給按讚的人，不是我',
            onTap: () => _do('+1 讚', () => s.peerLikesPost(myPost)),
          ),
        if (myPost != null)
          ListRow(
            title: '有人留言我的貼文',
            subtitle: '目前 ${myPost.comments.where((c) => !c.deleted).length} 則',
            onTap: () => _do('多了一則留言', () {
              s.peerCommentsPost(myPost, _name(s), '這組看起來很扎實，請問組間休息多久？');
            }),
          ),
        if (chat != null)
          ListRow(
            title: '${chat.peer} 回我訊息',
            subtitle: '對方的訊息一樣要過內容過濾',
            onTap: () => _do('${chat.peer} 回了一則', () {
              s.peerReplies(chat, '收到，我今天也練完了，明天一起？');
            }),
          ),
        if (myPost != null)
          ListRow(
            title: '有人檢舉我的貼文',
            subtitle: '進管理員待審佇列。這是「檢舉 → 審核 → 處罰 → 申訴」的入口',
            onTap: () => _do('已進入待審佇列', () {
              s.peerReportsMe(myPost, _name(s), '不實訊息');
            }),
          ),
        if (chat != null)
          ListRow(
            title: '${chat.peer} 傳了一則違規訊息',
            subtitle: '過濾命中 → 自動開案，被記名的是對方',
            onTap: () => _do('已自動送審', () {
              s.peerReplies(chat, '我朋友有在用類固醇，效果不錯');
            }),
          ),
      ]),
    ];
  }

  // ── 管理員 ──────────────────────────────────────────────────
  //
  // 這幾件先前要繞到「管理員後台」才做得到，而且是**我自己**去按 ——
  // 等於自己審自己的案子。這裡改由審核組的另一位管理員執行，
  // 案件的處理人欄位才留得下正確的名字。

  List<Widget> _admin(AppState s) {
    final who = s.otherReviewer;
    final rows = <ListRow>[];

    // 針對我的檢舉案。審視與判定是兩個 Command，這裡一次走完。
    for (final c in s.reports.where((c) =>
        c.accused == s.displayName &&
        (c.state == CaseState.pending || c.state == CaseState.reviewing))) {
      rows.add(ListRow(
        title: '${who.name} 判定「${c.reason}」成立',
        subtitle: '我會受處罰。累犯級距由階梯制決定，管理員不裁量',
        onTap: () => _do('檢舉成立，處罰已下', () {
          s.runAsAdmin(who, () {
            s.reviewReport(c);
            s.upholdReport(c);
          });
        }),
      ));
      rows.add(ListRow(
        title: '${who.name} 判定「${c.reason}」不成立',
        subtitle: '內容不下架，違規次數不變',
        onTap: () => _do('檢舉不成立', () {
          s.runAsAdmin(who, () {
            s.reviewReport(c);
            s.dismissReport(c);
          });
        }),
      ));
    }

    // 我送出的申訴。
    for (final c in s.appeals.where((c) =>
        c.appellant == s.displayName &&
        (c.state == CaseState.pending || c.state == CaseState.reviewing))) {
      rows.add(ListRow(
        title: '${who.name} 判定我的申訴成立',
        subtitle: '處罰撤銷，累計違規 −1',
        onTap: () => _do('申訴成立，處罰已撤銷', () {
          s.runAsAdmin(who, () {
            s.reviewAppeal(c);
            s.upholdAppeal(c);
          });
        }),
      ));
      rows.add(ListRow(
        title: '${who.name} 駁回我的申訴',
        subtitle: '原處罰維持不變，違規次數也不變',
        onTap: () => _do('申訴已駁回', () {
          s.runAsAdmin(who, () {
            s.reviewAppeal(c);
            s.dismissAppeal(c);
          });
        }),
      ));
    }

    // 我的教官申請。
    for (final c in s.instructorCases.where((c) =>
        c.applicant == s.displayName && c.state == CaseState.pending)) {
      rows.add(ListRow(
        title: '${who.name} 通過我的教官申請',
        subtitle: '簡答題人工審核 —— 這一步不是我按得到的',
        onTap: () => _do('你成為教官了', () {
          s.runAsAdmin(who, () => s.decideInstructor(c, true));
        }),
      ));
      rows.add(ListRow(
        title: '${who.name} 駁回我的教官申請',
        subtitle: '駁回階段記為「管理員審核」，滿 14 天可重考',
        onTap: () => _do('教官申請已駁回', () {
          s.runAsAdmin(who, () => s.decideInstructor(c, false));
        }),
      ));
    }

    // 我申請公開的自訂訓練。
    for (final p in s.customPlans
        .where((p) => p.isMine && p.state == CustomPlanState.pendingPublic)) {
      rows.add(ListRow(
        title: '${who.name} 核准「${p.name}」公開',
        onTap: () => _do('已公開', () {
          s.runAsAdmin(who, () => s.approvePublicPlan(p));
        }),
      ));
      rows.add(ListRow(
        title: '${who.name} 退回「${p.name}」',
        subtitle: '退回已發布，自己仍可用，改完可再申請',
        onTap: () => _do('已退回', () {
          s.runAsAdmin(who, () => s.rejectPublicPlan(p, '動作說明不足'));
        }),
      ));
    }

    for (final o in s.orders.where((o) => o.awaitingDelivery)) {
      rows.add(ListRow(
        title: '「${o.productName}」發放成功',
        subtitle: '虛擬商品由系統發放，不是誰按的',
        onTap: () => _do('已發放', () => s.deliverOrder(o)),
      ));
      rows.add(ListRow(
        title: '「${o.productName}」發放失敗',
        subtitle: '重試 ${o.deliveryRetries} / $kDeliveryMaxRetries 次，'
            '用完轉人工處理',
        onTap: () => _do('發放失敗', () => s.deliverOrder(o, fails: true)),
      ));
    }

    if (rows.isEmpty) {
      return [
        const SectionTitle('管理員', trailing: '由審核組的另一位執行'),
        AppCard(
          child: Text(
            '目前沒有跟你有關的待審案件。'
            '先在上面讓人檢舉你，或去「教官申請」作答測驗，這裡就會出現。',
            style: T.caption(),
          ),
        ),
      ];
    }
    return [
      const SectionTitle('管理員', trailing: '由審核組的另一位執行'),
      ListGroup(rows: rows),
    ];
  }

  // ── 時間 ────────────────────────────────────────────────────

  List<Widget> _time(AppState s) {
    final pending = s.sentApplications.length +
        s.mentorApplications.length +
        s.liveInbox.length;
    return [
      const SectionTitle('時間', trailing: '逾期是系統排程，不是誰的動作'),
      ListGroup(rows: [
        ListRow(
          title: '快轉 8 天，讓待回應的都逾期',
          subtitle: pending == 0 ? '目前沒有待回應的請求' : '目前有 $pending 筆待回應',
          onTap: () => _do('已快轉 8 天', () {
            s.advanceDemoClock(const Duration(days: 8));
          }),
        ),
      ]),
    ];
  }

  String _left(DateTime at, AppState s) {
    final d = at.difference(s.now);
    if (d.isNegative) return '0 小時';
    return d.inDays >= 1 ? '${d.inDays} 天' : '${d.inHours} 小時';
  }
}
