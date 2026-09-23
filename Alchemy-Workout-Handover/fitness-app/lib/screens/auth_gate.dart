import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../data/ai_suggestion.dart';
import '../data/auth.dart';
import '../data/platform_data.dart';
import '../data/public_profile.dart';
import '../data/follow_data.dart';
import '../data/post_data.dart';
import '../data/chat_data.dart';
import '../data/team_data.dart';
import '../data/mentor_data.dart';
import '../data/store.dart';
import '../state/app_state.dart';
import 'boot_screen.dart';
import 'home_shell.dart';
import 'signup/signup_screen.dart';
import 'train/tasks_screen.dart';

/// 依登入狀態決定要顯示登入流程還是這個帳號的內容。
///
/// **這是唯一宣布「誰登入了」的地方。** 登入按鈕本身不推進畫面 ——
/// 它只負責發起授權，結果由 [AuthService.authStateChanges] 這條 stream
/// 宣布。兩邊都能推進畫面的話，哪個先到沒有保證，就是一個會偶發的競態。
///
/// 沒有登入的人看到的是註冊流程，**而且進不到 [BootGate] 底下** ——
/// 所以上一個帳號留在記憶體裡的數字不會有機會被畫出來。
class AuthGate extends StatefulWidget {
  final AuthService auth;
  final AppState state;

  /// 建立這個帳號的儲存後端。測試改傳一個假的，就不必連真的 Firestore。
  final Store Function(String uid) storeFor;

  /// 這台裝置的小記事本。**不綁 uid** —— 登入頁要在還不知道使用者是誰
  /// 的時候，回答「這台裝置登入過嗎」。空值代表不記（既有測試走這條）。
  final Store? deviceStore;

  /// 平台公用唯讀資料的來源（[BE-12]）。空值代表不載入，維持本地後備。
  final PlatformDataSource? platformData;

  /// 公開檔案的來源（[BE-11] 批次 1）。依 uid 建立 —— 它既要寫我自己的，
  /// 也要讀別人的，所以需要知道「我是誰」。空值代表不同步。
  final PublicProfileSource Function(String uid)? profileFor;

  /// 外部的 AI 建議來源（[BE-08]）。空值代表走端內規則。
  final AiSuggestionSource? aiSource;

  /// 關注關係的來源（[BE-11] 批次 2）。空值代表不同步。
  final FollowSource Function(String uid)? followsFor;

  /// 貼文的來源（[BE-11] 批次 3）。空值代表不同步。
  final PostSource Function(String uid)? postsFor;

  /// 私訊的來源（[BE-14]）。空值代表不同步。
  final ChatSource Function(String uid)? chatsFor;

  /// 團隊的來源（[BE-14]）。空值代表不同步。
  final TeamSource Function(String uid)? teamsFor;

  /// 師徒的來源（[BE-14]）。空值代表不同步。
  final MentorSource Function(String uid)? mentorFor;

  const AuthGate({
    super.key,
    required this.auth,
    required this.state,
    required this.storeFor,
    this.deviceStore,
    this.platformData,
    this.profileFor,
    this.aiSource,
    this.followsFor,
    this.postsFor,
    this.chatsFor,
    this.teamsFor,
    this.mentorFor,
  });

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  StreamSubscription<User?>? _sub;

  /// 還沒收到第一個事件。
  ///
  /// 與「收到了，而且是未登入」是兩回事：Firebase 要先讀完本機的憑證快取
  /// 才知道上次是誰登入的。這段期間若直接當成未登入，每次冷啟動都會
  /// 閃一下登入頁，然後才跳回主畫面。
  bool _waiting = true;

  User? _user;

  /// 已經為哪一個 uid 讀過存檔。
  ///
  /// `authStateChanges` 會在權杖換新時重發同一位使用者 ——
  /// 不擋的話每次換新都重讀一次存檔，把使用者當下未存檔的操作蓋掉。
  String? _hydratedFor;

  /// 平台資料是否已載入過 —— 與 [_hydratedFor] 同理，擋 `authStateChanges`
  /// 在權杖換新時重發使用者而重複載入。平台資料不分帳號，只需載一次。
  bool _platformLoaded = false;

  /// 已為哪一個 uid 同步過公開檔案。與 [_hydratedFor] 同理，
  /// 擋 `authStateChanges` 在權杖換新時重發使用者而重複同步。
  String? _profileSyncedFor;

  /// 這台裝置成功登入過沒有。決定登入頁說「開始吧」還是「歡迎回來」。
  ///
  /// **讀完之前先當作沒有。** 猜錯的方向要選傷害小的那一邊：對老手說
  /// 「開始吧」只是囉嗦，對新手說「歡迎回來」會讓他以為自己忘了舊帳號。
  bool _returning = false;

  @override
  void initState() {
    super.initState();

    // **AI 代理在這裡接，不要放進 `_syncProfile`。**
    //
    // 它原本在那裡面，而那個函式有六個接連的網路 await（發布公開檔案、
    // 讀別人的、貼文、私訊、團隊、師徒），整段包在 try/catch 裡。
    // 任何一個失敗，catch 吞掉，`aiSource` 就永遠不會被設 ——
    // 而 `aiProduceSuggestionAsync` 看到空值會**靜靜地**退回端內規則，
    // 不留任何痕跡。症狀是「AI 建議沒有理由、替換動作說沒東西可換、
    // Worker 的 log 完全沒有流量」，查到第三層才會發現原因在這裡。
    //
    // 它不需要 uid，也不需要載入任何東西 —— token 是按下調整那一刻
    // 才抓的。沒有理由讓它依賴六個不相干的網路呼叫。
    widget.state.aiSource = widget.aiSource;

    // 讀裝置層的記事本。**不 await** —— 讀不到只是文案退回「開始吧」，
    // 不該擋住登入頁畫出來。
    final dev = widget.deviceStore;
    if (dev != null) {
      hasSignedInBefore(dev).then((seen) {
        if (mounted && seen) setState(() => _returning = true);
      });
    }

    _sub = widget.auth.authStateChanges().listen(_onAuthChanged);
  }

  void _onAuthChanged(User? user) {
    // 登入成功就記下來。**即發即忘**：寫不進去最多是下次文案退回
    // 「開始吧」，不該影響登入本身。
    if (user != null) {
      final dev = widget.deviceStore;
      if (dev != null) markSignedIn(dev).catchError((_) {});
    }
    if (user != null && _hydratedFor != user.uid) {
      _hydratedFor = user.uid;
      // 先呼叫再 setState：hydrate 是同步把狀態設成 loading 的，
      // 所以這之後的第一次 build 就會畫載入中，不會閃到上一個帳號的數字。
      widget.state.hydrate(widget.storeFor(user.uid));
    }
    // 平台資料的讀取需要已登入（安全規則要求 auth != null）。
    // **不 await**：載入是即發即忘的，完成時 applyPlatformData 會 notifyListeners
    // 觸發重繪，不擋載入畫面等網路（動作庫等離線後備本就已在記憶體裡）。
    if (user != null) {
      _loadPlatformData();
      _syncProfile(user.uid);
    }
    if (user == null) {
      _hydratedFor = null;
      _platformLoaded = false;
      _profileSyncedFor = null;
    }
    if (mounted) {
      setState(() {
        _waiting = false;
        _user = user;
      });
    }
  }

  Future<void> _loadPlatformData() async {
    if (_platformLoaded) return;
    final src = widget.platformData;
    if (src == null) return;
    _platformLoaded = true;
    try {
      widget.state.applyPlatformData(await src.load());
    } catch (_) {
      // 載入失敗維持本地後備，不擋使用者進場；允許下次登入事件重試。
      _platformLoaded = false;
    }
  }

  /// 把我自己的公開檔案寫上去，並讀回平台上的其他人（[BE-11] 批次 1）。
  ///
  /// **不 await**：即發即忘。這件事失敗不該擋住使用者進場 ——
  /// 社群功能拿不到別人的資料只是少了內容，訓練與簽到照樣能用。
  ///
  /// ## 為什麼每一塊各自 try
  ///
  /// 原本整段包在**同一個** `try/catch` 裡。於是任何一個 await 失敗，
  /// catch 吞掉，**後面每一塊都不執行** —— 而且完全沒有跡象。
  ///
  /// 這個結構造成過三個線上故障，當時看起來毫不相干：
  ///   · AI 代理從來沒被接上（`aiSource` 那行排在最後面）
  ///   · 建立團隊後重新整理就消失（`teamSource` 沒設，寫不上雲端）
  ///   · 私訊讀不到（`conversations` 的複合查詢缺索引而拋例外，
  ///     連帶把它後面的團隊、師徒、關注一起帶走）
  ///
  /// **一塊失敗不該波及其他塊。** 它們之間只有一個真正的順序相依：
  /// `applyPublicProfiles` 要先跑，因為其餘幾塊都靠 `nameByUid`
  /// 把 uid 翻回暱稱。除此之外互不相干。
  Future<void> _syncProfile(String uid) async {
    if (_profileSyncedFor == uid) return;
    final make = widget.profileFor;
    if (make == null) return;
    _profileSyncedFor = uid;

    /// 跑一塊。失敗只影響這一塊，並讓整趟同步之後可以重試。
    Future<void> step(String what, Future<String> Function() body) async {
      try {
        // 回傳值是「拿到什麼」的一句話，記進 syncReport 供開發者模式檢視。
        // 這幾塊全部吞掉錯誤 —— 那是對的，但出問題時完全沒有跡象，
        // 「申請送得出去、對方看不到」因此查了三輪都在猜。
        widget.state.reportSync(what, await body());
      } catch (e) {
        debugPrint('登入後同步「$what」失敗：$e');
        widget.state.reportSync(what, '失敗：$e');
        _profileSyncedFor = null; // 允許下次登入事件重試
      }
    }

    // **來源先接上，再談載入。** 接來源不需要網路，卻是之後每一次
    // 寫入雲端的前提 —— 埋在載入後面的話，任何一次讀取失敗都會讓
    // 使用者接下來做的事全部只留在記憶體裡。
    widget.state.myUid = uid;
    widget.state.postSource = widget.postsFor?.call(uid);
    widget.state.chatSource = widget.chatsFor?.call(uid);
    widget.state.teamSource = widget.teamsFor?.call(uid);
    widget.state.mentorSource = widget.mentorFor?.call(uid);
    widget.state.followSource = widget.followsFor?.call(uid);

    // 先寫再讀：讓自己在別人的清單裡也看得到，
    // 順序顛倒的話新使用者第一次登入不會出現在任何人的清單上。
    //
    // **這一塊要先完成**：其餘每一塊都靠 `nameByUid` 把 uid 翻回暱稱。
    final src = make(uid);
    await step('公開檔案', () async {
      await src.publish(widget.state.myPublicProfile(uid));
      final others = await src.others(limit: 50);
      widget.state.applyPublicProfiles(others);
      return '已發布自己，讀到 ${others.length} 位其他使用者';
    });

    final posts = widget.state.postSource;
    if (posts != null) {
      await step('貼文', () async {
        final got = await posts.recent(limit: AppState.kPostFeedLimit);
        widget.state.applyCloudPosts(got);
        return '${got.length} 則';
      });
    }

    final chats = widget.state.chatSource;
    if (chats != null) {
      await step('私訊', () async {
        final got = await chats.conversations(limit: 50);
        widget.state.applyCloudConversations(got);
        return '${got.length} 段對話，'
            '共 ${got.fold<int>(0, (a, c) => a + c.messages.length)} 則訊息';
      });
    }

    final teams = widget.state.teamSource;
    if (teams != null) {
      await step('我的團隊', () async {
        final t = await teams.myTeam();
        widget.state.applyCloudTeam(t);
        return t == null ? '沒有隊伍' : '${t.name}（${t.members.length} 人）';
      });
      // **另外一塊。** 讀我的隊伍失敗，不該連公開團隊清單也看不到。
      await step('公開團隊', () async {
        final got = await teams.openTeams();
        widget.state.applyPublicTeams(got);
        return '${got.length} 支';
      });
      // 待回應的團隊請求。**在此之前沒有任何呼叫端** —— 送出的申請
      // 寫進了 Firestore，但收件的那一方從來不去讀，於是隊長永遠
      // 看不到有人申請加入。要排在 applyCloudTeam 之後：分流時要
      // 知道我自己的隊伍 ID。
      await step('團隊請求', () async {
        final myId = widget.state.myTeam?.id;
        final errors = <String>[];
        final got =
            await teams.requestsFor(uid, myTeamId: myId, errors: errors);
        widget.state.applyCloudTeamRequests(got);
        return '${got.length} 筆'
            '（邀請 ${got.where((r) => r.isInvite).length}／'
            '申請 ${got.where((r) => !r.isInvite).length}）'
            '${myId == null ? '　⚠️ 我沒有隊伍，查不到別人的申請' : ''}'
            '${errors.isEmpty ? '' : '　⚠️ ${errors.join('；')}'}';
      });
    }

    final mentor = widget.state.mentorSource;
    if (mentor != null) {
      await step('師徒', () async {
        final got = await mentor.bonds();
        widget.state.applyCloudBonds(got);
        return '${got.length} 段關係';
      });
      // 待回應的師徒申請。**同樣在此之前沒有任何呼叫端** ——
      // 送出的拜師申請寫進了 Firestore，教官永遠看不到。
      await step('師徒申請', () async {
        final got = await mentor.requestsFor(uid);
        widget.state.applyCloudMentorRequests(got);
        return '${got.length} 筆';
      });
    }

    final follows = widget.state.followSource;
    if (follows != null) {
      await step('關注', () async {
        final a = await follows.following();
        final b = await follows.followers();
        widget.state.applyFollows(a, b);
        return '關注 ${a.length}／粉絲 ${b.length}';
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_waiting) return const BootLoading();

    if (_user == null) {
      return SignUpScreen(
        firstRun: true,
        // 這台裝置登入過的話，講的是「歡迎回來」而不是「建立帳號」。
        returning: _returning,
        auth: widget.auth,
        // 註冊流程走完不必做什麼 —— 畫面要不要換由這個 Gate 決定，
        // 它看的是登入狀態，不是註冊流程的完成回呼。
        onFinish: () {},
      );
    }

    return BootGate(
      child: _SignedInHome(
        email: _user?.email,
        name: _user?.displayName,
        auth: widget.auth,
      ),
    );
  }
}

/// 登入之後：帳號資料還沒填完就先走註冊問卷，填完了就進主畫面。
///
/// 與 [FirstRunGate] 的差別在於「這台裝置上有沒有帳號」已經由 [AuthGate]
/// 回答掉了，這裡回答的是「這個帳號的問卷填完了沒」。
class _SignedInHome extends StatefulWidget {
  final String? email;

  /// Google 帳號上的名字。預帶於註冊流程的暱稱欄，可改。
  final String? name;

  /// 一路帶下去，讓註冊流程知道後端是活的。
  /// 這條路徑理論上看不到登入頁（已登入者會直接跳過入口），
  /// 但不傳的話那一頁會以為沒接後端，把已經失效的手機／Apple
  /// 按鈕重新開放 —— 那是一條沒有人走、卻通往死路的岔路。
  final AuthService? auth;

  const _SignedInHome({this.email, this.name, this.auth});

  @override
  State<_SignedInHome> createState() => _SignedInHomeState();
}

class _SignedInHomeState extends State<_SignedInHome> {
  bool? _needsSignUp;

  @override
  Widget build(BuildContext context) {
    // 只在第一次 build 時決定，之後不再跟著旗標變動改 ——
    // 理由與 [FirstRunGate] 相同：completeSignUp() 在流程的倒數第二步
    // 就把旗標設成 true 了，跟著它走會把最後一頁（訓練計畫推薦）吃掉。
    _needsSignUp ??= !AppScope.of(context).signUpCompleted;

    if (_needsSignUp == true) {
      return SignUpScreen(
        firstRun: true,
        auth: widget.auth,
        // 已經用 Google 授權過了，別再要求他選一次登入方式。
        authorizedEmail: widget.email,
        suggestedName: widget.name,
        onFinish: () {
          setState(() => _needsSignUp = false);
          openNoviceTaskAfterSignUp(context);
        },
      );
    }
    return const HomeShell();
  }
}
