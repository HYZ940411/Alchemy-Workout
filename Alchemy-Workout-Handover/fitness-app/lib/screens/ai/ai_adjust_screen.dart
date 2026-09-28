import 'dart:async';
import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../domain/ai_adjust.dart';
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
  void initState() {
    super.initState();
    // 一進來就直接問「要怎麼調」，不必先打一句話。
    // **要等第一幀之後** —— `aiOpen` 會 `notifyListeners()`，在 build
    // 期間觸發的話 Flutter 當場拋例外。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AppScope.of(context).aiOpen(src);
    });
  }

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
                    // 「判讀方向」與「產生建議」是兩段等待，兩段都要有跡象。
                    // 在此之前只有後者有 —— 前者那一秒多（失敗時二十秒）
                    // 畫面完全靜止，連使用者自己打的那句話都還沒出現。
                    itemCount: turns.length +
                        (stage == AiStage.analyzing ||
                                (s.aiClassifying[src] ?? false)
                            ? 1
                            : 0),
                    itemBuilder: (context, i) {
                      if (i >= turns.length) {
                        return _Analyzing(
                            label: (s.aiClassifying[src] ?? false)
                                ? '判讀你的需求…'
                                : '分析中…');
                      }
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
    // 建議有結構就排成表格，不塞進對話泡泡。
    //
    // **對話泡泡最寬 260**，而一份建議有四五個動作、每個動作還帶一句理由
    // —— 擠進去就是使用者回報的那一坨字。建議本來就不是一句話，
    // 是一份清單，該佔整個寬度。
    if (turn.suggestion case final sug?) {
      return _SuggestionTable(suggestion: sug, scope: turn.scope);
    }

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
  final String label;
  const _Analyzing({this.label = '分析中…'});
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
              Text(label, style: T.body(color: C.textSecondary)),
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
        // **這裡曾經有一顆「模擬逾時」。** 那是驗收用的 Demo 按鈕，
        // 但它沒有藏在開發者模式後面 —— 使用者等 AI 回話時，
        // 右下角就擺著一顆會讓它失敗的按鈕（2026-09-28 截圖回報）。
        // 失敗路徑由 `ai_source_test.dart` 直接呼叫 `aiFail()` 驗，
        // 不需要畫面上留一個入口。
        return wrap(Text('AI 分析中，請稍候…', style: T.caption()));

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
        return wrap(Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 追問階段直接給三顆按鈕。**打字不是必要的** ——
            // 意圖本來就只有三個值，讓人用猜的去打字，猜不中就換來
            // 一句「我看不懂」，那是把系統的限制變成使用者的問題。
            if (stage == AiStage.clarifying) ...[
              Wrap(
                spacing: S.sm,
                runSpacing: S.sm,
                children: [
                  for (final i in AdjustIntent.values)
                    OutlinedButton(
                      // **要等它。** `aiConfirmDemand` 自 2026-09-27 起是
                      // 非同步的（先問 AI 判方向）—— 不等的話 `onSent()`
                      // 跑的時候 stage 還是 clarifying，見下面那一處的說明。
                      onPressed: () async {
                        await state.aiConfirmDemand(
                            source, adjustIntentNames[i]!);
                        onSent();
                      },
                      child: Text(adjustIntentNames[i]!, style: T.caption()),
                    ),
                ],
              ),
              const SizedBox(height: S.sm),
            ],
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: ctrl,
                    style: T.body(),
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(
                      isDense: true,
                      // 追問階段已經有三顆按鈕，打字是補充說明用的 ——
                      // 那些話會連同意圖一起送給模型當脈絡。
                      hintText: stage == AiStage.idle
                          ? '想怎麼調整？'
                          : '選上面一個方向，或補充說明…',
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
                    // **要等 `aiConfirmDemand` 完成再 `onSent()`。**
                    //
                    // 它自 2026-09-27 起是非同步的（先問 AI 判方向）。
                    // 不等的話，`onSent()` 執行的那一刻 stage 還是
                    // `clarifying` —— 而它裡面的
                    // `if (stage == analyzing) _startAnalyzing()`
                    // 因此永遠不成立：方向判出來了、stage 也變成
                    // `analyzing` 了，卻**沒有任何人去產生建議**。
                    // 畫面就停在「分析中…」轉圈，永遠不會結束。
                    // 使用者回報 P62 C「一直轉圈不停」。
                    onPressed: () async {
                      final text = ctrl.text.trim();
                      if (text.isEmpty) return;
                      ctrl.clear();
                      if (stage == AiStage.idle) {
                        state.aiRequest(source, text);
                      } else {
                        await state.aiConfirmDemand(source, text);
                      }
                      onSent();
                    },
                    icon: const Icon(Icons.send_rounded, color: C.actionPrimary),
                  ),
                ),
              ],
            ),
          ],
        ));
    }
  }
}


/// AI 建議的表格呈現。
///
/// 使用者回報「AI 建議給的排版不好做閱讀。可否用好看的表格呈現？」——
/// 在此之前整份建議被拼成一段字串塞進寬 260 的對話泡泡裡。
///
/// 而那些欄位在 `AdjustChange` 裡本來就是分開的（`title`／`change`／
/// `reason`），是渲染時才被拼掉的。這裡把它們排回兩欄。
///
/// **沒動的那幾列降一階呈現**：一份建議裡多半有一半是「維持不變」，
/// 它們不該跟真正的改動一樣搶眼 —— 但也不能不顯示，
/// 使用者要看得出 AI 把每個動作都看過了。
class _SuggestionTable extends StatelessWidget {
  final AdjustSuggestion suggestion;
  final String? scope;
  const _SuggestionTable({required this.suggestion, this.scope});

  @override
  Widget build(BuildContext context) {
    final changed = suggestion.changes.where((c) => !c.unchanged).length;
    return Padding(
      padding: const EdgeInsets.only(bottom: S.md),
      child: AppCard(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 標題列：這份建議是什麼方向、動了幾個動作。
            Container(
              padding: const EdgeInsets.fromLTRB(S.base, S.md, S.base, S.md),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: C.lineDivider)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome_outlined,
                      size: Sz.iconDense, color: C.accentDeep),
                  const SizedBox(width: S.sm),
                  Expanded(
                    child: Text(adjustIntentNames[suggestion.intent] ?? '調整建議',
                        style: T.body(weight: FontWeight.w700)),
                  ),
                  Text(
                    changed == 0
                        ? '無異動'
                        : '$changed / ${suggestion.changes.length} 項調整',
                    style: T.caption(),
                  ),
                ],
              ),
            ),
            for (final (i, c) in suggestion.changes.indexed)
              _Row(change: c, last: i == suggestion.changes.length - 1),
            // 整份建議的依據（端內規則走這一條；模型是逐筆給理由）。
            if (suggestion.rationale case final r?)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(S.base),
                decoration: const BoxDecoration(
                  color: C.bgPage,
                  border: Border(top: BorderSide(color: C.lineDivider)),
                ),
                child: Text(r, style: T.caption()),
              ),
            if (scope != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(S.base, S.md, S.base, S.md),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: C.lineDivider)),
                ),
                child: Text('作用範圍：$scope', style: T.caption()),
              ),
          ],
        ),
      ),
    );
  }
}

/// 表格的一列：動作 ｜ 調整，理由另起一行。
///
/// **不用 `Table` 或 `DataTable`。** 動作名長短差很多（「深蹲」到
/// 「站姿單腳屈腿 · 器械」），固定欄寬要嘛把長名字擠成三行、要嘛讓短的
/// 那幾列空一大半。左右各自伸縮、理由橫跨整列，在 375 寬才讀得下去。
class _Row extends StatelessWidget {
  final AdjustChange change;
  final bool last;
  const _Row({required this.change, required this.last});

  @override
  Widget build(BuildContext context) {
    final dim = change.unchanged;
    return Container(
      padding: const EdgeInsets.fromLTRB(S.base, S.md, S.base, S.md),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: C.lineDivider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // **兩欄都要可伸縮。**
              //
              // 第一版是 `Expanded(動作名)` ＋ 固定寬的標籤，而調整字串
              // 可以很長（「60kg × 8 下 → 55kg × 10 下」）—— 在 375 寬
              // 溢出 1.3px，`screen_crawl_test` 與 smoke 當場紅。
              //
              // 兩邊都給 flex，長的那一欄自己折行。比例 5:4 是讓動作名
              // 優先拿到空間 —— 它是這一列的主詞。
              Expanded(
                flex: 5,
                child: Text(
                  change.title,
                  style: T.body(
                    color: dim ? C.textSecondary : C.textPrimary,
                    weight: dim ? FontWeight.w500 : FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: S.sm),
              // 「維持不變」用灰底，真正的改動用重點色 ——
              // 掃過去就看得出哪幾列動過。
              Flexible(
                flex: 4,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: S.sm, vertical: 3),
                  decoration: BoxDecoration(
                    // 輔助色在 v0.8 已移除（設計稿裁決：資訊沿用中性色），
                    // 所以重點色標籤用品牌深藍的淡色底，與設定頁那塊
                    // 存檔失敗面板同一個手法。
                    color:
                        dim ? C.bgPage : C.accentDeep.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(R.child),
                  ),
                  child: Text(
                    change.change,
                    textAlign: TextAlign.right,
                    style: T.caption(
                        color: dim ? C.textSecondary : C.accentDeep),
                  ),
                ),
              ),
            ],
          ),
          if (change.reason case final r?) ...[
            const SizedBox(height: S.xs),
            Text(r, style: T.caption(color: C.textSecondary)),
          ],
        ],
      ),
    );
  }
}
