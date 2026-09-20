import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// 帳號的邊界。
///
/// App 其餘部分只認這個類別，不直接碰 `FirebaseAuth` ——
/// 理由與 [Store] 相同：日後要換供應商（加上 Apple 登入、接回手機簡訊
/// 驗證）時，改這一個檔案就好。
///
/// ## 為什麼不用 `google_sign_in` 套件
///
/// 用 `firebase_auth` 內建的 OAuth 流程，而不是 `google_sign_in`：
///
/// 1. **Web 版的按鈕外觀是我們自己的。** `google_sign_in` 在 Web 上規定
///    必須用它自己渲染的按鈕元件（`renderButton()`），套不上 `AppButton`
///    的樣式 —— 那等於為了接後端而偏離 UI 規格書。
/// 2. **Android 不必先註冊 SHA-1 憑證指紋。** 原生流程沒有指紋就直接
///    回 `DEVELOPER_ERROR`，而指紋只能人工貼到 Console。
/// 3. 少一個依賴，也少一套 v6→v7 破壞性改版的相容問題。
///
/// 代價是登入走系統瀏覽器而不是原生的帳號選擇器，體驗略遜一階。
/// 要換回原生流程的話，只需要改這個檔案，呼叫端不受影響。
class AuthService {
  AuthService({FirebaseAuth? auth}) : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  /// 登入狀態的變化。`null` 表示未登入。
  ///
  /// [AuthGate] 監看這個 stream 決定要顯示登入流程還是主畫面 ——
  /// **登入的結果只由這裡宣布**，不由按鈕的 callback 宣布。
  /// 按鈕自己推進畫面的話，會跟這個 stream 形成兩個來源，
  /// 兩邊誰先到沒有保證，就是一個會偶發的競態。
  Stream<User?> authStateChanges() => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  /// 目前使用者的 Firebase ID token。沒登入回空值。
  ///
  /// 給 `[BE-08]` 的 AI 代理用 —— Worker 靠它認出是誰在呼叫。
  /// **放在這裡而不是讓呼叫端自己抓**：`firebase_auth` 就該只出現在
  /// `lib/data/` 底下，`ai_suggestion_http.dart` 不必知道它的存在。
  Future<String?> idToken() async => _auth.currentUser?.getIdToken();

  /// 用 Google 帳號登入。
  ///
  /// 使用者中途取消時回傳 `false`，不算錯誤 —— 呼叫端不必顯示任何訊息，
  /// 停在原本的登入頁即可。真正的失敗（沒網路、供應商沒啟用）往上拋
  /// [FirebaseAuthException]，由呼叫端顯示文字。
  Future<bool> signInWithGoogle() async {
    final provider = GoogleAuthProvider()
      // 每次都跳出帳號選擇，不要默默沿用上次那個 ——
      // 換帳號登入是這個 App 少數會用到的除錯手段（只有一位使用者的
      // 那些流程要靠第二個帳號才測得到）。
      ..setCustomParameters({'prompt': 'select_account'});

    try {
      if (kIsWeb) {
        // **轉址而不是彈出視窗。**
        //
        // 手機瀏覽器多半會擋掉彈出視窗（或改開新分頁，結果一樣不通），
        // 所以 signInWithPopup 那條路在手機上本來就不可靠。
        // 轉址是整頁跳走再跳回來，兩種裝置走同一條路。
        //
        // 前提是 authDomain 與 App 同源（見 main.dart 的 _firebaseOptions）——
        // 不同源的話轉回來會讀不到登入前寫下的狀態，報 missing initial state。
        //
        // 這個呼叫之後頁面就會跳走，下面的 return 不會執行到；
        // 回來時由 [completePendingSignIn] 收尾。
        await _auth.signInWithRedirect(provider);
      } else {
        await _auth.signInWithProvider(provider);
      }
      return true;
    } on FirebaseAuthException catch (e) {
      if (_userCancelled(e.code)) return false;
      rethrow;
    }
  }

  /// 收掉一次轉址登入的結果。
  ///
  /// 轉址流程會讓整個 App 重新載入，所以「登入成功」這件事不是由
  /// [signInWithGoogle] 回報的 —— 它在轉址當下就結束了。
  /// 回來之後必須呼叫這個，Firebase 才會把授權碼換成登入狀態並發出
  /// [authStateChanges] 事件。
  ///
  /// **啟動時一定要呼叫**，而且失敗不可以擋住 App 開啟 ——
  /// 沒有待處理的轉址時它也會正常回傳，那是最常見的情況（一般啟動）。
  Future<void> completePendingSignIn() async {
    if (!kIsWeb) return;
    try {
      await _auth.getRedirectResult();
    } catch (_) {
      // 轉址失敗（使用者中途取消、逾時）只代表這次沒登入成功，
      // 不該讓 App 開不起來 —— 使用者會回到登入頁，再按一次即可。
    }
  }

  /// 使用者自己關掉授權視窗／按了取消。
  ///
  /// 各平台回的代碼不同，全部視為同一件事：他改變主意了，沒有出錯。
  bool _userCancelled(String code) => const {
        'popup-closed-by-user',
        'cancelled-popup-request',
        'user-cancelled',
        'web-context-canceled',
      }.contains(code);

  Future<void> signOut() => _auth.signOut();
}
