import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data/store.dart';
import 'screens/boot_screen.dart';
import 'screens/home_shell.dart';
import 'screens/signup/signup_screen.dart';
import 'state/app_state.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.surface,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));
  // 由平台決定：手機／桌面存檔案，瀏覽器存 localStorage。
  runApp(FitnessApp(store: defaultStore()));
}

class FitnessApp extends StatefulWidget {
  /// 儲存後端。測試傳 [MemoryStore]，正式由 [defaultStore] 依平台決定。
  /// 傳 null 表示完全不持久化 —— 既有的 widget 測試走這條，
  /// 免得每跑一次測試就往磁碟寫一份狀態。
  final Store? store;
  const FitnessApp({super.key, this.store});
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
    final store = widget.store;
    if (store != null) state.hydrate(store);
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
  Widget build(BuildContext context) => AppScope(
        state: state,
        child: MaterialApp(
          title: '健金術 Alchemy Workout',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(),
          // 讀完存檔才進主畫面。載入中與讀取失敗各有自己的畫面。
          home: const BootGate(child: FirstRunGate()),
        ),
      );
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
