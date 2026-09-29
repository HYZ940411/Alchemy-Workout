import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../data/ai_suggestion.dart';
import '../data/auth.dart';
import '../data/platform_data.dart';
import '../data/public_profile.dart';
import '../data/follow_data.dart';
import '../data/photo_data.dart';
import '../data/rating_data.dart';
import '../data/post_data.dart';
import '../data/chat_data.dart';
import '../data/team_data.dart';
import '../data/mentor_data.dart';
import '../data/instructor_case_data.dart';
import '../data/report_data.dart';
import '../data/appeal_data.dart';
import '../data/punishment_data.dart';
import '../data/quality_score_data.dart';
import '../data/violation_data.dart';
import '../domain/commerce.dart';
import '../data/store.dart';
import '../domain/admin.dart';
import '../state/app_state.dart';
import 'boot_screen.dart';
import 'signup/signup_screen.dart';
import 'signup/terms_reconsent_screen.dart';
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
  final QualityScoreSource? qualitySource;

  /// 關注關係的來源（[BE-11] 批次 2）。空值代表不同步。
  final FollowSource Function(String uid)? followsFor;

  /// 貼文的來源（[BE-11] 批次 3）。空值代表不同步。
  final PostSource Function(String uid)? postsFor;
  final PhotoSource Function(String uid)? photosFor;

  /// 訓練體驗評分（`[BE-18]`）。
  final RatingSource Function(String uid)? ratingsFor;

  /// 私訊的來源（[BE-14]）。空值代表不同步。
  final ChatSource Function(String uid)? chatsFor;

  /// 團隊的來源（[BE-14]）。空值代表不同步。
  final TeamSource Function(String uid)? teamsFor;

  /// 師徒的來源（[BE-14]）。空值代表不同步。
  final MentorSource Function(String uid)? mentorFor;

  /// 檢舉的來源。空值代表不送上雲（既有測試走這條）。
  /// **只有寫、沒有讀** —— 檢舉佇列是管理端的東西。
  final ReportSource Function(String uid)? reportsFor;
  final InstructorCaseSource Function(String uid)? instructorCasesFor;

  /// 累計違規次數。與 uid 無關（一份服務讀所有人的），但與其他來源
  /// 同一個形狀，保持呼叫端一致。
  final ViolationSource Function()? violationsFor;
  final PunishmentSource Function()? punishmentsFor;
  final AppealSource Function()? appealsFor;

  const AuthGate({
    super.key,
    required this.auth,
    required this.state,
    required this.storeFor,
    this.deviceStore,
    this.platformData,
    this.profileFor,
    this.aiSource,
    this.qualitySource,
    this.followsFor,
    this.postsFor,
    this.photosFor,
    this.ratingsFor,
    this.chatsFor,
    this.teamsFor,
    this.mentorFor,
    this.reportsFor,
    this.instructorCasesFor,
    this.violationsFor,
    this.punishmentsFor,
    this.appealsFor,
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
    widget.state.qualitySource = widget.qualitySource;

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
      // **冷靜期到了就真的刪。** 這是整個刪除流程唯一真的動手的地方 ——
      // 在此之前 `requestDeletion()` 只設了一個欄位，冷靜期過了沒有
      // 任何東西會發生，資料一直都在。畫面上是承諾了的。
      widget.state
          .hydrate(widget.storeFor(user.uid))
          .then((_) => _executeDeletionIfDue(user.uid));
    }
    // **在這裡接，不要放進 `_syncProfile`。** 那個函式在
    // `profileFor == null` 時會提早返回，而「能不能刪自己的帳號」
    // 不該取決於公開檔案有沒有接上。
    if (user != null) {
      final uid = user.uid;
      widget.state.deleteAccountJob = () => _deleteEverything(uid);
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
      // **訂閱要跟著斷。** 它綁在建立它的那個 Source 上（帶著當時的
      // uid），Source 換掉了舊訂閱不會自己停 —— 不收的話下一個登入的
      // 人會被上一個帳號的變動叫醒。
      widget.state.stopCloudWatch();
    }
    if (mounted) {
      setState(() {
        _waiting = false;
        _user = user;
      });
    }
  }

  /// 冷靜期已過就執行刪除。
  ///
  /// ## 為什麼在登入時做，而不是排程
  ///
  /// 排程要 Cloud Functions，而那需要 Blaze 方案。登入時檢查的代價是
  /// **使用者不再登入就不會被刪** —— 對一個「申請刪除後就不打算再來」
  /// 的人來說，這是實質上的沒刪。這一點要誠實記著，等 `[BE-07]` 上
  /// Cloud Functions 之後改成排程掃描。
  ///
  /// ## 順序不能換
  ///
  /// 先刪 Firestore，最後才刪 Auth 帳號 —— 帳號一沒，安全規則就認不得
  /// 他是誰，剩下的資料誰也刪不掉，會永遠留在那裡。
  Future<void> _executeDeletionIfDue(String uid) async {
    final s = widget.state;
    if (!s.pendingDeletion) return;
    if ((s.deletionDaysLeft ?? 1) > 0) return;
    final err = await _deleteEverything(uid);
    if (err != null) debugPrint('冷靜期屆滿的自動刪除未完成：$err');
  }

  /// 刪掉這個帳號的一切。回傳 null 代表成功，否則是給使用者看的一句話。
  ///
  /// 兩個呼叫端：冷靜期屆滿時的自動刪除（[_executeDeletionIfDue]），
  /// 以及使用者在待刪除頁自己按「立即永久刪除」（經
  /// [AppState.deleteAccountJob]）。**兩條路要走同一份實作** ——
  /// 刪除是不可逆的，兩份實作意味著其中一份遲早會漏掉一步。
  Future<String?> _deleteEverything(String uid) async {
    try {
      // 公開檔案先刪：少了這一步，帳號都沒了，別人在「找人」裡還看得到他。
      await widget.profileFor?.call(uid).remove();
      await widget.storeFor(uid).clear();
    } catch (e) {
      // 資料沒刪掉就不刪帳號 —— 帳號一沒，安全規則就認不得他是誰，
      // 剩下的資料誰也刪不掉，會永遠留在那裡。
      return '雲端資料沒有刪成功，帳號保留未刪：$e';
    }

    final err = await widget.auth.deleteAccount();
    if (err == null) return null;

    // 資料已經刪了，帳號還在。登出讓下一次登入重試 —— 那時的工作階段
    // 是新的，`requires-recent-login` 就不會再擋。
    await widget.auth.signOut();
    return err == 'requires-recent-login'
        ? '資料已全部刪除。帳號本身需要剛登入過才能刪 —— 請再登入一次，'
            '系統會自動把它刪掉。'
        : '資料已全部刪除，但帳號沒刪掉（$err）。請再登入一次重試。';
  }

  Future<void> _loadPlatformData() async {
    if (_platformLoaded) return;
    final src = widget.platformData;
    if (src == null) return;
    // **狀態層也要拿得到。** 讀完就丟的話，管理員改了什麼寫不回去
    // —— 那正是 P123 的症狀（見 `AppState.platformSource`）。
    widget.state.platformSource = src;
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
    widget.state.photoSource = widget.photosFor?.call(uid);
    widget.state.chatSource = widget.chatsFor?.call(uid);
    widget.state.teamSource = widget.teamsFor?.call(uid);
    widget.state.mentorSource = widget.mentorFor?.call(uid);
    widget.state.reportSource = widget.reportsFor?.call(uid);
    widget.state.instructorCaseSource =
        widget.instructorCasesFor?.call(uid);
    widget.state.violationSource = widget.violationsFor?.call();
    widget.state.punishmentSource = widget.punishmentsFor?.call();
    widget.state.appealSource = widget.appealsFor?.call();
    widget.state.followSource = widget.followsFor?.call(uid);
    widget.state.ratingSource = widget.ratingsFor?.call(uid);

    // **公開檔案的來源也要交給狀態層。** 在此之前只有這個畫面握著它，
    // 於是「把我的公開檔案寫上去」只在這裡發生得了 —— 這個 session 內
    // 升的階，別人要等我下次登入才看得到。交出去之後 `AppState` 才能
    // 在升階當下重寫，也才能按 uid 隨用隨取補齊沒撈到的人。
    final src = make(uid);
    widget.state.profileSource = src;

    // 先寫再讀：讓自己在別人的清單裡也看得到，
    // 順序顛倒的話新使用者第一次登入不會出現在任何人的清單上。
    //
    // **這一塊要先完成**：其餘每一塊都靠 `nameByUid` 把 uid 翻回暱稱。
    await step('公開檔案', () async {
      await src.publish(widget.state.myPublicProfile(uid));
      final others = await src.others(limit: kProfileFetchLimit);
      widget.state.applyPublicProfiles(others);
      return '已發布自己，讀到 ${others.length} 位其他使用者';
    });

    final posts = widget.state.postSource;
    if (posts != null) {
      await step('貼文', () async {
        final got = await posts.recent(limit: AppState.kPostFeedLimit);
        widget.state.applyCloudPosts(got);
        // **不 await 補細節。** 留言與讚是一篇各一趟，30 篇就是 60 趟；
        // 等它們回來才往下跑，後面的私訊、團隊、師徒全都排在後面。
        // 貼文本體已經在畫面上了，留言晚幾百毫秒到就好。
        widget.state.fillPostDetails(got);
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
        // **教官側的任務與問答也要讀回來**（`[BE-15]`）——
        // 不讀的話學徒的提問教官永遠看不到，學徒給的評分也回不來，
        // 於是拜師頁上那個星等永遠是 0。要排在 `applyCloudBonds`
        // 之後：學徒清單是它建出來的。
        await widget.state.loadMentorSide();
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

    final ratings = widget.state.ratingSource;
    if (ratings != null) {
      await step('訓練體驗評分', () async {
        final mine = await ratings.mine();
        widget.state.applyCloudRatings(mine);
        return '${mine.length} 筆';
      });
    }

    // 管理員身分。**與 `firestore.rules` 的 `isAdmin()` 同源** ——
    // 兩邊各自判斷的話會出現「後台進得去、每個寫入都被規則擋下」。
    //
    // 自成一塊：讀不到 claim 不該讓前面那幾塊的結果被丟掉，
    // 而「不是管理員」本來就是絕大多數人的答案。
    await step('管理員身分', () async {
      final claims = await widget.auth.claims();
      final isAdmin = claims['admin'] == true;
      final scopes = claims['adminScopes'];
      widget.state.applyAdminClaim(
        isAdmin,
        scopes: scopes is List ? [for (final s in scopes) '$s'] : null,
      );
      return isAdmin
          ? '是管理員（${widget.state.admin.scopes.length} 組權限）'
          : '一般使用者';
    });

    // 自己的累計違規次數。**不在存檔裡，也不該在** —— 存檔是本人寫得動的，
    // 而處罰級距靠這個數字決定。
    if (widget.state.violationSource != null) {
      await step('違規次數', () async {
        await widget.state.loadMyViolations();
        return '${widget.state.myViolations} 次';
      });
    }

    // 處罰狀態。**同樣不在存檔裡** —— 存檔是本人寫得動的，
    // 被罰的人自己就能解除。
    if (widget.state.punishmentSource != null) {
      await step('處罰狀態', () async {
        await widget.state.loadMyPunishment();
        final p = widget.state.punishment;
        return p == null ? '無' : punishmentKindNames[p.kind]!;
      });
    }

    // 檢舉佇列。**只有管理員讀得動** —— 一般帳號連查都會被規則拒絕，
    // 所以這一塊自己判斷、自己成敗，不要讓它的失敗影響別人。
    if (widget.state.isPlatformAdmin) {
      await step('檢舉佇列', () async {
        await widget.state.loadReportQueue();
        return '${widget.state.reports.length} 案'
            '（待審 ${widget.state.reports.where((c) => c.state == CaseState.pending).length}）';
      });
      // 另外一塊 —— 檢舉讀不到不該連申訴也看不到。
      await step('申訴佇列', () async {
        await widget.state.loadAppealQueue();
        return '${widget.state.appeals.length} 案';
      });
      // 教官申請（`[BE-20]`）。同樣自己成敗 —— 在此之前這一整個佇列
      // 在正式環境對每一個人都是空的（見 PROGRESS 第 5 節 2I）。
      await step('教官申請', () async {
        await widget.state.loadInstructorQueue();
        return '${widget.state.instructorCases.length} 案';
      });
    }

    // **排在最後，不是隨便排的。**
    //
    // 團隊那條要監看「別人申請加入我的隊」，而那批請求掛在隊伍底下 ——
    // 要先知道我在哪一隊才訂得到。上面「我的團隊」那一塊剛把它讀回來。
    //
    // 也因為一掛上就會先收到一份現況快照（`mergeWatches` 會丟掉），
    // 排在同步之後才不會跟同步本身搶著寫同一批資料。
    widget.state.startCloudWatch();
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
    // **條款改版後要重新同意** —— 與 `FirstRunGate` 共用同一道閘門。
    //
    // 這裡原本直接回 `HomeShell`。`main.dart` 有兩個入口：沒接 Firebase
    // 走 `FirstRunGate`，接了走這裡 —— 2026-09-24 加條款閘門時只改了前者，
    // 於是真正在線上跑的那條路徑完全沒有那道閘門。
    //
    // 同一個判斷寫在兩處、只有一處做對，正是這一批 bug 的共同形狀。
    return const TermsGate();
  }
}
