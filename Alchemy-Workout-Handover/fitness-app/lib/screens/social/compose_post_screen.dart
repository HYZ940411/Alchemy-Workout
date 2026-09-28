import 'package:flutter/material.dart';

import '../../design/image_library.dart';
import '../../design/tokens.dart';
import '../../domain/community.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import '../../widgets/image_picker_sheet.dart';

/// 發文（〈發文與互動流程〉）
///
/// 貼文支援文字與圖片，不支援影片，無標籤欄位。
/// **貼文一律公開**（使用者裁決 2026-09-26，2026-09-28 再次確認 A）。
/// 送出前先經自動過濾，依判定分兩條路：明顯違規當場攔截、疑似違規照常發布並自動送審。
class ComposePostScreen extends StatefulWidget {
  const ComposePostScreen({super.key});
  @override
  State<ComposePostScreen> createState() => _ComposePostScreenState();
}

class _ComposePostScreenState extends State<ComposePostScreen> {
  final ctrl = TextEditingController();
  /// **貼文一律公開**（使用者裁決 2026-09-26）。
  ///
  /// 可見範圍的選擇器已移除。理由不是「不想做」，是**它從來沒有生效過**：
  /// 動態牆只濾掉已刪除的，而 `firestore.rules` 的貼文讀取是
  /// `allow read: if request.auth != null` —— **任何登入者都讀得到每一篇**，
  /// 包括標「私人」的。也就是那個選項一直在對使用者說一件不是真的事。
  ///
  /// 要真的做對，「僅關注者」得讓安全規則判斷「讀的人有沒有關注作者」，
  /// 而那在查詢裡做不到（Firestore 要求查詢條件本身就證明得了權限），
  /// 得把可見名單反正規化到每一篇貼文上 —— 關注一個人就要回頭改他
  /// 所有的貼文。成本與效益不成比例。
  ///
  /// 使用者裁決：**移除選項，一律公開**。停止假裝有保護，比留著一個
  /// 擋不住任何人的開關誠實。
  ///
  /// **2026-09-28 補上告知。** 移除選項之後畫面上**什麼都沒說** ——
  /// 使用者從一個有三個選項的畫面，變成一個沒有選項的畫面，
  /// 而沒有任何地方告訴他結果是哪一種。不給選擇可以，不告知不行。
  final PostVisibility visibility = PostVisibility.public;
  String? errorText;

  /// 貼文的圖片集合。文字為空但有圖時仍不可發布 ——
  /// 沿用既有的字數判定，本次不改動發布條件。
  List<String> images = [];

  static const _maxChars = 500;

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
    final len = ctrl.text.characters.length;
    final canPost = len > 0 && len <= _maxChars;

    return Scaffold(
      backgroundColor: C.bgPage,
      // 任務型頁面：底部導覽列隱藏（§8.4）
      appBar: AppBar(title: const Text('發文')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                  S.base, S.base, S.base, S.scrollBottom),
              children: [
                // 貼文是公開的，這件事要講出來 —— 見上面 [visibility]。
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.public,
                        size: Sz.iconDense, color: C.accentInfo),
                    const SizedBox(width: S.sm),
                    Expanded(
                      child: Text(
                        '這篇貼文公開，任何人都看得到。',
                        style: T.caption(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: S.base),
                // 多行輸入框（§8.2）：最小高 120、文字從頂部開始、字數上限置右下
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('內容', style: T.caption()),
                    const SizedBox(height: S.xs),
                    Container(
                      constraints: const BoxConstraints(minHeight: 120),
                      decoration: BoxDecoration(
                        color: C.bgSurface,
                        borderRadius: BorderRadius.circular(R.control),
                        border: Border.all(
                          color: errorText != null
                              ? C.statusError
                              : C.lineDivider,
                          width: errorText != null ? 1.5 : 1,
                        ),
                      ),
                      padding: const EdgeInsets.fromLTRB(S.base, S.md, S.base, S.sm),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          TextField(
                            controller: ctrl,
                            maxLines: null,
                            minLines: 4,
                            style: T.body(),
                            decoration: InputDecoration(
                              isDense: true,
                              border: InputBorder.none,
                              hintText: '今天練了什麼？',
                              hintStyle: T.body(color: C.textSecondary),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                          Text('$len / $_maxChars', style: T.caption()),
                        ],
                      ),
                    ),
                    // 【必須】錯誤必須有文字，不可只靠紅色
                    if (errorText != null) ...[
                      const SizedBox(height: S.xs),
                      Text(errorText!, style: T.caption(color: C.statusError)),
                    ],
                  ],
                ),

                const SizedBox(height: S.base),
                if (images.isNotEmpty) ...[
                  AppImageStrip(
                    ids: images,
                    onRemove: (id) => setState(() => images.remove(id)),
                  ),
                  const SizedBox(height: S.base),
                ],
                AppButton(
                  label: images.isEmpty ? '加入圖片' : '更換圖片（${images.length} 張）',
                  kind: BtnKind.secondary,
                  icon: Icons.image_outlined,
                  onPressed: () async {
                    final picked = await pickImages(
                      context,
                      title: '加入圖片',
                      selected: images,
                    );
                    if (picked == null) return;
                    setState(() => images = picked);
                  },
                ),


              ],
            ),
          ),
          // 底部固定按鈕，距螢幕底 50px（§1.2）
          Container(
            decoration: const BoxDecoration(
              color: C.bgSurface,
              border: Border(top: BorderSide(color: C.lineDivider)),
            ),
            padding: EdgeInsets.fromLTRB(S.base, S.md, S.base,
                MediaQuery.of(context).padding.bottom + S.base),
            child: AppButton(
              label: '發布',
              onPressed: canPost
                  ? () async {
                      final verdict = s.publishPost(ctrl.text.trim(), visibility,
                          images: images);
                      if (!context.mounted) return;
                      switch (verdict) {
                        case FilterVerdict.blocked:
                          // 明顯違規：當場攔截，不寫入任何 Aggregate
                          setState(() => errorText =
                              '內容含有違規字詞，已被攔截。修改後可重新送出，次數不限。');
                          await showAppDialog(
                            context,
                            title: '內容已攔截',
                            message: '此內容判定為明顯違規，未發布，'
                                '也不發放任何互動獎勵。你可以修改後重送，或提出申訴。',
                            confirmLabel: '我知道了',
                            cancelLabel: '申訴',
                          );
                        case FilterVerdict.flagged:
                          // 疑似違規：照常發布並自動送審
                          setState(() => errorText = null);
                          Navigator.of(context).pop();
                          showToast(context, '已發布，內容將自動送審');
                        case FilterVerdict.pass:
                          setState(() => errorText = null);
                          Navigator.of(context).pop();
                          showToast(context, '已發布');
                      }
                    }
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}
