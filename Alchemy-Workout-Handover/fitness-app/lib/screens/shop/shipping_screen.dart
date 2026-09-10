import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../domain/commerce.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

/// 收貨資訊填寫頁（〈實體商品購買流程〉：使用者已填寫收貨資訊）
///
/// 五個欄位：收件人姓名、手機號碼、郵遞區號、地址、備註 —— 僅備註為選填。
/// 地址為單一自由文字欄，不拆縣市／鄉鎮區／街道：須維護會改名合併的行政區資料，
/// 而物流已在系統邊界外，本系統無拆解用途。
/// 不收電子郵件：那是使用者 Aggregate 的選填欄位，不於此重複收集。
///
/// 填妥後以 [ShippingInfo] 回傳給呼叫端，本頁不成立訂單。
class ShippingScreen extends StatefulWidget {
  const ShippingScreen({super.key});

  @override
  State<ShippingScreen> createState() => _ShippingScreenState();
}

class _ShippingScreenState extends State<ShippingScreen> {
  late TextEditingController name;
  late TextEditingController phone;
  late TextEditingController zip;
  late TextEditingController address;
  late TextEditingController note;
  String? error;
  bool prefilled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (prefilled) return;
    prefilled = true;
    // 預帶上次填寫的內容 —— 5 個必填欄位每次重填為純粹的摩擦。
    final last = AppScope.of(context).lastShipping;
    name = TextEditingController(text: last?.name ?? '');
    phone = TextEditingController(text: last?.phone ?? '');
    zip = TextEditingController(text: last?.zip ?? '');
    address = TextEditingController(text: last?.address ?? '');
    note = TextEditingController(text: last?.note ?? '');
  }

  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    zip.dispose();
    address.dispose();
    note.dispose();
    super.dispose();
  }

  void _submit() {
    final failure = ShippingInfo.validate(
      name: name.text,
      phone: phone.text,
      zip: zip.text,
      address: address.text,
    );
    if (failure != null) {
      setState(() => error = failure);
      return;
    }
    Navigator.of(context).pop(ShippingInfo(
      name: name.text.trim(),
      phone: phone.text.trim(),
      zip: zip.text.trim(),
      address: address.text.trim(),
      note: note.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final last = AppScope.of(context).lastShipping;

    return Scaffold(
      backgroundColor: C.bgPage,
      appBar: AppBar(title: const Text('收貨資訊')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          S.base,
          S.base,
          S.base,
          S.scrollBottom,
        ),
        children: [
          if (last != null)
            AppCard(
              child: Row(
                children: [
                  const Icon(Icons.history_rounded,
                      size: Sz.iconDense, color: C.textSecondary),
                  const SizedBox(width: S.md),
                  Expanded(
                    child: Text('已帶入上次填寫的內容，可直接修改。',
                        style: T.caption()),
                  ),
                ],
              ),
            ),
          const SectionTitle('收件人'),
          _Field(label: '姓名', controller: name, hint: '收件人姓名'),
          const SizedBox(height: S.md),
          _Field(
            label: '手機號碼',
            controller: phone,
            hint: '09 開頭的 10 位數字',
            keyboard: TextInputType.phone,
          ),
          const SectionTitle('地址'),
          _Field(
            label: '郵遞區號',
            controller: zip,
            hint: '例：110',
            keyboard: TextInputType.number,
          ),
          const SizedBox(height: S.md),
          _Field(
            label: '地址',
            controller: address,
            hint: '縣市、鄉鎮區、街道門牌一併填入',
            lines: 2,
          ),
          const SizedBox(height: S.md),
          _Field(
            label: '備註（選填）',
            controller: note,
            hint: '例：放管理室、平日白天不在家',
            lines: 2,
          ),
          if (error != null) ...[
            const SizedBox(height: S.base),
            AppCard(
              borderColor: C.statusError,
              child: Row(
                children: [
                  const Icon(Icons.error_outline,
                      size: Sz.iconDense, color: C.statusError),
                  const SizedBox(width: S.md),
                  Expanded(
                    child:
                        Text(error!, style: T.caption(color: C.statusError)),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: S.base),
          Text('出貨通知會顯示在「我的訂單」，不另外推播。', style: T.caption()),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(S.base, S.md, S.base, S.base),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppButton(label: '下一步：確認訂單', onPressed: _submit),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String hint;
  final int lines;
  final TextInputType? keyboard;
  const _Field({
    required this.label,
    required this.controller,
    required this.hint,
    this.lines = 1,
    this.keyboard,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: T.caption()),
          const SizedBox(height: S.xs),
          TextField(
            controller: controller,
            style: T.body(),
            maxLines: lines,
            keyboardType: keyboard,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: T.body(color: C.textDisabled),
              filled: true,
              fillColor: C.bgSurface,
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
      );
}
