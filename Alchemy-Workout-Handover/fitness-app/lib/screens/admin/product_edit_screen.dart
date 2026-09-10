import 'package:flutter/material.dart';

import '../../design/image_library.dart';
import '../../design/tokens.dart';
import '../../domain/admin.dart';
import '../../mock/mock_admin.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import '../../widgets/image_picker_sheet.dart';

/// 設定商品資訊（〈管理員商品上架流程〉）
///
/// 商品層級寫入類型、名稱、圖片；價格與庫存屬商品規格子聚合，逐規格設定。
/// 實體商品的規格為尺寸，可多筆；虛擬商品僅有一個預設規格。
class ProductEditScreen extends StatefulWidget {
  final AdminProduct product;
  const ProductEditScreen({super.key, required this.product});

  @override
  State<ProductEditScreen> createState() => _ProductEditScreenState();
}

class _ProductEditScreenState extends State<ProductEditScreen> {
  late final AdminProduct p = widget.product;
  late final name = TextEditingController(text: p.name);
  late final unlock = TextEditingController(text: p.unlockTarget ?? '');
  late List<String> images = [...p.images];
  late VirtualSubtype? subtype = p.subtype;

  /// 規格的編輯中副本。按儲存才寫回 Aggregate ——
  /// 中途離開不得改動任何既有規格。
  late final List<_SpecDraft> drafts = [
    for (final x in p.specs) _SpecDraft(x.name, x.price, x.stock),
  ];
  String? error;

  @override
  void dispose() {
    name.dispose();
    unlock.dispose();
    for (final d in drafts) {
      d.dispose();
    }
    super.dispose();
  }

  bool get stockApplies => subtype != VirtualSubtype.unlock;

  Future<void> _pick() async {
    final picked = await pickImages(
      context,
      title: '商品圖片',
      selected: images,
    );
    if (picked == null) return;
    setState(() => images = picked);
  }

  void _save(AppState s) {
    final specs = <AdminProductSpec>[];
    for (final d in drafts) {
      final price = int.tryParse(d.price.text.trim());
      final stock =
          stockApplies ? int.tryParse(d.stock.text.trim()) : 0;
      if (price == null) {
        setState(() => error = '「${d.name.text}」的價格不是有效的整數。');
        return;
      }
      if (stock == null) {
        setState(() => error = '「${d.name.text}」的庫存不是有效的整數。');
        return;
      }
      specs.add(AdminProductSpec(d.name.text, price, stock));
    }
    final failure = s.setProductInfo(
      p,
      name: name.text,
      images: images,
      specs: specs,
      subtype: subtype,
      unlockTarget: unlock.text,
    );
    if (failure != null) {
      setState(() => error = failure);
      return;
    }
    showToast(context, '已設定商品資訊');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);

    return Scaffold(
      backgroundColor: C.bgPage,
      appBar: AppBar(title: const Text('設定商品資訊')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          S.base,
          S.base,
          S.base,
          S.scrollBottom,
        ),
        children: [
          AppCard(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('商品 ID ${p.id}', style: T.caption()),
                      const SizedBox(height: 2),
                      Text(p.physical ? '實體商品' : '虛擬商品',
                          style: T.body(weight: FontWeight.w600)),
                    ],
                  ),
                ),
                TagBadge(
                  listingStateNames[p.listing]!,
                  borderColor: p.listing == ListingState.listed
                      ? C.statusSuccess
                      : C.lineDivider,
                ),
              ],
            ),
          ),
          const SizedBox(height: S.sm),
          Text(
            p.physical
                ? '類型於新增時決定，不再變更 —— 實體與虛擬的規格語意不同。'
                : '虛擬商品僅有一個預設規格。',
            style: T.caption(),
          ),

          const SectionTitle('名稱'),
          TextField(
            controller: name,
            style: T.body(),
            decoration: InputDecoration(
              hintText: '商品名稱',
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

          SectionTitle('圖片', trailing: '${images.length} 張'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppImageStrip(
                  ids: images,
                  onRemove: (id) => setState(() => images.remove(id)),
                ),
                const SizedBox(height: S.base),
                AppButton(
                  label: images.isEmpty ? '加入圖片' : '更換圖片',
                  kind: BtnKind.secondary,
                  icon: Icons.image_outlined,
                  onPressed: _pick,
                ),
              ],
            ),
          ),

          if (!p.physical) ...[
            const SectionTitle('虛擬商品子類型'),
            for (final v in VirtualSubtype.values) ...[
              OptionCard(
                title: virtualSubtypeNames[v]!,
                subtitle: v == VirtualSubtype.consumable
                    ? '道具入庫，可持有多份；適用庫存'
                    : '將解鎖標的寫入使用者的已購買計畫清單；不適用庫存',
                selected: subtype == v,
                onTap: () => setState(() => subtype = v),
              ),
              const SizedBox(height: S.md),
            ],
            if (subtype == VirtualSubtype.unlock) ...[
              const SizedBox(height: S.xs),
              Text('解鎖標的（訓練計畫）', style: T.caption()),
              const SizedBox(height: S.xs),
              _PlanPicker(
                value: unlock.text,
                plans: [for (final x in s.platformPlans) x.name],
                onChanged: (v) => setState(() => unlock.text = v),
              ),
            ],
          ],

          SectionTitle(
            p.physical ? '規格（尺寸）' : '規格',
            trailing: '價格與庫存屬規格層級',
          ),
          for (var i = 0; i < drafts.length; i++) ...[
            _SpecRow(
              draft: drafts[i],
              stockApplies: stockApplies,
              // 至少須有一個規格，故只剩一筆時不給刪。
              onRemove: drafts.length > 1
                  ? () => setState(() => drafts.removeAt(i).dispose())
                  : null,
            ),
            const SizedBox(height: S.md),
          ],
          if (p.physical)
            AppButton(
              label: '新增規格',
              kind: BtnKind.secondary,
              icon: Icons.add,
              onPressed: () =>
                  setState(() => drafts.add(_SpecDraft('', 0, 0))),
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
                    child: Text(error!, style: T.caption(color: C.statusError)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(S.base, S.md, S.base, S.base),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppButton(label: '儲存', onPressed: () => _save(s)),
          ],
        ),
      ),
    );
  }
}

class _SpecDraft {
  final TextEditingController name;
  final TextEditingController price;
  final TextEditingController stock;
  _SpecDraft(String n, int p, int st)
      : name = TextEditingController(text: n),
        price = TextEditingController(text: '$p'),
        stock = TextEditingController(text: '$st');

  void dispose() {
    name.dispose();
    price.dispose();
    stock.dispose();
  }
}

class _SpecRow extends StatelessWidget {
  final _SpecDraft draft;
  final bool stockApplies;
  final VoidCallback? onRemove;
  const _SpecRow({
    required this.draft,
    required this.stockApplies,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) => AppCard(
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _Field(controller: draft.name, hint: '規格名稱'),
                ),
                if (onRemove != null) ...[
                  const SizedBox(width: S.sm),
                  GestureDetector(
                    onTap: onRemove,
                    child: const Padding(
                      padding: EdgeInsets.all(S.sm),
                      child: Icon(Icons.delete_outline,
                          size: Sz.iconDefault, color: C.textSecondary),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: S.md),
            Row(
              children: [
                Expanded(
                  child: _Field(
                    controller: draft.price,
                    hint: '價格',
                    suffix: '金幣',
                    number: true,
                  ),
                ),
                const SizedBox(width: S.md),
                Expanded(
                  child: stockApplies
                      ? _Field(
                          controller: draft.stock,
                          hint: '庫存',
                          suffix: '件',
                          number: true,
                        )
                      // 權限解鎖類不適用庫存：解鎖為冪等狀態，非可消耗的資源。
                      : Text('庫存不適用', style: T.caption()),
                ),
              ],
            ),
          ],
        ),
      );
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final String? suffix;
  final bool number;
  const _Field({
    required this.controller,
    required this.hint,
    this.suffix,
    this.number = false,
  });

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        style: number ? T.numberS() : T.body(),
        textAlign: number ? TextAlign.end : TextAlign.start,
        keyboardType: number ? TextInputType.number : null,
        decoration: InputDecoration(
          isDense: true,
          hintText: hint,
          hintStyle: T.body(color: C.textDisabled),
          suffixText: suffix,
          suffixStyle: T.caption(),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: S.md, vertical: S.md),
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
      );
}

/// 解鎖標的只能指向既有的訓練計畫，故為選擇而非自由輸入 ——
/// 打錯字的商品會解鎖不到任何東西。
class _PlanPicker extends StatelessWidget {
  final String value;
  final List<String> plans;
  final ValueChanged<String> onChanged;
  const _PlanPicker({
    required this.value,
    required this.plans,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: S.sm,
        runSpacing: S.sm,
        children: [
          for (final n in plans)
            GestureDetector(
              onTap: () => onChanged(n),
              child: TagBadge(
                n,
                borderColor: n == value ? C.actionOutline : C.lineDivider,
                fill: n == value ? C.actionOutline : null,
              ),
            ),
        ],
      );
}
