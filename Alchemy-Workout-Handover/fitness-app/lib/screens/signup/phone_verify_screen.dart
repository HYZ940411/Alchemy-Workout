import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design/tokens.dart';
import '../../domain/registration.dart';
import '../../widgets/common.dart';

/// 手機驗證頁（〈註冊流程〉：使用者手機已驗證）
///
/// 六格驗證碼。重新發送有冷卻秒數 —— 否則按鈕會被連點成簡訊轟炸。
/// 驗證碼本身由簡訊服務產生，屬系統邊界之外；本頁只負責「輸滿六碼並送出」。
class PhoneVerifyPane extends StatefulWidget {
  final String phone;
  final VoidCallback onVerified;
  const PhoneVerifyPane({
    super.key,
    required this.phone,
    required this.onVerified,
  });

  @override
  State<PhoneVerifyPane> createState() => _PhoneVerifyPaneState();
}

class _PhoneVerifyPaneState extends State<PhoneVerifyPane> {
  final code = TextEditingController();
  final focus = FocusNode();
  int cooldown = kSmsResendSeconds;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    code.addListener(() => setState(() {}));
    _startCooldown();
    WidgetsBinding.instance.addPostFrameCallback((_) => focus.requestFocus());
  }

  void _startCooldown() {
    timer?.cancel();
    setState(() => cooldown = kSmsResendSeconds);
    timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => cooldown -= 1);
      if (cooldown <= 0) t.cancel();
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    code.dispose();
    focus.dispose();
    super.dispose();
  }

  String get _digits => code.text.replaceAll(RegExp(r'\D'), '');
  bool get _full => _digits.length == kSmsCodeLength;

  String _masked() {
    final p = widget.phone;
    if (p.length < 10) return p;
    return '${p.substring(0, 4)} ${p.substring(4, 7)} ${p.substring(7)}';
  }

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                  S.base, S.xl, S.base, S.scrollBottom),
              children: [
                Text('輸入驗證碼', style: T.h1()),
                const SizedBox(height: S.sm),
                Text('已發送至 ${_masked()}',
                    style: T.body(color: C.textSecondary)),
                const SizedBox(height: S.xl),

                // 六個格子只是外觀 —— 真正接收輸入的是底下那一個看不見的
                // TextField。分成六個各自持有焦點的欄位會讓刪除鍵、
                // 貼上整組驗證碼、自動填入三件事全部要各自處理。
                Stack(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        for (var i = 0; i < kSmsCodeLength; i++)
                          _Cell(
                            digit: i < _digits.length ? _digits[i] : '',
                            active: i == _digits.length && focus.hasFocus,
                          ),
                      ],
                    ),
                    Positioned.fill(
                      child: Opacity(
                        opacity: 0,
                        child: TextField(
                          controller: code,
                          focusNode: focus,
                          keyboardType: TextInputType.number,
                          maxLength: kSmsCodeLength,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: const InputDecoration(counterText: ''),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: S.lg),
                Center(
                  child: cooldown > 0
                      ? Text('沒收到？ 重新發送（$cooldown）', style: T.caption())
                      : GestureDetector(
                          onTap: _startCooldown,
                          child: Text('沒收到？ 重新發送',
                              style: T.caption(color: C.actionOutline)),
                        ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(S.base, S.md, S.base, S.base),
            child: AppButton(
              label: '下一步',
              onPressed: _full ? widget.onVerified : null,
            ),
          ),
        ],
      );
}

class _Cell extends StatelessWidget {
  final String digit;
  final bool active;
  const _Cell({required this.digit, required this.active});

  @override
  Widget build(BuildContext context) => Container(
        width: 48,
        height: 56,
        decoration: BoxDecoration(
          color: C.bgSurface,
          borderRadius: BorderRadius.circular(R.control),
          border: Border.all(
            color: active ? C.actionOutline : C.lineDivider,
            width: active ? 2 : 1,
          ),
        ),
        alignment: Alignment.center,
        child: Text(digit, style: T.numberM()),
      );
}
