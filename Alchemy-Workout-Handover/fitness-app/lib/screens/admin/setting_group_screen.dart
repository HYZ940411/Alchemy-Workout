import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../domain/admin.dart';
import '../../domain/platform_config.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

/// 一組平台參數的編輯器（7 個 Command 共用）
///
/// 七組參數的差別只在欄位與不變條件，操作完全一樣 —— 故為同一個畫面，
/// 由 [SettingGroup] 驅動。不變條件不成立時擋在儲存這一步，
/// 而非讓每個欄位各自報錯：不變條件是欄位之間的關係，逐欄檢核看不出來。
class SettingGroupScreen extends StatefulWidget {
  final String groupId;
  const SettingGroupScreen({super.key, required this.groupId});

  @override
  State<SettingGroupScreen> createState() => _SettingGroupScreenState();
}

class _SettingGroupScreenState extends State<SettingGroupScreen> {
  late final SettingGroup group = platformConfig.group(widget.groupId);
  late final Map<String, TextEditingController> ctrls = {
    for (final p in group.params) p.key: TextEditingController(text: p.display),
  };
  String? error;

  @override
  void dispose() {
    for (final c in ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, num>? _parse() {
    final out = <String, num>{};
    for (final p in group.params) {
      final raw = ctrls[p.key]!.text.trim();
      final v = num.tryParse(raw);
      if (v == null) {
        setState(() => error = '「${p.label}」不是有效的數字。');
        return null;
      }
      if (p.isInt && v != v.roundToDouble()) {
        setState(() => error = '「${p.label}」須為整數。');
        return null;
      }
      out[p.key] = v;
    }
    return out;
  }

  void _save(AppState s) {
    final next = _parse();
    if (next == null) return;
    final failure = s.applySettings(group.id, next);
    if (failure != null) {
      setState(() => error = failure);
      return;
    }
    setState(() => error = null);
    showToast(context, '已設定');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final allowed = s.canConfigure;

    return Scaffold(
      backgroundColor: C.bgPage,
      appBar: AppBar(title: Text(group.command)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          S.base,
          S.base,
          S.base,
          S.scrollBottom,
        ),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(group.event, style: T.body(weight: FontWeight.w600)),
                const SizedBox(height: S.sm),
                Text(group.note, style: T.caption()),
              ],
            ),
          ),
          if (!allowed) ...[
            const SizedBox(height: S.md),
            AppCard(
              borderColor: C.statusError,
              child: Row(
                children: [
                  const Icon(
                    Icons.lock_outline,
                    size: Sz.iconDense,
                    color: C.statusError,
                  ),
                  const SizedBox(width: S.md),
                  Expanded(
                    child: Text(
                      s.admin.status == AdminStatus.disabled
                          ? '帳號已停用，不得執行任何管理員 Command。'
                          : '權限組未涵蓋「平台設定」，本頁為唯讀。',
                      style: T.caption(color: C.statusError),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SectionTitle('參數'),
          for (final p in group.params) ...[
            _ParamField(param: p, controller: ctrls[p.key]!, enabled: allowed),
            const SizedBox(height: S.md),
          ],
          if (error != null)
            AppCard(
              borderColor: C.statusError,
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: Sz.iconDense,
                    color: C.statusError,
                  ),
                  const SizedBox(width: S.md),
                  Expanded(
                    child: Text(error!, style: T.caption(color: C.statusError)),
                  ),
                ],
              ),
            ),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(S.base, S.md, S.base, S.base),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppButton(
              label: '儲存設定',
              onPressed: allowed ? () => _save(s) : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _ParamField extends StatelessWidget {
  final SettingParam param;
  final TextEditingController controller;
  final bool enabled;
  const _ParamField({
    required this.param,
    required this.controller,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(param.label, style: T.body(weight: FontWeight.w600)),
            ),
            SizedBox(
              width: 120,
              child: TextField(
                controller: controller,
                enabled: enabled,
                textAlign: TextAlign.right,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: false,
                ),
                style: T.numberS(),
                decoration: InputDecoration(
                  isDense: true,
                  suffixText: param.unit,
                  suffixStyle: T.caption(),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: S.md,
                    vertical: S.sm,
                  ),
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
                    borderSide: const BorderSide(
                      color: C.actionOutline,
                      width: 2,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        if (param.hint != null) ...[
          const SizedBox(height: S.sm),
          Text(param.hint!, style: T.caption()),
        ],
      ],
    ),
  );
}
