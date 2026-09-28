import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../design/image_library.dart';
import '../design/tokens.dart';
import '../state/app_state.dart';
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

  /// 正在壓縮與上傳。**整個抽屜都要擋住** —— 使用者在這段時間按「確定」
  /// 的話，會帶著一份還沒有那張照片的清單離開。
  bool busy = false;
  String? error;

  /// 從裝置選一張照片，壓好、傳上去，把 ID 加進選取清單。
  ///
  /// **一次只選一張。** 多選要處理「第三張失敗了前兩張怎麼辦」，
  /// 而使用者可以按第二次。
  Future<void> _fromDevice() async {
    final s = AppScope.of(context);
    setState(() { error = null; busy = true; });
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (file == null) return;              // 使用者取消，不是錯誤
      final (id, why) = await s.uploadPhoto(await file.readAsBytes());
      if (!mounted) return;
      setState(() {
        if (id != null) {
          picked.add(id);
        } else {
          error = why;
        }
      });
    } catch (e) {
      if (mounted) setState(() => error = '選取照片失敗：$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<AppImage>>{};
    for (final img in kImageLibrary) {
      groups.putIfAbsent(img.group, () => []).add(img);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 2026-09-28 起可以選裝置上的照片（使用者裁決：存 Firestore）。
        // 沒接雲端時（既有測試）這一顆不出現，行為與加功能之前一樣。
        if (AppScope.of(context).canUploadPhoto) ...[
          AppButton(
            label: busy ? '處理中…' : '從裝置選擇照片',
            kind: BtnKind.secondary,
            onPressed: busy ? null : _fromDevice,
          ),
          if (error != null) ...[
            const SizedBox(height: S.xs),
            Text(error!, style: T.caption(color: C.statusError)),
          ],
          // 已經傳上來的照片要看得到，也要拿得掉 —— 不然它只出現在
          // 「已選 N 張」那個數字裡，使用者不知道自己選了什麼。
          if (picked.any(isUploadedPhotoId)) ...[
            const SizedBox(height: S.md),
            AppImageStrip(
              ids: picked.where(isUploadedPhotoId).toList(),
              size: 72,
              onRemove: (id) => setState(() => picked.remove(id)),
            ),
          ],
          const SizedBox(height: S.md),
          Text('或從下面的內建圖片挑：', style: T.caption()),
        ] else
          Text('圖庫為程式繪製的內建圖片。', style: T.caption()),
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
            // 上傳中按確定會帶著一份還沒有那張照片的清單離開。
            onPressed: busy ? null : () => Navigator.of(context).pop(picked),
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
