import 'dart:async';
import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../domain/community.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import '../shop/ai_credits_screen.dart';

/// AI 調整對話
///
/// §5.7【例外】AI 訓練前／訓練中調整為**多輪對話往返**，且對話內容須完整留存，
/// **不使用彈窗／抽屜／Toast 任何一種容器，應為整頁**。
class AiAdjustScreen extends StatefulWidget {
  final AiSource source;
  const AiAdjustScreen({super.key, required this.source});
  @override
  State<AiAdjustScreen> createState() => _AiAdjustScreenState();
}

class _AiAdjustScreenState extends State<AiAdjustScreen> {
  final ctrl = TextEditingController();
  final scroll = ScrollController();
  Timer? analyzeTimer;

  AiSource get src => widget.source;

  @override
  void dispose() {
    ctrl.dispose();
    scroll.dispose();
    analyzeTimer?.cancel();
    super.dispose();
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scroll.hasClients) {
        scroll.animateTo(scroll.position.maxScrollExtent,
            duration: kAnim, curve: Curves.easeOut);
      }
    });
  }

  void _startAnalyzing(AppState s) {
    analyzeTimer?.cancel();
    // 沒接外部 API 時這段延遲是**模擬**呼叫的等待；接上之後它是送出前的
    // 一小段緩衝，真正的等待發生在 aiProduceSuggestionAsync 裡面。
    analyzeTimer = Timer(const Duration(milliseconds: 900), () async {
      if (!mounted) return;
      await s.aiProduceSuggestionAsync(src);
      if (mounted) _toBottom();
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final turns = s.aiConversations[src]!;
    final stage = s.aiStage[src]!;

    return Scaffold(
      backgroundColor: C.bgPage,
      appBar: AppBar(
        title: Text(aiSourceNames[src]!),
        actions: [
          if (aiCostsCredit(src))
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: S.base),
                child: ValueUnit(
                  value: '${s.aiTotal}',
                  unit: '點',
                  style: T.numberS(),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          _ScopeBanner(source: src, costs: aiCostsCredit(src)),
          Expanded(
            child: turns.isEmpty
                ? _Intro(source: src)
                : ListView.builder(
                    controller: scroll,
                    padding: const EdgeInsets.fromLTRB(
                        S.base, S.base, S.base, S.base),
                    itemCount: turns.length + (stage == AiStage.analyzing ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (i >= turns.length) return const _Analyzing();
                      return _Turn(turn: turns[i]);
                    },
                  ),
          ),
          _Composer(
            state: s,
            source: src,
            stage: stage,
            ctrl: ctrl,
            onSent: () {
              _toBottom();
              if (s.aiStage[src] == AiStage.analyzing) _startAnalyzing(s);
            },
          ),
        ],
      ),
    );
  }
}

class _ScopeBanner extends StatelessWidget {
  final AiSource source;
  final bool costs;
  const _ScopeBanner({required this.source, required this.costs});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        color: C.bgSurface,
        padding: const EdgeInsets.fromLTRB(S.base, S.md, S.base, S.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline,
                size: Sz.iconDense, color: C.accentInfo),
            const SizedBox(width: S.sm),
            Expanded(
              child: Text(
                '${aiSourceScope[source]}'
                '${costs ? '　·　本次消耗 1 點' : '　·　會員權益，不扣點'}',
                style: T.caption(),
              ),
            ),
          ],
        ),
      );
}

class _Intro extends StatelessWidget {
  final AiSource source;
  const _Intro({required this.source});

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(
            S.base, S.base, S.base, S.scrollBottom),
        children: [
          const EmptyState(
            icon: Icons.auto_awesome_outlined,
            title: '告訴 AI 你想怎麼調',
            message: '例如「今天肩膀有點緊，想降低推的強度」。AI 會先與你確認需求再產出建議。',
          ),
        ],
      );
}

class _Turn extends StatelessWidget {
  final AiTurn turn;
  const _Turn({required this.turn});

  @override
  Widget build(BuildContext context) {
    // 系統訊息置中呈現，與對話往返區分
    if (turn.role == AiTurnRole.system) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: S.md),
        child: AppCard(
          color: C.bgSurface,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.settings_suggest_outlined,
                  size: Sz.iconDense, color: C.textSecondary),
              const SizedBox(width: S.sm),
              Expanded(child: Text(turn.text, style: T.caption())),
            ],
          ),
        ),
      );
    }

    final mine = turn.role == AiTurnRole.user;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: S.md),
        padding: const EdgeInsets.symmetric(horizontal: S.base, vertical: S.md),
        constraints: BoxConstraints(maxWidth: mine ? 280 : 260),
        decoration: BoxDecoration(
          color: mine ? C.actionOutline : C.bgSurface,
          borderRadius: BorderRadius.circular(R.card),
          border: mine ? null : Border.all(color: C.lineDivider),
        ),
        child: Text(
          turn.text,
          style: T.body(color: mine ? C.textOnDark : C.textPrimary),
        ),
      ),
    );
  }
}

class _Analyzing extends StatelessWidget {
  const _Analyzing();
  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: S.md),
          padding: const EdgeInsets.symmetric(horizontal: S.base, vertical: S.md),
          decoration: BoxDecoration(
            color: C.bgSurface,
            borderRadius: BorderRadius.circular(R.card),
            border: Border.all(color: C.lineDivider),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: C.textSecondary),
              ),
              const SizedBox(width: S.md),
              Text('分析中…', style: T.body(color: C.textSecondary)),
            ],
          ),
        ),
      );
}

class _Composer extends StatelessWidget {
  final AppState state;
  final AiSource source;
  final AiStage stage;
  final TextEditingController ctrl;
  final VoidCallback onSent;
  const _Composer({
    required this.state,
    required this.source,
    required this.stage,
    required this.ctrl,
    required this.onSent,
  });

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom + S.base;

    Widget wrap(Widget child) => Container(
          decoration: const BoxDecoration(
            color: C.bgSurface,
            border: Border(top: BorderSide(color: C.lineDivider)),
          ),
          padding: EdgeInsets.fromLTRB(S.base, S.md, S.base, bottom),
          child: child,
        );

    switch (stage) {
      // 點數不足：不扣點，導向 AI 點數購買頁
      case AiStage.denied:
        return wrap(Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('AI 點數不足，本次調整已拒絕（未扣點）。',
                style: T.body(color: C.statusError)),
            const SizedBox(height: S.md),
            AppButton(
              label: '前往購買 AI 點數',
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const AiCreditsScreen())),
            ),
          ],
        ));

      case AiStage.proposed:
        return wrap(ButtonRow(
          left: AppButton(
            label: '拒絕調整',
            kind: BtnKind.secondary,
            onPressed: () {
              state.aiReject(source);
              showToast(context, '已拒絕，維持原訓練內容');
            },
          ),
          right: AppButton(
            label: '使用新強度',
            onPressed: () {
              state.aiAccept(source);
              showToast(context, '訓練課表已套用新強度');
            },
          ),
        ));

      case AiStage.applied:
        return wrap(AppButton(
          label: '完成',
          onPressed: () => Navigator.of(context).pop(),
        ));

      // 拒絕後維持原訓練內容，流程結束，不可重新提出調整要求
      case AiStage.rejected:
        return wrap(Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('本次流程已結束，不可重新提出調整要求。',
                style: T.caption()),
            const SizedBox(height: S.md),
            AppButton(
              label: '返回',
              kind: BtnKind.secondary,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ));

      case AiStage.failed:
        return wrap(ButtonRow(
          left: AppButton(
            label: '返回',
            kind: BtnKind.secondary,
            onPressed: () => Navigator.of(context).pop(),
          ),
          right: AppButton(
            label: '稍後再試',
            onPressed: () {
              state.aiReset(source);
              showToast(context, '已重設對話');
            },
          ),
        ));

      case AiStage.analyzing:
        return wrap(Row(
          children: [
            Expanded(
              child: Text('AI 分析中，請稍候…', style: T.caption()),
            ),
            // Demo：手動觸發失敗路徑，供驗收
            TextButton(
              onPressed: () => state.aiFail(source, AiFailReason.timeout),
              child: Text('模擬逾時', style: T.caption(color: C.accentInfo)),
            ),
          ],
        ));

      case AiStage.idle:
      case AiStage.clarifying:
        // 名額分流：名額足夠者須先確認「本次調整將佔用一個自訂訓練名額」。
        // 名額已滿者不擋 —— 擋下等於因為額度問題讓人練一份器材不合的課表。
        // 名額分流**只適用於器材解鎖後的課表調整** ——
        // 使用者主動要求的訓練前微調只改本次快照，與名額無關。
        final blocked = aiUsesPlanQuota(source) && stage == AiStage.idle
            ? state.aiPlanQuotaBlockedReason()
            : null;
        if (blocked != null) {
          return wrap(Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(blocked, style: T.body()),
              const SizedBox(height: S.xs),
              Text('確認只是意願確認，名額要等 AI 真的調整成功之後才被佔用。',
                  style: T.caption()),
              const SizedBox(height: S.md),
              AppButton(
                label: '我知道，開始調整',
                onPressed: () => state.setAiQuotaConsent(true),
              ),
            ],
          ));
        }
        return wrap(Row(
          children: [
            Expanded(
              child: TextField(
                controller: ctrl,
                style: T.body(),
                minLines: 1,
                maxLines: 4,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: stage == AiStage.idle ? '想怎麼調整？' : '回答 AI 的問題…',
                  hintStyle: T.body(color: C.textSecondary),
                  filled: true,
                  fillColor: C.bgPage,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: S.base, vertical: S.md),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: S.sm),
            SizedBox(
              width: Sz.tapTarget,
              height: Sz.tapTarget,
              child: IconButton(
                onPressed: () {
                  final text = ctrl.text.trim();
                  if (text.isEmpty) return;
                  if (stage == AiStage.idle) {
                    state.aiRequest(source, text);
                  } else {
                    state.aiConfirmDemand(source, text);
                  }
                  ctrl.clear();
                  onSent();
                },
                icon: const Icon(Icons.send_rounded, color: C.actionPrimary),
              ),
            ),
          ],
        ));
    }
  }
}
