import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

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

  /// 平台公用唯讀資料的來源（[BE-12]）。空值代表不載入，維持本地後備。
  final PlatformDataSource? platformData;

  /// 公開檔案的來源（[BE-11] 批次 1）。依 uid 建立 —— 它既要寫我自己的，
  /// 也要讀別人的，所以需要知道「我是誰」。空值代表不同步。
  final PublicProfileSource Function(String uid)? profileFor;

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
    this.platformData,
    this.profileFor,
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

  @override
  void initState() {
    super.initState();
    _sub = widget.auth.authStateChanges().listen(_onAuthChanged);
  }

  void _onAuthChanged(User? user) {
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
  Future<void> _syncProfile(String uid) async {
    if (_profileSyncedFor == uid) return;
    final make = widget.profileFor;
    if (make == null) return;
    _profileSyncedFor = uid;
    final src = make(uid);
    try {
      // 先寫再讀：讓自己在別人的清單裡也看得到，
      // 順序顛倒的話新使用者第一次登入不會出現在任何人的清單上。
      await src.publish(widget.state.myPublicProfile(uid));
      widget.state.applyPublicProfiles(await src.others(limit: 50));

      // **一定要在 applyPublicProfiles 之後**：applyFollows 靠 nameByUid
      // 把 uid 翻回暱稱，而那張表是上一行填的。順序顛倒的話一個都翻不出來。
      // 貼文：先把來源與身分交給 AppState（之後的按讚／留言才寫得上去），
      // 再把既有的貼文讀回來。
      final postsSrc = widget.postsFor?.call(uid);
      if (postsSrc != null) {
        widget.state.myUid = uid;
        widget.state.postSource = postsSrc;
        widget.state.applyCloudPosts(await postsSrc.recent(limit: 30));
      }

      // 私訊。要排在 applyPublicProfiles 之後 —— 對話裡的 uid 要靠
      // nameByUid 翻成暱稱才畫得出來。
      final chats = widget.chatsFor?.call(uid);
      if (chats != null) {
        widget.state.myUid = uid;
        widget.state.chatSource = chats;
        widget.state.applyCloudConversations(await chats.conversations(limit: 50));
      }

      // 團隊。同樣排在 applyPublicProfiles 之後 —— 隊員的暱稱要從
      // 雲端的 uid 翻回來才畫得出名字。
      final teams = widget.teamsFor?.call(uid);
      if (teams != null) {
        widget.state.myUid = uid;
        widget.state.teamSource = teams;
        widget.state.applyCloudTeam(await teams.myTeam());
      }

      // 師徒。同樣要排在 applyPublicProfiles 之後 —— 教官的暱稱
      // 要從 uid 翻回來。
      final mentor = widget.mentorFor?.call(uid);
      if (mentor != null) {
        widget.state.myUid = uid;
        widget.state.mentorSource = mentor;
        widget.state.applyCloudBonds(await mentor.bonds());
      }

      final follows = widget.followsFor?.call(uid);
      if (follows != null) {
        widget.state.followSource = follows;
        widget.state.applyFollows(
          await follows.following(),
          await follows.followers(),
        );
      }
    } catch (_) {
      // 允許下次登入事件重試。
      _profileSyncedFor = null;
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
        auth: widget.auth,
        // 註冊流程走完不必做什麼 —— 畫面要不要換由這個 Gate 決定，
        // 它看的是登入狀態，不是註冊流程的完成回呼。
        onFinish: () {},
      );
    }

    return BootGate(
      child: _SignedInHome(email: _user?.email, auth: widget.auth),
    );
  }
}

/// 登入之後：帳號資料還沒填完就先走註冊問卷，填完了就進主畫面。
///
/// 與 [FirstRunGate] 的差別在於「這台裝置上有沒有帳號」已經由 [AuthGate]
/// 回答掉了，這裡回答的是「這個帳號的問卷填完了沒」。
class _SignedInHome extends StatefulWidget {
  final String? email;

  /// 一路帶下去，讓註冊流程知道後端是活的。
  /// 這條路徑理論上看不到登入頁（已登入者會直接跳過入口），
  /// 但不傳的話那一頁會以為沒接後端，把已經失效的手機／Apple
  /// 按鈕重新開放 —— 那是一條沒有人走、卻通往死路的岔路。
  final AuthService? auth;

  const _SignedInHome({this.email, this.auth});

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
        onFinish: () => setState(() => _needsSignUp = false),
      );
    }
    return const HomeShell();
  }
}
