import 'package:flutter/material.dart';

import '../../domain/admin.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// 檢舉內容的入口。理由採**列舉單選 ＋ 選填補充文字** ——
/// 純自由文字會使管理員的待審佇列無法依理由篩選與排序。
///
/// 值域來自〈檢舉理由設定 Aggregate〉，由管理員於後台維護。
Future<void> showReportSheet(
  BuildContext context, {
  required ReportTarget target,
  required String targetKey,
  required String content,
  required String accused,

  /// 被檢舉者的雲端身分。**記點靠它，不靠暱稱** —— 暱稱會改也會撞名。
  /// 訊息類的對話若是示範資料就沒有，那種案件審得了但記不了點。
  String? accusedUid,
}) async {
  final s = AppScope.of(context);
  final result = await showAppSheet<(String, String)>(
    context,
    title: '檢舉${reportTargetNames[target]}',
    child: _ReportForm(content: content, accused: accused),
  );
  if (result == null || !context.mounted) return;

  final isNew = s.fileReport(
    target: target,
    targetKey: targetKey,
    content: content,
    accused: accused,
    accusedUid: accusedUid,
    reason: result.$1,
    note: result.$2.isEmpty ? null : result.$2,
  );
  if (!context.mounted) return;
  showToast(
    context,
    isNew
        ? '已送出檢舉，管理員會審視'
        : '已併入既有案件 —— 多人檢舉同一內容只需審視一次',
  );
}

class _ReportForm extends StatefulWidget {
  final String content;
  final String accused;
  const _ReportForm({required this.content, required this.accused});

  @override
  State<_ReportForm> createState() => _ReportFormState();
}

class _ReportFormState extends State<_ReportForm> {
  String? _reason;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('被檢舉內容', style: T.caption()),
                const SizedBox(height: S.xs),
                Text(widget.content, style: T.body(), maxLines: 3,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(height: S.lg),
          Text('檢舉理由', style: T.caption()),
          const SizedBox(height: S.sm),
          for (final r in kReportReasons)
            Padding(
              padding: const EdgeInsets.only(bottom: S.sm),
              child: OptionCard(
                title: r,
                selected: _reason == r,
                onTap: () => setState(() => _reason = r),
              ),
            ),
          const SizedBox(height: S.md),
          Text('補充說明（選填）', style: T.caption()),
          const SizedBox(height: S.sm),
          TextField(
            controller: _note,
            style: T.body(),
            maxLines: 3,
            decoration: InputDecoration(
              hintText: '無論選哪個理由都不強制填寫',
              hintStyle: T.body(color: C.textDisabled),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(R.control),
              ),
            ),
          ),
          const SizedBox(height: S.lg),
          AppButton(
            label: '送出檢舉',
            onPressed: _reason == null
                ? null
                : () => Navigator.of(context).pop((_reason!, _note.text.trim())),
          ),
          const SizedBox(height: S.sm),
          Text(
            '檢舉不會觸發任何自動處置 —— 沒有累積次數門檻，也不會自動隱藏內容。',
            style: T.caption(),
            textAlign: TextAlign.center,
          ),
        ],
      );
}
