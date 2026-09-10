import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../domain/novice_wrapup.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

/// 引導收尾②：評分訓練體驗
///
/// **可跳過，不阻擋領取獎勵或任何後續 Command**；跳過不產生任何 Event，
/// 也不記錄「已跳過」狀態 —— 被擋住去路的人會隨手點一個把它關掉，
/// 取得的是筆數而非品質的訊號，而這份評分的唯一讀者（管理員評分彙總）
/// 要回答的正是「哪一份內容該改」。
///
/// 每人每個對象**終身僅一筆**，但**可修改**：不可修改的話，
/// 誤觸就是永久寫入一筆錯的資料且無從更正。
/// 評分不連動任何獎勵或聲望，沒有操縱誘因，故不設防刷機制。
class RateExperienceScreen extends StatefulWidget {
  final RatingTarget target;
  final String targetId;
  final String targetName;
  final bool fromGuide;

  const RateExperienceScreen({
    super.key,
    required this.target,
    required this.targetId,
    required this.targetName,
    this.fromGuide = false,
  });

  @override
  State<RateExperienceScreen> createState() => _RateExperienceScreenState();
}

class _RateExperienceScreenState extends State<RateExperienceScreen> {
  final ctrl = TextEditingController();
  int stars = 0;
  bool loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (loaded) return;
    final existing =
        AppScope.of(context).ratingFor(widget.target, widget.targetId);
    if (existing != null) {
      stars = existing.stars;
      ctrl.text = existing.feedback ?? '';
    }
    loaded = true;
  }

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final existing = s.ratingFor(widget.target, widget.targetId);

    return Scaffold(
      backgroundColor: C.bgPage,
      appBar: AppBar(
        title: Text(existing == null ? '評分體驗' : '修改評分'),
        automaticallyImplyLeading: !widget.fromGuide,
      ),
      body: ListView(
        padding:
            const EdgeInsets.fromLTRB(S.base, S.base, S.base, S.scrollBottom),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${widget.targetName}做起來如何？', style: T.h3()),
                const SizedBox(height: S.sm),
                Text(
                  '這份評分是給平台改內容用的，不會連動任何人的聲望或獎勵。'
                  '${ratingTargetNames[widget.target]}每人只評一次，但隨時可以改。',
                  style: T.caption(),
                ),
              ],
            ),
          ),

          const SectionTitle('星等', trailing: '必填'),
          AppCard(
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 1; i <= 5; i++)
                      GestureDetector(
                        onTap: () => setState(() => stars = i),
                        behavior: HitTestBehavior.opaque,
                        child: SizedBox(
                          width: Sz.tapTarget,
                          height: Sz.tapTarget,
                          child: Icon(
                            i <= stars ? Icons.star : Icons.star_border,
                            size: Sz.iconEmphasis,
                            color: i <= stars
                                ? C.actionPrimary
                                : C.textSecondary,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: S.sm),
                // 【必須】不可只靠顏色與圖形，星數要有文字。
                Text(stars == 0 ? '還沒選' : '$stars 星', style: T.caption()),
              ],
            ),
          ),

          const SectionTitle('想補充什麼？', trailing: '選填'),
          TextField(
            controller: ctrl,
            style: T.body(),
            maxLines: 4,
            decoration: InputDecoration(
              hintText: '哪裡好、哪裡卡住，寫下來平台才知道要改什麼。',
              hintStyle: T.body(color: C.textDisabled),
              contentPadding: const EdgeInsets.all(S.base),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(R.control),
                borderSide: const BorderSide(color: C.lineDivider),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(R.control),
                borderSide: const BorderSide(color: C.lineDivider),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(R.control),
                borderSide: const BorderSide(color: C.actionOutline, width: 2),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: EdgeInsets.fromLTRB(S.base, S.md, S.base,
            MediaQuery.of(context).padding.bottom + S.base),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ButtonRow(
              left: AppButton(
                label: widget.fromGuide ? '跳過' : '返回',
                kind: BtnKind.secondary,
                // 跳過不產生任何 Event，也不記錄「已跳過」狀態 ——
                // 日後仍可主動評分。
                onPressed: () => Navigator.of(context).pop(),
              ),
              right: AppButton(
                label: existing == null ? '送出評分' : '更新評分',
                onPressed: stars == 0
                    ? null
                    : () {
                        final text = ctrl.text.trim();
                        s.rateExperience(
                          widget.target,
                          widget.targetId,
                          stars,
                          feedback: text.isEmpty ? null : text,
                        );
                        showToast(context,
                            existing == null ? '已送出評分' : '已更新評分');
                        Navigator.of(context).pop();
                      },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
