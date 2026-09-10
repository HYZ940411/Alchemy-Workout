import 'package:flutter/material.dart';

import '../design/image_library.dart';
import '../design/tokens.dart';
import 'common.dart';

/// 選圖抽屜（商品圖片與貼文圖片共用）
///
/// 兩處要的東西一模一樣：從圖庫挑一組圖、可複選、可取消選取、按確定才生效。
/// 故為同一個抽屜 —— 差別只在標題與初始選取。
///
/// 回傳 null 代表使用者取消，與「選了空集合」不同：前者不改動原本的圖片，
/// 後者是把圖片清空。
Future<List<String>?> pickImages(
  BuildContext context, {
  required String title,
  required List<String> selected,
}) {
  return showAppSheet<List<String>>(
    context,
    title: title,
    child: _ImagePicker(initial: selected),
  );
}

class _ImagePicker extends StatefulWidget {
  final List<String> initial;
  const _ImagePicker({required this.initial});

  @override
  State<_ImagePicker> createState() => _ImagePickerState();
}

class _ImagePickerState extends State<_ImagePicker> {
  late final List<String> picked = [...widget.initial];

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<AppImage>>{};
    for (final img in kImageLibrary) {
      groups.putIfAbsent(img.group, () => []).add(img);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '本專案不打包點陣圖，圖庫為程式繪製的內建圖片；真機版此處接系統相簿。',
          style: T.caption(),
        ),
        for (final g in groups.entries) ...[
          SectionTitle(g.key, trailing: '${g.value.length} 張'),
          Wrap(
            spacing: S.md,
            runSpacing: S.md,
            children: [
              for (final img in g.value)
                _Tile(
                  image: img,
                  // 選取序號：複選時要看得出「先後」，只用打勾看不出來。
                  order: picked.indexOf(img.id),
                  onTap: () => setState(() {
                    picked.contains(img.id)
                        ? picked.remove(img.id)
                        : picked.add(img.id);
                  }),
                ),
            ],
          ),
        ],
        const SizedBox(height: S.lg),
        Text(
          picked.isEmpty ? '未選取任何圖片' : '已選 ${picked.length} 張',
          style: T.caption(),
        ),
        const SizedBox(height: S.md),
        ButtonRow(
          left: AppButton(
            label: '取消',
            kind: BtnKind.secondary,
            onPressed: () => Navigator.of(context).pop(),
          ),
          right: AppButton(
            label: '確定',
            onPressed: () => Navigator.of(context).pop(picked),
          ),
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  final AppImage image;
  final int order;
  final VoidCallback onTap;
  const _Tile({required this.image, required this.order, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final on = order >= 0;
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 88,
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(R.child + 2),
                    border: Border.all(
                      color: on ? C.actionOutline : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: AppImageView(id: image.id, size: 72),
                ),
                if (on)
                  Positioned(
                    top: -4,
                    right: -4,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: const BoxDecoration(
                        color: C.actionOutline,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text('${order + 1}',
                          style: T.caption(color: C.onFill(C.actionOutline))),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: S.xs),
            Text(
              image.label,
              style: T.caption(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
