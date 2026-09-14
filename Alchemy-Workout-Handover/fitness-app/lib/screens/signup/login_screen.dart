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

  /// Google 授權。空值代表這次沒有接後端（既有測試與流程示範走這條），
  /// 按鈕退回 [onThirdParty] 的假路徑。
  ///
  /// **授權成功後不由這裡推進畫面** —— 回傳只用來關掉載入中。
  /// 換頁是 [AuthGate] 收到登入事件之後的事，兩邊都推進會變成競態。
  final Future<bool> Function()? onGoogle;

  const LoginPane({
    super.key,
    required this.onPhone,
    required this.onThirdParty,
    this.onGoogle,
  });

  @override
  State<LoginPane> createState() => _LoginPaneState();
}

class _LoginPaneState extends State<LoginPane> {
  final phone = TextEditingController();
  String? error;

  /// 授權視窗開著的期間。按鈕要禁用 —— 不擋的話連按兩下會開兩個視窗，
  /// 而第二個的結果會覆蓋第一個。
  bool _authorizing = false;

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

  Future<void> _google() async {
    final go = widget.onGoogle;
    // 沒接後端：沿用原本的假路徑（流程示範與既有測試走這條）。
    if (go == null) {
      widget.onThirdParty('you@gmail.com');
      return;
    }

    setState(() {
      _authorizing = true;
      error = null;
    });
    try {
      await go();
      // 成功的話 [AuthGate] 已經在換畫面了，這裡不必做任何事；
      // 使用者中途取消也一樣 —— 停在原地，不顯示錯誤。
    } catch (e) {
      // 【必須】錯誤必須有文字，不可只靠紅色或靜靜地沒反應。
      if (mounted) setState(() => error = '登入沒有成功，請再試一次。（$e）');
    } finally {
      if (mounted) setState(() => _authorizing = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
        padding:
            const EdgeInsets.fromLTRB(S.base, S.xl, S.base, S.scrollBottom),
        children: [
          // **不可以寫「歡迎回來」** —— 這一頁只有第一次來的人看得到
          //（AppBar 標題就是「建立帳號」）。對素未謀面的人說「回來」，
          // 第一個感覺是「我是不是以前註冊過卻忘了」。
          // 等真的有「既有帳號登入」那條路徑時，再依情境分兩種文案。
          Text('開始吧', style: T.h1()),
          const SizedBox(height: S.sm),
          Text('選一種方式建立帳號，只要一分鐘',
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
            // 尚未接上真的授權 —— 需要 Apple 開發者帳號（見 PROGRESS.md DEP-03）。
            onPressed: _authorizing
                ? null
                : () => widget.onThirdParty('a1b2c3@privaterelay.appleid.com'),
          ),
          const SizedBox(height: S.md),
          AppButton(
            label: _authorizing ? '授權中…' : '使用 Google 帳號繼續',
            kind: BtnKind.secondary,
            icon: Icons.g_mobiledata_rounded,
            onPressed: _authorizing ? null : _google,
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
