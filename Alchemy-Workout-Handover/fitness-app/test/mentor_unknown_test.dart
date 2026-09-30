// 「我沒有教官」與「還不知道」要分得開（2026-09-24）。
//
// ## 這條是從一個搞錯的隱患挖出來的
//
// `PROGRESS.md` 第 5 節 0h 原本寫著「既有的師徒關係不會被補寫到雲端…
// 那些關係在雲端不存在，換裝置或重新登入就消失」，並打算寫一支回填。
//
// 查證之後那句話是錯的：`myInstructor` 與 `apprentices`
// **根本不在存檔裡**（`app_state_snapshot.dart` 對這兩個欄位零筆引用）。
// 所以 2026-09-24 之前建立的關係不只雲端沒有，本機也沒有 ——
// 它只活在那個分頁的記憶體裡，重新整理就沒了。**沒有東西可以回填。**
//
// 真正該修的是這件事在畫面上的樣子：`myInstructor == null` 有兩個意思，
// 而拜師頁把兩者畫成同一張清單 —— 也就是在同步失敗時，對著一位有教官
// 的人說「你沒有教官」。
//
// 而它不會報錯。師徒那一塊是各自 `try`、吞掉錯誤的（那是對的，社群
// 讀不到不該擋住訓練），代價正是出問題時完全沒有跡象。
//
// 守則第 5 條：**填錯的數字比留白更糟 —— 留白會被看見，錯的不會。**

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/mentor_data.dart';
import 'package:fitness_app/data/store.dart';
import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/screens/social/mentor_screen.dart';
import 'package:fitness_app/state/app_state.dart';

class _Src implements MentorSource {

  /// 恢復提議。只記下來，需要的測試自己讀。
  final List<(String bond, String? by)> restoreCalls = [];

  @override
  Future<void> proposeRestore(String bondId, String byUid) async =>
      restoreCalls.add((bondId, byUid));

  @override
  Future<void> dropRestore(String bondId) async =>
      restoreCalls.add((bondId, null));


  /// 週互動評分。這支測試不碰它 —— 記下來就好。
  final List<(String bond, String week, int stars)> weekRatings = [];

  @override
  Future<void> rateWeek(String bondId, String week, int stars) async =>
      weekRatings.add((bondId, week, stars));

  @override
  Future<List<CloudBond>> bonds() async => const [];
  @override
  Stream<void> watchMentor() => const Stream.empty();
  @override
  Future<void> bond(CloudBond b) async {}
  @override
  Future<void> release(
      String bondId, MentorReleaseReason reason, DateTime at) async {}
  @override
  Future<void> recover(String bondId, DateTime now) async {}
  @override
  Future<List<CloudMentorTask>> tasks(String bondId) async => const [];
  @override
  Future<void> putTask(String bondId, CloudMentorTask t) async {}
  @override
  Future<List<CloudQuestion>> questions(String bondId) async => const [];
  @override
  Future<void> ask(String bondId, CloudQuestion q) async {}
  @override
  Future<void> answer(
      String bondId, String questionId, String text, DateTime at) async {}
  @override
  Future<List<MentorRequest>> requestsFor(String uid) async => const [];

  /// 我自己送出去的申請。預設沒有 —— 需要的測試自己覆寫。
  @override
  Future<List<MentorRequest>> sentRequests() async => sent;
  List<MentorRequest> sent = const [];
  @override
  Future<void> sendRequest(MentorRequest r) async {}
  @override
  Future<void> dropRequest(String requestId) async {}
}

void main() {
  group('mentorKnown', () {
    test('接了雲端、還沒讀到 → 不知道', () {
      final s = AppState(demo: false)
        ..myUid = 'u-me'
        ..mentorSource = _Src();
      expect(s.mentorKnown, isFalse);
    });

    test('讀回來之後 → 知道，即使雲端是空的', () {
      final s = AppState(demo: false)
        ..myUid = 'u-me'
        ..mentorSource = _Src();

      s.applyCloudBonds(const []);

      // 「雲端確實沒有關係」是一個答案，與「還沒問到」不同。
      expect(s.mentorKnown, isTrue);
      expect(s.myInstructor, isNull);
    });

    test('沒接雲端 → 本機就是全部事實，直接算知道', () {
      // 示範身分與既有測試走這條。
      expect(AppState(demo: false).mentorKnown, isTrue);
      expect(AppState().mentorKnown, isTrue);
    });

    test('換了來源就重新算不知道 —— 上一個帳號讀過的不算數', () {
      final s = AppState(demo: false)
        ..myUid = 'u-me'
        ..mentorSource = _Src();
      s.applyCloudBonds(const []);
      expect(s.mentorKnown, isTrue);

      s.mentorSource = _Src(); // 換帳號
      expect(s.mentorKnown, isFalse);
    });
  });

  group('師徒關係刻意不進存檔', () {
    test('存讀一輪之後我的教官不會留著 —— 雲端才是唯一事實', () async {
      final store = MemoryStore();
      await store.save(AppState().toSnapshot());
      final s = AppState()..myUid = 'u-me';
      await s.hydrate(store);
      s.myInstructor = Instructor(
        name: '老王', uid: 'u-師父', rank: 30, reputation: 100,
        apprentices: 1, apprenticeCap: 3,
        ability: const {}, specialties: const [],
        avgRating: 0, ratingCount: 0,
      );
      await s.saveNow();

      final next = AppState();
      await next.hydrate(store);

      // **這是刻意的，不是漏掉的。** 存一份本機副本就是把同一個事實
      // 寫在兩個地方，而這個專案的 bug 有一整排正是那樣來的
      // （守則第 3 條：衍生值優於儲存欄位）。
      //
      // 代價是讀不到時畫面上什麼都沒有 —— 所以才要 `mentorKnown`
      // 把「沒有」與「不知道」分開，讓那個代價**被看見**。
      //
      // 這條測試同時也是 `PROGRESS.md` 0h 的結論：2026-09-24 之前的
      // 關係不只雲端沒有、本機也沒有，**沒有東西可以回填**。
      expect(next.myInstructor, isNull);
    });
  });

  group('拜師頁的三種狀態', () {
    Future<void> pump(WidgetTester t, AppState s) async {
      t.view.physicalSize = const Size(393 * 3, 852 * 3);
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      // `MentorScreen` 自己沒有 Scaffold（它是社群頁的一個分頁），
      // 而「我的教官」那一側有輸入框 —— 沒有 Material 祖先會直接拋。
      await t.pumpWidget(AppScope(
        state: s,
        child: const MaterialApp(home: Scaffold(body: MentorScreen())),
      ));
      await t.pumpAndSettle();
    }

    // **要先解鎖師徒功能**：真帳號一開機五件互動都是 0，拜師頁畫的是
    // 解鎖清單而不是這三種狀態。在此之前不用寫這一行 —— 那是因為
    // `following` 漏了 `demo` 旗標，白送了一個「關注」進度（見
    // `AppState.followTotal`）。
    AppState unread() => AppState(demo: false)
      ..myUid = 'u-me'
      ..markMentorUnlocked()
      ..mentorSource = _Src();

    testWidgets('還沒讀到 → 不說「你沒有教官」', (t) async {
      await pump(t, unread());

      // 在此之前這裡畫的是拜師清單 —— 一個有教官的人會看到
      // 「挑一位教官」，而他已經有了。
      expect(find.text('師徒資料還沒讀到'), findsOneWidget);
      expect(find.textContaining('這不代表你沒有教官'), findsOneWidget);
    });

    testWidgets('還沒讀到 → 給得出重試', (t) async {
      await pump(t, unread());
      expect(find.text('重新讀取'), findsOneWidget);
    });

    testWidgets('讀到了、確實沒有教官 → 畫拜師清單', (t) async {
      final s = unread()..applyCloudBonds(const []);
      await pump(t, s);

      expect(find.text('師徒資料還沒讀到'), findsNothing);
    });

    testWidgets('有教官 → 畫我的教官，不管讀沒讀到', (t) async {
      final s = unread();
      s.applyCloudBonds([
        CloudBond(
          id: 'u-師父_u-me',
          mentorUid: 'u-師父',
          apprenticeUid: 'u-me',
          mentorName: '老王',
          apprenticeName: '我',
          state: MentorBondState.active,
          bondedAt: DateTime(2026, 9, 24),
        ),
      ]);
      await pump(t, s);

      expect(find.textContaining('老王'), findsWidgets);
      expect(find.text('師徒資料還沒讀到'), findsNothing);
    });
  });
}
