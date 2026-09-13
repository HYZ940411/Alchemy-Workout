import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data/auth.dart';
import 'data/platform_data.dart';
import 'data/platform_data_firestore.dart';
import 'data/follow_data.dart';
import 'data/follow_data_firestore.dart';
import 'data/public_profile.dart';
import 'data/public_profile_firestore.dart';
import 'data/store.dart';
import 'data/store_firestore.dart';
import 'firebase_options.dart';
import 'screens/auth_gate.dart';
import 'screens/boot_screen.dart';
import 'screens/home_shell.dart';
import 'screens/signup/signup_screen.dart';
import 'state/app_state.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.surface,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  // 正式環境走帳號 ＋ Firestore，不再用本機存檔 ——
  // 換裝置、清瀏覽器資料都不會再從頭開始。
  // 平台公用資料（動作庫、課表、設定…）登入後自 Firestore 載入，
  // 讀不到退回打包在本地的後備（[BE-12]）。
  runApp(FitnessApp(
    auth: AuthService(),
    platformData: FirestorePlatformData(),
    profileFor: (uid) => FirestorePublicProfile(uid: uid),
    followsFor: (uid) => FirestoreFollows(uid: uid),
  ));
}

class FitnessApp extends StatefulWidget {
  /// 儲存後端。測試傳 [MemoryStore]，正式由 [defaultStore] 依平台決定。
  /// 傳 null 表示完全不持久化 —— 既有的 widget 測試走這條，
  /// 免得每跑一次測試就往磁碟寫一份狀態。
  final Store? store;

  /// 帳號。空值代表這次不接後端 —— **既有的 widget 測試全部走這條**，
  /// 行為與加後端之前完全一樣，不必為了 BE-04 去碰那 1,212 個測試。
  final AuthService? auth;

  /// 依 uid 建立儲存後端。測試改傳一個假的就不必連真的 Firestore。
  final Store Function(String uid)? storeFor;

  /// 平台公用唯讀資料的來源。空值代表不載入（維持打包在本地的後備）——
  /// **既有測試全部走這條**，動作庫/課表/成就等與上雲前完全一樣。
  final PlatformDataSource? platformData;

  /// 公開檔案的來源（[BE-11] 批次 1）。空值代表不同步 ——
  /// **既有測試全部走這條**，社群清單與上雲前完全一樣。
  final PublicProfileSource Function(String uid)? profileFor;

  /// 關注關係的來源（[BE-11] 批次 2）。空值代表不同步 ——
  /// **既有測試全部走這條**。
  final FollowSource Function(String uid)? followsFor;

  const FitnessApp({
    super.key,
    this.store,
    this.auth,
    this.storeFor,
    this.platformData,
    this.profileFor,
    this.followsFor,
  });
  @override
  State<FitnessApp> createState() => _FitnessAppState();
}

class _FitnessAppState extends State<FitnessApp> with WidgetsBindingObserver {
  final state = AppState();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 讀回上次的狀態。讀不到就沿用假資料 —— App 照常開得起來。
    //
    // 接了帳號就不在這裡讀：要先知道是誰，才知道該讀誰的。
    // 那件事由 [AuthGate] 在收到登入事件時做。
    final store = widget.store;
    if (store != null && widget.auth == null) state.hydrate(store);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    // 進背景或被關掉前立刻寫入，補上防抖那 300ms 可能漏掉的最後一筆。
    if (s == AppLifecycleState.inactive ||
        s == AppLifecycleState.paused ||
        s == AppLifecycleState.detached) {
      state.saveNow();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = widget.auth;
    return AppScope(
      state: state,
      child: MaterialApp(
        title: '健金術 Alchemy Workout',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: auth == null
            // 沒接帳號：讀完存檔才進主畫面。載入中與讀取失敗各有自己的畫面。
            ? const BootGate(child: FirstRunGate())
            // 接了帳號：先確定是誰，再讀他的資料。
            : AuthGate(
                auth: auth,
                state: state,
                storeFor: widget.storeFor ??
                    (uid) => FirestoreStore(uid: uid),
                platformData: widget.platformData,
                profileFor: widget.profileFor,
                followsFor: widget.followsFor,
              ),
      ),
    );
  }
}

/// 這台裝置上還沒有帳號時，先走註冊流程。
///
/// **用閂鎖而不是直接看 `signUpCompleted`**：註冊的最後一步是
/// 「訓練計畫已推薦」，而 `completeSignUp()` 在**前一步**就把那個旗標
/// 設成 true 了（帳號要先建立，推薦頁才進得去 —— 那是模型的 Precondition）。
/// 直接跟著旗標走的話，畫面會在倒數第二步就切到主畫面，
/// 把整個流程的最後一頁吃掉。
class FirstRunGate extends StatefulWidget {
  const FirstRunGate({super.key});

  @override
  State<FirstRunGate> createState() => _FirstRunGateState();
}

class _FirstRunGateState extends State<FirstRunGate> {
  bool? _needsSignUp;

  @override
  Widget build(BuildContext context) {
    // 只在第一次 build 時決定，之後不再跟著狀態變動改。
    _needsSignUp ??= !AppScope.of(context).signUpCompleted;
    if (_needsSignUp == true) {
      return SignUpScreen(
        firstRun: true,
        onFinish: () => setState(() => _needsSignUp = false),
      );
    }
    return const HomeShell();
  }
}
