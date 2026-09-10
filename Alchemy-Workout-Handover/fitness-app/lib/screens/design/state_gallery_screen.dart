import 'package:flutter/material.dart';

import '../../design/error_state.dart';
import '../../design/skeleton.dart';
import '../../design/tokens.dart';
import '../../widgets/common.dart';

/// 骨架屏、空狀態、錯誤頁的型錄
///
/// 三者是同一個東西的三個結果：**這一頁還沒有內容**。
/// 差別在於「為什麼沒有」—— 還在載（骨架屏）、真的沒有（空狀態）、
/// 載不到（錯誤頁）。放在同一個型錄裡，才看得出三者不可互相代用。
class StateGalleryScreen extends StatelessWidget {
  const StateGalleryScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: C.bgPage,
        appBar: AppBar(title: const Text('骨架屏與錯誤頁')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(
              S.base, S.base, S.base, S.scrollBottom),
          children: [
            AppCard(
              child: Text(
                '骨架形狀必須貼近真實內容的排版：形狀差太多的話，'
                '載入完成時版面會大幅跳動，體感比轉圈更差。'
                '故六種型態各有各的骨架，不共用。',
                style: T.caption(),
              ),
            ),
            const SectionTitle('骨架屏', trailing: '六種型態·僅首次載入'),
            ListGroup(rows: [
              for (var i = 0; i < SkeletonKind.values.length; i++)
                _row(
                  context,
                  skeletonKindNames[SkeletonKind.values[i]]!,
                  _skeletonHint[SkeletonKind.values[i]]!,
                  _preview(
                    skeletonKindNames[SkeletonKind.values[i]]!,
                    _demoTitle[SkeletonKind.values[i]]!,
                    _skeletonBody(SkeletonKind.values[i]),
                  ),
                  i != SkeletonKind.values.length - 1,
                ),
            ]),

            const SectionTitle('空狀態', trailing: '四種型態·E 與 F 不需要'),
            ListGroup(rows: [
              for (var i = 0; i < kGalleryEmptyStates.length; i++)
                _row(
                  context,
                  '${kGalleryEmptyStates[i].$1}·空狀態',
                  kGalleryEmptyStates[i].$2,
                  _preview(kGalleryEmptyStates[i].$1, kGalleryEmptyStates[i].$3, kGalleryEmptyStates[i].$4),
                  i != kGalleryEmptyStates.length - 1,
                ),
            ]),

            const SectionTitle('錯誤頁', trailing: '一定有重新載入'),
            ListGroup(rows: [
              _row(
                context,
                'E1 次層頁',
                '講的是這份清單載不出來',
                _preview('E1 次層頁', '訓練歷史',
                    Builder(builder: (c) => ErrorState(onRetry: () {}))),
                true,
              ),
              _row(
                context,
                'E2 著陸頁',
                '整個分頁都空了，講的是連線本身',
                _preview('E2 著陸頁', '首頁',
                    Builder(builder: (c) => ErrorState.landing(onRetry: () {}))),
                false,
              ),
            ]),
          ],
        ),
      );

  static const _skeletonHint = <SkeletonKind, String>{
    SkeletonKind.listA: '頭像圓 32 ＋ 兩行條（12／8）',
    SkeletonKind.cardListB: '16:9 圖 ＋ 標題條 ＋ 副標條 ＋ 標籤',
    SkeletonKind.gridC: '兩欄方塊 92 高 ＋ 兩行條',
    SkeletonKind.chatD: '泡泡左右交錯',
    SkeletonKind.detailE: '大圖 184 ＋ 段落條 ＋ 清單條',
    SkeletonKind.chartF: '六邊形實心 ＋ 數值列',
  };

  static const _demoTitle = <SkeletonKind, String>{
    SkeletonKind.listA: '對話',
    SkeletonKind.cardListB: '選擇課表',
    SkeletonKind.gridC: '商店',
    SkeletonKind.chatD: '王教練',
    SkeletonKind.detailE: '訓練計畫',
    SkeletonKind.chartF: '六維能力值',
  };

  static Widget _skeletonBody(SkeletonKind k) => SingleChildScrollView(
        padding: EdgeInsets.all(k == SkeletonKind.listA ? 0 : S.base),
        physics: const NeverScrollableScrollPhysics(),
        child: Skeleton(kind: k, rows: _rows[k]!),
      );

  /// 顯示列數依該頁首屏可見的列數，不多不少。
  static const _rows = <SkeletonKind, int>{
    SkeletonKind.listA: 6,
    SkeletonKind.cardListB: 2,
    SkeletonKind.gridC: 3,
    SkeletonKind.chatD: 5,
    SkeletonKind.detailE: 4,
    SkeletonKind.chartF: 4,
  };

  static Widget _preview(String label, String title, Widget body) =>
      _PreviewPage(label: label, title: title, body: body);

  ListRow _row(BuildContext context, String title, String subtitle,
          Widget page, bool divider) =>
      ListRow(
        title: title,
        subtitle: subtitle,
        chevron: true,
        showDivider: divider,
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => page)),
      );
}

/// 型錄的預覽頁 —— 用真的 AppBar 包起來，才看得出骨架與內容的版面是否對齊。
/// 四個空狀態。**E 詳情型與 F 圖表型不需要空狀態** ——
/// 詳情頁一定有資料，六維能力值對新使用者也有初始值。
///
/// 文案三條規則（§8.5）：不得只寫「暫無資料」、必須說明為什麼是空的、
/// 必須提供一個下一步。放成公開常數，測試才驗得到這三條。
final kGalleryEmptyStates = <(String, String, String, EmptyState)>[
    (
      'A 清單型',
      '對話清單',
      '對話',
      EmptyState(
        icon: Icons.chat_bubble_outline,
        title: '還沒有任何對話',
        message: '到教官清單找一位教官，開始你的第一段對話',
        action: AppButton(
            label: '瀏覽教官', kind: BtnKind.secondary, onPressed: _noop),
      ),
    ),
    (
      'B 卡片列表型',
      '自訂訓練管理',
      '我的自訂訓練',
      EmptyState(
        icon: Icons.article_outlined,
        title: '還沒有自訂訓練',
        message: '你可以從動作庫挑動作，組出屬於自己的課表',
        action: AppButton(
            label: '建立第一份課表', kind: BtnKind.secondary, onPressed: _noop),
      ),
    ),
    (
      'C 卡片格狀型',
      '成就頁',
      '成就',
      EmptyState(
        icon: Icons.star_border_rounded,
        title: '還沒有解鎖任何成就',
        message: '完成第一次訓練，就會解鎖你的第一枚成就',
        action: AppButton(
            label: '開始訓練', kind: BtnKind.secondary, onPressed: _noop),
      ),
    ),
    (
      'D 對話型',
      '師徒對話',
      '王教練',
      EmptyState(
        icon: Icons.add_comment_outlined,
        title: '還沒有訊息',
        message: '打聲招呼，讓教練知道你想加強哪個部位',
        action: AppButton(
            label: '說點什麼', kind: BtnKind.secondary, onPressed: _noop),
      ),
    ),
  ];

void _noop() {}

class _PreviewPage extends StatelessWidget {
  final String label;
  final String title;
  final Widget body;
  const _PreviewPage(
      {required this.label, required this.title, required this.body});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: C.bgPage,
        appBar: AppBar(
          title: Text(title),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(24),
            child: Container(
              width: double.infinity,
              color: C.bgSurface,
              padding: const EdgeInsets.only(bottom: S.sm),
              child: Text(label,
                  style: T.caption(), textAlign: TextAlign.center),
            ),
          ),
        ),
        body: body,
      );
}
