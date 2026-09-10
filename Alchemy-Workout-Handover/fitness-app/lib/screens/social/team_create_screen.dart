import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../domain/community.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

/// 建立團隊
///
/// **建立本身無門檻**，任何使用者皆可建立 —— 擋人的只有「一人只能屬於一個團隊」
/// 與換隊冷卻，這兩條與申請加入共用同一組 Precondition。
///
/// 可見性在建立時就要決定（預設公開），但**事後可改**：
/// 團隊性質本會隨時間改變，鎖死只會逼使用者解散重建。
class TeamCreateScreen extends StatefulWidget {
  const TeamCreateScreen({super.key});

  @override
  State<TeamCreateScreen> createState() => _TeamCreateScreenState();
}

class _TeamCreateScreenState extends State<TeamCreateScreen> {
  final ctrl = TextEditingController();
  bool isPublic = true;

  @override
  void initState() {
    super.initState();
    ctrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final blocked = s.createBlockedReason();

    return Scaffold(
      backgroundColor: C.bgPage,
      appBar: AppBar(title: const Text('建立團隊')),
      body: ListView(
        padding:
            const EdgeInsets.fromLTRB(S.base, S.base, S.base, S.scrollBottom),
        children: [
          Text('團隊名稱', style: T.h3()),
          const SizedBox(height: S.sm),
          TextField(
            controller: ctrl,
            style: T.body(),
            decoration: InputDecoration(
              isDense: true,
              hintText: '例：晨型人訓練隊',
              hintStyle: T.body(color: C.textDisabled),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: S.base, vertical: S.md),
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

          const SectionTitle('可見性', trailing: '之後可以改'),
          _Option(
            title: '公開',
            detail: '可被搜尋，也接受加入申請。申請一律由你核准或拒絕，'
                '不會有人直接進來。',
            selected: isPublic,
            onTap: () => setState(() => isPublic = true),
          ),
          const SizedBox(height: S.md),
          _Option(
            title: '私密',
            detail: '不會出現在搜尋結果，也不接受加入申請，只能由你邀請。',
            selected: !isPublic,
            onTap: () => setState(() => isPublic = false),
          ),

          const SectionTitle('建立之後'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Line('你是隊長。團隊只有隊長與成員兩種角色，沒有副隊長。'),
                _Line('人數上限 $kTeamCapacity 人（含隊長）；'
                    '待回應的邀請與申請不佔名額。'),
                _Line('本週期曾達 $kTeamMinSize 人才會列入團隊排行榜，'
                    '未達也照常累積分數。'),
                _Line('隊上只剩你一個人時退出，團隊即解散，不可復原。'),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: EdgeInsets.fromLTRB(S.base, S.md, S.base,
            MediaQuery.of(context).padding.bottom + S.base),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (blocked != null)
              Padding(
                padding: const EdgeInsets.only(bottom: S.sm),
                child: Text(blocked, style: T.caption()),
              ),
            AppButton(
              label: '建立團隊',
              onPressed: (blocked != null || ctrl.text.trim().isEmpty)
                  ? null
                  : () {
                      s.createTeam(ctrl.text, isPublic: isPublic);
                      showToast(context, '團隊已建立，你是隊長');
                      Navigator.of(context).pop();
                    },
            ),
          ],
        ),
      ),
    );
  }
}

class _Option extends StatelessWidget {
  final String title;
  final String detail;
  final bool selected;
  final VoidCallback onTap;
  const _Option({
    required this.title,
    required this.detail,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(R.card),
        child: Container(
          padding: const EdgeInsets.all(S.base),
          decoration: BoxDecoration(
            color: C.bgSurface,
            borderRadius: BorderRadius.circular(R.card),
            // §4.4：選取態為 2px 外框，不換底色。
            border: Border.all(
              color: selected ? C.actionOutline : C.lineDivider,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: Sz.iconDense,
                color: selected ? C.actionOutline : C.textDisabled,
              ),
              const SizedBox(width: S.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: T.body(weight: FontWeight.w700)),
                    const SizedBox(height: S.xs),
                    Text(detail, style: T.caption()),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class _Line extends StatelessWidget {
  final String text;
  const _Line(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: S.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('·　', style: T.caption()),
            Expanded(child: Text(text, style: T.caption())),
          ],
        ),
      );
}
