import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data/ai_suggestion.dart';
import 'data/ai_suggestion_http.dart';
import 'data/auth.dart';
import 'data/platform_data.dart';
import 'data/platform_data_firestore.dart';
import 'data/follow_data.dart';
import 'data/follow_data_firestore.dart';
import 'data/chat_data.dart';
import 'data/mentor_data.dart';
import 'data/mentor_data_firestore.dart';
import 'data/report_data.dart';
import 'data/report_data_firestore.dart';
import 'data/appeal_data.dart';
import 'data/appeal_data_firestore.dart';
import 'data/punishment_data.dart';
import 'data/quality_score_data.dart';
import 'data/quality_score_http.dart';
import 'data/punishment_data_firestore.dart';
import 'data/violation_data.dart';
import 'data/violation_data_firestore.dart';
import 'data/team_data.dart';
import 'data/team_data_firestore.dart';
import 'data/chat_data_firestore.dart';
import 'data/post_data.dart';
import 'data/photo_data.dart';
import 'data/photo_data_firestore.dart';
import 'data/post_data_firestore.dart';
import 'data/public_profile.dart';
import 'data/public_profile_firestore.dart';
import 'data/store.dart';
import 'data/store_firestore.dart';
import 'firebase_options.dart';
import 'screens/auth_gate.dart';
import 'screens/boot_screen.dart';
import 'screens/signup/signup_screen.dart';
import 'screens/signup/terms_reconsent_screen.dart';
import 'screens/train/tasks_screen.dart';
import 'state/app_state.dart';
import 'theme.dart';

/// 正式環境對外的網域。Firebase Hosting 給每個專案兩個網址
/// （`.web.app` 與 `.firebaseapp.com`），這裡選定前者為正式對外的那一個。
const _kWebHost = 'alchemy-workout.web.app';

/// Firebase 設定。
///
/// **Web 版要把 `authDomain` 改成 App 自己的網域。**
///
/// `flutterfire configure` 產生的預設值是 `<專案>.firebaseapp.com`，
/// 而 App 開在 `<專案>.web.app` —— 兩個不同的來源。
/// Google 登入會轉址到驗證頁再轉回來，而瀏覽器（Chrome 與 Safari 都在收緊）
/// 會把不同來源的 sessionStorage 隔開，於是轉回來時讀不到登入前寫下的狀態，
/// 報 `missing initial state`，登入永遠走不完。
///
/// Firebase Hosting 在**每一個**網域上都提供 `/__/auth/handler`，
/// 所以把 authDomain 指到同一個網域即可全程同源。
/// 這是設定問題，不動任何畫面或流程。
FirebaseOptions _firebaseOptions() => kIsWeb
    ? DefaultFirebaseOptions.web.copyWith(authDomain: _kWebHost)
    : DefaultFirebaseOptions.currentPlatform;

/// 我們自己的 Gemini 代理。金鑰在 Cloudflare 的 secret 裡，前端看不到。
///
/// **2026-09-26 換帳號**：原本在 `...ntub.workers.dev`，但那個 Cloudflare
/// 帳號的登入方式已不可考（Cloudflare 回「Your account uses a different
/// login provider」）。改部署到 `a94041198` 這個帳號。
/// 舊的那個仍然活著但沒有人打它了 —— 進得去舊帳號時可以刪掉。
const kAiWorker = 'https://alchemy-workout-ai.a94041198.workers.dev';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.surface,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));
  await Firebase.initializeApp(options: _firebaseOptions());
  // 轉址登入回來時，先把結果收掉再開 App —— 否則 AuthGate 會先看到
  // 「未登入」而畫出登入頁，使用者剛授權完卻又被要求登入一次。
  final auth = AuthService();
  await auth.completePendingSignIn();

  // 正式環境走帳號 ＋ Firestore，不再用本機存檔 ——
  // 換裝置、清瀏覽器資料都不會再從頭開始。
  // 平台公用資料（動作庫、課表、設定…）登入後自 Firestore 載入，
  // 讀不到退回打包在本地的後備（[BE-12]）。
  runApp(FitnessApp(
    auth: auth,
    platformData: FirestorePlatformData(),
    profileFor: (uid) => FirestorePublicProfile(uid: uid),
    followsFor: (uid) => FirestoreFollows(uid: uid),
    postsFor: (uid) => FirestorePosts(uid: uid),
    // 2026-09-28 使用者裁決：照片存 Firestore，不另外開 Cloudflare R2。
    photosFor: (uid) => FirestorePhotos(uid: uid),
    chatsFor: (uid) => FirestoreChats(uid: uid),
    teamsFor: (uid) => FirestoreTeams(uid: uid),
    mentorFor: (uid) => FirestoreMentor(uid: uid),
    reportsFor: (uid) => FirestoreReports(uid: uid),
    violationsFor: FirestoreViolations.new,
    punishmentsFor: FirestorePunishments.new,
    appealsFor: FirestoreAppeals.new,
    // [BE-08]：訓練調整建議交給 Gemini 產生。
    // **呼叫的是我們自己的 Worker，不是 Gemini** —— 金鑰在 Cloudflare
    // 的 secret 裡，前端看不到它。Worker 失敗或模型輸出不合格時，
    // 伺服器會退回與 App 內同一組規則，使用者照樣拿得到建議。
    aiSource: HttpAiSuggestionSource(
      endpoint: Uri.parse(kAiWorker),
      idToken: auth.idToken,
    ),
    // 教官申請的訓練品質評分。**同一個 Worker**（靠請求裡有沒有
    // `sessions` 分流）—— 驗身分與 CORS 完全一樣，分兩條就是同一個
    // 決定寫在兩個地方。失敗時 `AppState` 退回 App 內的規則計算。
    qualitySource: HttpQualityScoreSource(
      endpoint: Uri.parse(kAiWorker),
      idToken: auth.idToken,
    ),
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

  /// 外部的 AI 建議來源（[BE-08]）。空值代表走端內規則 ——
  /// **既有測試全部走這條**。
  final AiSuggestionSource? aiSource;

  /// 關注關係的來源（[BE-11] 批次 2）。空值代表不同步 ——
  /// **既有測試全部走這條**。
  final FollowSource Function(String uid)? followsFor;

  /// 貼文的來源（[BE-11] 批次 3）。空值代表不同步 ——
  /// **既有測試全部走這條**。
  final PostSource Function(String uid)? postsFor;
  final PhotoSource Function(String uid)? photosFor;

  /// 私訊的來源（[BE-14]）。空值代表不同步 —— **既有測試全部走這條**。
  final ChatSource Function(String uid)? chatsFor;

  /// 團隊的來源（[BE-14]）。空值代表不同步 —— **既有測試全部走這條**。
  final TeamSource Function(String uid)? teamsFor;

  /// 師徒的來源（[BE-14]）。空值代表不同步 —— **既有測試全部走這條**。
  final MentorSource Function(String uid)? mentorFor;

  /// 檢舉的來源。空值代表不送上雲 —— **既有測試全部走這條**。
  final ReportSource Function(String uid)? reportsFor;
  final ViolationSource Function()? violationsFor;
  final PunishmentSource Function()? punishmentsFor;
  final QualityScoreSource? qualitySource;
  final AppealSource Function()? appealsFor;

  const FitnessApp({
    super.key,
    this.store,
    this.auth,
    this.storeFor,
    this.platformData,
    this.profileFor,
    this.aiSource,
    this.followsFor,
    this.postsFor,
    this.photosFor,
    this.chatsFor,
    this.teamsFor,
    this.mentorFor,
    this.reportsFor,
    this.violationsFor,
    this.punishmentsFor,
    this.qualitySource,
    this.appealsFor,
  });
  @override
  State<FitnessApp> createState() => _FitnessAppState();
}

class _FitnessAppState extends State<FitnessApp> with WidgetsBindingObserver {
  /// **接了帳號就不載入示範資料**（[AppState.demo]）。
  ///
  /// 判準沿用這個檔案裡到處都是的那一個：`auth == null` ＝ 沒接後端。
  /// 假貼文、假隊伍、假通知混進真資料裡，使用者分不出哪一則是真的；
  /// 而且那些「別人」在雲端根本不存在，點進去是死路。
  late final state = AppState(demo: widget.auth == null);

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
                // 裝置層的小記事本 —— 只記「這台裝置登入過」，不綁 uid。
                // **測試不傳**，於是登入頁一律走「開始吧」那一版，
                // 既有測試不受影響。
                deviceStore: deviceStore(),
                platformData: widget.platformData,
                profileFor: widget.profileFor,
                aiSource: widget.aiSource,
                qualitySource: widget.qualitySource,
                followsFor: widget.followsFor,
                postsFor: widget.postsFor,
                photosFor: widget.photosFor,
                chatsFor: widget.chatsFor,
                teamsFor: widget.teamsFor,
                mentorFor: widget.mentorFor,
                reportsFor: widget.reportsFor,
                violationsFor: widget.violationsFor,
                punishmentsFor: widget.punishmentsFor,
                appealsFor: widget.appealsFor,
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
        onFinish: () {
          setState(() => _needsSignUp = false);
          openNoviceTaskAfterSignUp(context);
        },
      );
    }
    return const TermsGate();
  }
}

