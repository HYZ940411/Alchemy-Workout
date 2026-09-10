import 'package:flutter/material.dart';

import '../../domain/community.dart';
import '../../domain/admin.dart';
import '../../design/skeleton.dart';
import '../../state/app_state.dart';
import '../../widgets/load_boundary.dart';
import 'report_sheet.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

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
                Tab(text: '一般訊息'),
                Tab(text: '陌生訊息'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _List(
                  items: s.visibleConversations
                      .where((c) => c.bucket == MessageCategory.normal)
                      .toList(),
                ),
                _List(
                  items: s.visibleConversations
                      .where((c) => c.bucket == MessageCategory.stranger)
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
    title: '刪除與「${c.peer}」的對話？',
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

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 50),
      children: [
        for (final c in sorted)
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
                        c.peer.characters.first,
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
                                c.peer,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (c.peerIsInstructor) ...[
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
      if (mounted) AppScope.of(context).markRead(widget.conversation);
    });
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
              c.peer,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 8),
            Text(
              '${c.peerRank} 階',
              style: const TextStyle(color: AppColors.textDim, fontSize: 11.5),
            ),
            if (c.peerIsInstructor) ...[
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
