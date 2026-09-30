import 'package:flutter/material.dart';

import '../../domain/community.dart';
import '../../domain/admin.dart';
import '../../design/skeleton.dart';
import '../../state/app_state.dart';
import '../../widgets/load_boundary.dart';
import 'find_people_screen.dart';
import 'report_sheet.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

class _Tabs extends StatelessWidget {
  const _Tabs();

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(16, 4, 0, 8),
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
          labelStyle: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
          tabs: [
            Tab(text: '一般訊息'),
            Tab(text: '陌生訊息'),
          ],
        ),
      );
}

/// Read Model：對話清單 —— 一般訊息 / 陌生訊息兩個分頁。
class ConversationsScreen extends StatelessWidget {
  const ConversationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(child: _Tabs()),
              // **找人的入口。**
              //
              // 在此之前要進到別人的公開檔案（「開始聊天」在那裡）只有
              // 兩條路：動態牆上點貼文作者，或自己的關注／粉絲清單。
              // 於是「私訊一個還沒關注、也還沒發過文的人」在 App 裡
              // 做不到 —— 而「陌生訊息」這個分頁的存在本身就說明
              // 那是預期內的情境。
              IconButton(
                icon: const Icon(Icons.person_search_outlined),
                tooltip: '找人',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const FindPeopleScreen()),
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _List(
                  items: s.visibleConversations
                      .where((c) => s.bucketOf(c) == MessageCategory.normal)
                      .toList(),
                ),
                _List(
                  items: s.visibleConversations
                      .where((c) => s.bucketOf(c) == MessageCategory.stranger)
                      .toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 使用者已刪除對話。**單方刪除**，且刪除只發生在對話層級 ——
/// 單則訊息一經發送即不可刪除。
Future<void> _delete(BuildContext context, Conversation c) async {
  final s = AppScope.of(context);
  final ok = await showAppDialog(
    context,
    title: '刪除與「${s.nameOf(c.peer, uid: c.peerUid)}」的對話？',
    message: '只會從你這一側消失，對方仍看得到這段對話。'
        '訊息本身不會被刪除。',
    confirmLabel: '刪除',
    destructive: true,
  );
  if (ok != true) return;
  s.deleteConversation(c);
}

class _List extends StatelessWidget {
  final List<Conversation> items;
  const _List({required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const EmptyState(
        icon: Icons.chat_bubble_outline,
        title: '沒有訊息',
        message: '在個人檔案頁或教官清單找到對象後，就能開始對話。',
      );
    }
    // 依最後一則訊息時戳排序
    final sorted = items.toList()
      ..sort(
        (a, b) =>
            (b.last?.at ?? DateTime(0)).compareTo(a.last?.at ?? DateTime(0)),
      );

    // **下拉重新整理是「沒有即時訂閱」的代償。** 跨使用者的東西只在
    // 登入時載入一次，對方傳了訊息我這邊要登出再登入才看得到。
    return RefreshIndicator(
      onRefresh: AppScope.of(context).refreshInbound,
      child: ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 50),
      // 內容不足一頁時也要拉得動，否則沒有訊息的人反而刷不了。
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        for (final c in sorted)
          // 對方現在的名字。`c.peer` 是開這個對話當下存下來的 ——
          // 與旁邊的階級、教官徽章同一套。
          if (AppScope.of(context).nameOf(c.peer, uid: c.peerUid)
              case final peer)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Panel(
              padding: const EdgeInsets.all(13),
              child: InkWell(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ChatScreen(conversation: c),
                  ),
                ),
                // 長按刪除對話。單方刪除，對方那一側不受影響。
                onLongPress: () => _delete(context, c),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: AppColors.surfaceAlt,
                      child: Text(
                        peer.characters.first,
                        style: const TextStyle(
                          color: AppColors.accent,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                peer,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              // 對方**現在**是不是教官。`c.peerIsInstructor`
                              // 是開這個對話當下存的 —— 教官身分會被撤銷。
                              if (AppScope.of(context).isInstructorOf(c.peer,
                                  uid: c.peerUid,
                                  fallback: c.peerIsInstructor)) ...[
                                const SizedBox(width: 6),
                                const Pill('教官'),
                              ],
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            c.last?.text ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textDim,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (c.unread > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: C.statusError,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${c.unread}',
                          style: const TextStyle(
                            color: AppColors.onAccent,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    ),
    );
  }
}

/// Read Model：對話內容
class ChatScreen extends StatefulWidget {
  final Conversation conversation;
  const ChatScreen({super.key, required this.conversation});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final s = AppScope.of(context);
      s.markRead(widget.conversation);
      _offerFollow(s);
    });
  }

  /// 陌生訊息：問一次要不要追蹤對方。
  ///
  /// 使用者要求（2026-09-27）：「如果 A 沒追蹤 B，B 私訊 A 會被丟到
  /// 陌生訊息，如果 A 看訊息當下還沒追蹤 B，會跳出是否要追蹤對方。」
  ///
  /// **同一個對象在同一次開啟期間只問一次**（使用者裁決）。
  /// 每次開都問的話，同一個人傳十則訊息就會被問十次 —— 那是騷擾。
  /// 「一次開啟期間」＝這個 State 的生命週期：退出去再進來會再問一次，
  /// 那是他自己又點進來的，不算打擾。
  bool _asked = false;

  Future<void> _offerFollow(AppState s) async {
    if (_asked) return;
    _asked = true;
    // 已經追蹤了就沒事；不是陌生訊息也沒事。
    if (s.bucketOf(widget.conversation) != MessageCategory.stranger) return;
    if (s.isFollowing(widget.conversation.peer,
        uid: widget.conversation.peerUid)) {
      return;
    }

    final ok = await showAppDialog(
      context,
      title: '要追蹤 ${s.nameOf(widget.conversation.peer, uid: widget.conversation.peerUid)} 嗎？',
      // **不要承諾「追蹤之後就會進一般訊息」** —— 那是假的。
      // 規格：一般訊息要的是**互相關注**（或師徒、同隊），
      // 我單方追蹤不夠。承諾了而它沒發生，使用者只會以為功能壞了。
      message: '他不在你的關注名單裡，所以這段對話在「陌生訊息」。\n\n'
          '追蹤之後你會在動態牆看到他的貼文；'
          '等他也追蹤你（或你們成為師徒、隊友），這段對話才會移到一般訊息。',
      confirmLabel: '追蹤',
      cancelLabel: '先不要',
    );
    if (ok != true || !mounted) return;
    s.toggleFollow(widget.conversation.peer,
        uid: widget.conversation.peerUid);
    if (mounted) {
      showToast(context,
          '已追蹤 ${s.nameOf(widget.conversation.peer, uid: widget.conversation.peerUid)}');
    }
  }

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = widget.conversation;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        surfaceTintColor: Colors.transparent,
        title: Row(
          children: [
            Text(
              // 對方現在的名字。`c.peer` 是開這個對話當下存下來的。
              s.nameOf(c.peer, uid: c.peerUid),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 8),
            Text(
              // 對方現在的階級。`c.peerRank` 是開這個對話當下存下來的，
              // 只在查不到他的公開檔案時墊底。
              '${s.rankOf(c.peer, uid: c.peerUid, fallback: c.peerRank)} 階',
              style: const TextStyle(color: AppColors.textDim, fontSize: 11.5),
            ),
            if (s.isInstructorOf(c.peer,
                uid: c.peerUid, fallback: c.peerIsInstructor)) ...[
              const SizedBox(width: 6),
              const Pill('教官'),
            ],
          ],
        ),
        actions: [
          IconButton(
            onPressed: () => showReportSheet(
              context,
              target: ReportTarget.message,
              targetKey: reportKey(ReportTarget.message, c.id),
              content: c.messages.isEmpty ? '（無訊息）' : c.messages.last.text,
              accused: c.peer,
              accusedUid: c.peerUid,
            ),
            icon: const Icon(Icons.flag_outlined, size: 18),
          ),
        ],
      ),
      body: Column(
        children: [
          // D 對話型骨架：泡泡左右交錯，首屏約五則。
          Expanded(
            child: LoadBoundary(
              id: 'chat:${c.id}',
              kind: SkeletonKind.chatD,
              rows: 5,
              builder: (context) => ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 50),
                children: [for (final m in c.messages) _Bubble(msg: m)],
              ),
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(
              12,
              8,
              12,
              MediaQuery.of(context).padding.bottom + 8,
            ),
            color: AppColors.surface,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: ctrl,
                    style: const TextStyle(fontSize: 13.5),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: '輸入訊息…',
                      hintStyle: const TextStyle(
                        color: AppColors.textFaint,
                        fontSize: 13,
                      ),
                      filled: true,
                      fillColor: AppColors.surfaceAlt,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  onPressed: () {
                    // 停權中的社群互動要說得出理由 —— 靜靜地什麼都不發生，
                    // 使用者只會以為 App 壞了。
                    final blocked = s.communityBlockedReason;
                    if (blocked != null) {
                      showToast(context, blocked);
                      return;
                    }
                    final v = s.sendMessage(c, ctrl.text);
                    // 被攔截時**不清空輸入框** —— 訊息沒送出去，
                    // 把使用者剛打的字清掉等於連內容都拿不回來。
                    if (v == FilterVerdict.blocked) {
                      showToast(context, '這則訊息含明顯違規內容，未送出。');
                      return;
                    }
                    // 送上雲是即發即忘的，失敗會晚一點才回來 ——
                    // 等一拍再看有沒有錯誤，有就講出來。
                    Future<void>.delayed(const Duration(seconds: 2), () {
                      if (!context.mounted) return;
                      final err = s.consumeChatSendError();
                      if (err != null) {
                        showToast(context, '這則訊息沒有送到對方那裡，重新載入後會消失。');
                      }
                    });
                    if (v == FilterVerdict.flagged) {
                      showToast(context, '已送出。內容經自動過濾標記待審。');
                    }
                    ctrl.clear();
                  },
                  icon: const Icon(Icons.send_rounded, color: AppColors.accent),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final ChatMessage msg;
  const _Bubble({required this.msg});

  @override
  Widget build(BuildContext context) => Align(
    alignment: msg.fromMe ? Alignment.centerRight : Alignment.centerLeft,
    child: Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.72,
      ),
      decoration: BoxDecoration(
        color: msg.fromMe ? AppColors.accent : AppColors.surface,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(14),
          topRight: const Radius.circular(14),
          bottomLeft: Radius.circular(msg.fromMe ? 14 : 4),
          bottomRight: Radius.circular(msg.fromMe ? 4 : 14),
        ),
        border: msg.fromMe ? null : Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // 已下架的訊息留下佔位，不整則消失 ——
          // 資料保留是為了申訴時調得回來，而收訊方也該知道發生過什麼。
          Text(
            msg.deleted ? '此訊息已由管理員下架' : msg.text,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.55,
              fontStyle: msg.deleted ? FontStyle.italic : FontStyle.normal,
              color: msg.deleted
                  ? (msg.fromMe
                      ? AppColors.onAccent.withValues(alpha: 0.7)
                      : AppColors.textFaint)
                  : (msg.fromMe ? AppColors.onAccent : AppColors.text),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '${msg.at.hour.toString().padLeft(2, '0')}:'
            '${msg.at.minute.toString().padLeft(2, '0')}'
            '${msg.fromMe && msg.read ? ' 已讀' : ''}',
            style: TextStyle(
              fontSize: 9.5,
              color: msg.fromMe
                  ? AppColors.onAccent.withValues(alpha: 0.7)
                  : AppColors.textFaint,
            ),
          ),
        ],
      ),
    ),
  );
}
