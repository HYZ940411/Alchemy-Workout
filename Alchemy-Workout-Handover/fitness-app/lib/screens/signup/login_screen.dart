import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../domain/registration.dart';
import '../../widgets/common.dart';

/// 登入頁 —— 註冊入口二選一
///
/// 手機簡訊驗證 或 第三方登入授權，完成其一後才建立帳號。
/// 第三方登入者於授權時帶入電子郵件；手機註冊者不強制填寫電子郵件。
class LoginPane extends StatefulWidget {
  /// 手機路徑：把號碼交給呼叫端，接著進驗證頁。
  final ValueChanged<String> onPhone;

  /// 第三方路徑：授權完成即帶回電子郵件。
  final void Function(String email) onThirdParty;

  const LoginPane({
    super.key,
    required this.onPhone,
    required this.onThirdParty,
  });

  @override
  State<LoginPane> createState() => _LoginPaneState();
}

class _LoginPaneState extends State<LoginPane> {
  final phone = TextEditingController();
  String? error;

  @override
  void initState() {
    super.initState();
    phone.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    phone.dispose();
    super.dispose();
  }

  void _send() {
    if (!isValidPhone(phone.text)) {
      setState(() => error = '手機號碼格式不正確（應為 09 開頭的 10 位數字）。');
      return;
    }
    setState(() => error = null);
    widget.onPhone(phone.text.replaceAll(RegExp(r'[\s-]'), ''));
  }

  @override
  Widget build(BuildContext context) => ListView(
        padding:
            const EdgeInsets.fromLTRB(S.base, S.xl, S.base, S.scrollBottom),
        children: [
          Text('歡迎回來', style: T.h1()),
          const SizedBox(height: S.sm),
          Text('輸入手機號碼，我們會傳一組驗證碼給你',
              style: T.body(color: C.textSecondary)),
          const SizedBox(height: S.xl),

          Text('手機號碼', style: T.caption()),
          const SizedBox(height: S.xs),
          TextField(
            controller: phone,
            keyboardType: TextInputType.phone,
            style: T.body(),
            decoration: InputDecoration(
              hintText: '09xx xxx xxx',
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
                borderSide: BorderSide(
                    color: error == null ? C.lineDivider : C.statusError),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(R.control),
                borderSide: const BorderSide(color: C.actionOutline, width: 2),
              ),
            ),
          ),
          // 【必須】錯誤必須有文字，不可只靠紅色
          if (error != null) ...[
            const SizedBox(height: S.xs),
            Text(error!, style: T.caption(color: C.statusError)),
          ],
          const SizedBox(height: S.base),
          AppButton(
            label: '發送驗證碼',
            onPressed: phone.text.trim().isEmpty ? null : _send,
          ),

          const SizedBox(height: S.lg),
          Row(
            children: [
              const Expanded(child: Divider(color: C.lineDivider)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: S.md),
                child: Text('或', style: T.caption()),
              ),
              const Expanded(child: Divider(color: C.lineDivider)),
            ],
          ),
          const SizedBox(height: S.lg),

          AppButton(
            label: '使用 Apple 帳號繼續',
            kind: BtnKind.secondary,
            icon: Icons.apple,
            // Apple 登入取得的可能為私密轉發信箱。
            onPressed: () => widget.onThirdParty('a1b2c3@privaterelay.appleid.com'),
          ),
          const SizedBox(height: S.md),
          AppButton(
            label: '使用 Google 帳號繼續',
            kind: BtnKind.secondary,
            icon: Icons.g_mobiledata_rounded,
            onPressed: () => widget.onThirdParty('you@gmail.com'),
          ),

          const SizedBox(height: S.xl),
          Text(
            '繼續即表示你同意服務條款與隱私權政策',
            textAlign: TextAlign.center,
            style: T.caption(),
          ),
        ],
      );
}
