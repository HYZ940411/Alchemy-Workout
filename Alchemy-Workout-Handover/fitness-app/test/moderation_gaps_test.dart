// 內容過濾的四個缺口（2026-10-20 對照規格檢查時發現）：
//
//  ① 留言的疑似違規沒有開案 —— 規格說貼文／留言／私訊三類共用，
//     留言只擋了明顯違規。
//  ② 編輯貼文與留言不重新過濾 —— 先發正常內容再改成違規字詞，整道過濾就繞過了。
//  ③ 分享訓練成果的疑似違規只標了 pendingReview、沒有開案，永遠沒人審。
//  ④ 被攔截後的「申訴」按鈕按了沒反應；資料模型有「內容攔截」這種申訴，
//     卻沒有任何程式能建立它。而且 `upholdAppeal` 不分對象一律撤銷處罰、
//     退違規次數 —— 內容攔截的申訴成立，會把申訴人別的處罰一併撤掉。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/appeal_data.dart';
import 'package:fitness_app/data/punishment_data.dart';
import 'package:fitness_app/data/violation_data.dart';
import 'package:fitness_app/domain/admin.dart';
import 'package:fitness_app/domain/commerce.dart';
import 'package:fitness_app/domain/clock.dart';
import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/domain/rewards.dart';
import 'package:fitness_app/domain/social.dart';
import 'package:fitness_app/screens/social/blocked_dialog.dart';
import 'package:fitness_app/state/app_state.dart';

class _Appeals implements AppealSource {
  final List<CloudAppeal> filed = [];
  final List<(String, bool)> verdicts = [];
  List<ApprovedBlock> approved = [];
  int approvedReads = 0;

  @override
  Future<void> file(CloudAppeal a) async => filed.add(a);
  @override
  Future<List<CloudAppeal>> queue({int limit = 100}) async => const [];
  @override
  Future<void> judge(
    String id, {
    required bool upheld,
    required String handlerName,
  }) async => verdicts.add((id, upheld));
  @override
  Future<List<ApprovedBlock>> approvedBlockedTexts(String uid) async {
    approvedReads++;
    return approved;
  }
}

class _Punishments implements PunishmentSource {
  final List<String> revoked = [];
  @override
  Future<void> revoke(String uid) async => revoked.add(uid);
  @override
  Future<Punishment?> of(String uid) async => null;
  @override
  Future<void> issue(String uid, Punishment p, {required String name}) async {}
  @override
  Future<void> markAppealed(String uid, AppealState state) async {}
}

class _Violations implements ViolationSource {
  final List<String> decremented = [];
  @override
  Future<int> decrement(String uid) async {
    decremented.add(uid);
    return 0;
  }

  @override
  Future<int> countOf(String uid) async => 0;
  @override
  Future<int> increment(String uid, {required String name}) async => 1;
}

AppState _user() => AppState(demo: false)
  ..myUid = 'u-me'
  ..displayName = '阿健';

Iterable<ReportCase> _autoFlagged(AppState s) =>
    s.reports.where((c) => c.origin == CaseOrigin.autoFlag);

void main() {
  group('① 留言的疑似違規要開案', () {
    test('疑似違規的留言照常留下，並自動開立檢舉案', () {
      final s = _user();
      s.publishPost('今天練腿', PostVisibility.public);
      final post = s.posts.first;

      s.addComment(post, '聽說類固醇很有效');

      expect(post.comments, hasLength(1), reason: '疑似違規照常發布');
      final c = _autoFlagged(s).single;
      expect(c.target, ReportTarget.comment);
      expect(
        c.targetKey,
        reportKey(ReportTarget.comment, post.comments.single.id),
      );
      expect(c.content, '聽說類固醇很有效');
      expect(c.reporterCount, 0, reason: '系統自動標記的案件沒有檢舉者');
    });

    test('正常留言不開案', () {
      final s = _user();
      s.publishPost('今天練腿', PostVisibility.public);
      s.addComment(s.posts.first, '加油');
      expect(_autoFlagged(s), isEmpty);
    });

    test('明顯違規的留言不寫入，並記下這次攔截', () {
      final s = _user();
      s.publishPost('今天練腿', PostVisibility.public);
      final post = s.posts.first;

      final exp = s.addComment(post, '加賴買藥');

      expect(exp, 0);
      expect(post.comments, isEmpty, reason: '狀態層自己也要擋，不能只靠畫面');
      expect(s.lastBlocked?.kind, BlockedKind.comment);
      expect(s.lastBlocked?.text, '加賴買藥');
    });
  });

  group('② 編輯也要過濾', () {
    test('貼文改成明顯違規 → 拒絕，原文保留', () {
      final s = _user();
      s.publishPost('今天練腿', PostVisibility.public);
      final p = s.posts.first;

      final ok = s.editPost(p, '加賴買藥');

      expect(ok, isFalse);
      expect(p.text, '今天練腿');
      expect(p.edits, isEmpty);
    });

    test('貼文改成疑似違規 → 存下，並自動開案', () {
      final s = _user();
      s.publishPost('今天練腿', PostVisibility.public);
      final p = s.posts.first;

      final ok = s.editPost(p, '今天練腿，順便聊聊類固醇');

      expect(ok, isTrue);
      final c = _autoFlagged(s).single;
      expect(c.targetKey, reportKey(ReportTarget.post, p.id));
      expect(c.content, '今天練腿，順便聊聊類固醇', reason: '案件要記編輯後的內容');
    });

    test('貼文正常編輯不開案', () {
      final s = _user();
      s.publishPost('今天練腿', PostVisibility.public);
      expect(s.editPost(s.posts.first, '今天練背'), isTrue);
      expect(_autoFlagged(s), isEmpty);
    });

    test('留言改成明顯違規 → 拒絕，原文保留', () {
      final s = _user();
      s.publishPost('今天練腿', PostVisibility.public);
      s.addComment(s.posts.first, '加油');
      final c = s.posts.first.comments.single;

      expect(s.editComment(c, '詐騙'), isFalse);
      expect(c.text, '加油');
    });

    test('留言改成疑似違規 → 存下，並自動開案', () {
      final s = _user();
      s.publishPost('今天練腿', PostVisibility.public);
      s.addComment(s.posts.first, '加油');
      final c = s.posts.first.comments.single;

      expect(s.editComment(c, '加油，禁藥不要碰'), isTrue);
      expect(
        _autoFlagged(s).single.targetKey,
        reportKey(ReportTarget.comment, c.id),
      );
    });
  });

  group('③ 分享訓練成果的疑似違規要開案', () {
    test('疑似違規的分享：貼文標待審，且有案件', () {
      final s = AppState()..resetToNewAccount();
      s.startWorkout(s.platformPlans.firstWhere((p) => p.id == 'p_push'));
      s.completeCurrentSet();
      final r = s.finishWorkout(EndKind.completed);

      final shared = s.shareWorkout(r, '今天順便聊聊類固醇');

      expect(shared, isNotNull);
      expect(shared!.post.pendingReview, isTrue);
      // 只標 pendingReview 不開案，那則分享永遠不會有人審。
      expect(
        _autoFlagged(s).where(
          (c) => c.targetKey == reportKey(ReportTarget.post, shared.post.id),
        ),
        hasLength(1),
      );
    });
  });

  group('④ 被攔截後的申訴', () {
    test('發文被攔下 → 記下原文；申訴帶著原文上雲', () {
      final s = _user();
      final src = _Appeals();
      s.appealSource = src;

      s.publishPost('  加賴買藥  ', PostVisibility.public);
      final sent = s.fileBlockedAppeal('我是在勸大家不要');

      expect(sent, isTrue);
      final f = src.filed.single;
      expect(f.target, AppealTarget.blockedContent);
      expect(f.content, '加賴買藥', reason: '管理員要看得到當時攔的是什麼');
      expect(f.subject, '貼文遭自動攔截');
      expect(f.reason, '我是在勸大家不要');
      expect(f.appellantUid, 'u-me');
      expect(s.appeals.single.content, '加賴買藥');
    });

    test('同一次攔截只能申訴一次', () {
      final s = _user();
      final src = _Appeals();
      s.appealSource = src;
      s.publishPost('加賴買藥', PostVisibility.public);

      expect(s.fileBlockedAppeal('第一次'), isTrue);
      expect(s.fileBlockedAppeal('第二次'), isFalse);
      expect(src.filed, hasLength(1));
    });

    test('攔截滿 30 天就不能申訴；差一天還可以', () {
      addTearDown(resetAppClock);
      final s = _user();
      final src = _Appeals();
      s.appealSource = src;

      s.publishPost('加賴買藥', PostVisibility.public);
      appClockOffset = const Duration(days: 29, hours: 23);
      expect(s.fileBlockedAppeal('還來得及'), isTrue);

      s.publishPost('詐騙集團', PostVisibility.public);
      appClockOffset =
          const Duration(days: 30, hours: 1) +
          const Duration(days: 29, hours: 23);
      expect(s.fileBlockedAppeal('太晚了'), isFalse);
      expect(src.filed, hasLength(1));
    });

    test('沒有被攔過就不能申訴', () {
      final s = _user();
      s.appealSource = _Appeals();
      expect(s.fileBlockedAppeal('我要申訴'), isFalse);
    });

    test('重送被攔的內容 → 換成新的一次攔截，各有一次申訴機會', () {
      final s = _user();
      final src = _Appeals();
      s.appealSource = src;

      s.publishPost('加賴買藥', PostVisibility.public);
      s.fileBlockedAppeal('第一則');
      s.publishPost('詐騙集團', PostVisibility.public);
      final sent = s.fileBlockedAppeal('第二則');

      expect(sent, isTrue);
      expect(src.filed.map((a) => a.content), ['加賴買藥', '詐騙集團']);
    });

    test('社群功能停權造成的拒絕不算內容攔截', () {
      final s = _user();
      s.punishment = Punishment(
        kind: PunishmentKind.permanent,
        reason: '',
        evidence: '',
        issuedAt: s.now,
        violationCount: 5,
        nextConsequence: '',
      );
      s.publishPost('今天練腿', PostVisibility.public);
      expect(s.lastBlocked, isNull);
    });

    test('私訊被攔下也記得住', () {
      final s = AppState();
      final c = s.conversations.first;
      s.sendMessage(c, '加賴買藥');
      expect(s.lastBlocked?.kind, BlockedKind.message);
    });
  });

  group('④ 內容攔截的申訴裁決', () {
    ({AppState admin, _Appeals appeals, _Punishments pun, _Violations vio})
    wired() {
      final appeals = _Appeals();
      final pun = _Punishments();
      final vio = _Violations();
      final s = AppState(demo: false)
        ..myUid = 'u-admin'
        ..displayName = '阿管'
        ..appealSource = appeals
        ..punishmentSource = pun
        ..violationSource = vio;
      s.applyAdminClaim(true);
      return (admin: s, appeals: appeals, pun: pun, vio: vio);
    }

    AppealCase blockedAppeal(AppState s, {String who = '阿昶'}) {
      final c = AppealCase(
        id: 'u-阿昶__blocked__1',
        appellant: who,
        appellantUid: 'u-阿昶',
        target: AppealTarget.blockedContent,
        subject: '貼文遭自動攔截',
        reason: '我是在勸阻',
        filedAt: s.now,
        daysSinceIncident: 0,
        content: '不要用類固醇，加賴問我',
      );
      s.appeals.add(c);
      s.reviewAppeal(c);
      return c;
    }

    test('成立 → 不撤銷處罰、不退違規次數', () {
      final w = wired();
      final c = blockedAppeal(w.admin);

      w.admin.upholdAppeal(c);

      // 在此之前 upholdAppeal 不分對象一律撤處罰、退點 ——
      // 內容攔截的申訴成立，會把申訴人別的處罰一併撤掉。
      expect(w.pun.revoked, isEmpty);
      expect(w.vio.decremented, isEmpty);
      expect(w.appeals.verdicts, [('u-阿昶__blocked__1', true)]);
      expect(c.state, CaseState.upheld);
    });

    test('駁回 → 裁決寫回，也不動處罰', () {
      final w = wired();
      final c = blockedAppeal(w.admin);

      w.admin.dismissAppeal(c);

      expect(w.pun.revoked, isEmpty);
      expect(w.appeals.verdicts, [('u-阿昶__blocked__1', false)]);
      expect(c.state, CaseState.dismissed);
    });

    test('申訴人就在這台裝置上：成立後原文放行', () {
      final w = wired();
      expect(w.admin.screenContent('不要用類固醇，加賴問我'), FilterVerdict.blocked);
      final c = blockedAppeal(w.admin, who: '阿管');

      w.admin.upholdAppeal(c);

      expect(w.admin.screenContent('不要用類固醇，加賴問我'), FilterVerdict.pass);
      // 只放行原文，不是放行整個字詞。
      expect(w.admin.screenContent('加賴買藥'), FilterVerdict.blocked);
    });

    test('駁回 → 原文仍然被攔', () {
      final w = wired();
      final c = blockedAppeal(w.admin, who: '阿管');
      w.admin.dismissAppeal(c);
      expect(w.admin.screenContent('不要用類固醇，加賴問我'), FilterVerdict.blocked);
    });

    test('申訴人在別的裝置：登入時把已放行的原文讀回來', () async {
      final s = _user();
      final src = _Appeals()
        ..approved = [const ApprovedBlock('a1', '不要用類固醇，加賴問我')];
      s.appealSource = src;
      expect(s.screenContent('不要用類固醇，加賴問我'), FilterVerdict.blocked);

      await s.loadMyApprovedTexts();

      expect(s.screenContent('不要用類固醇，加賴問我'), FilterVerdict.pass);
      expect(
        s.publishPost('不要用類固醇，加賴問我', PostVisibility.public),
        FilterVerdict.pass,
      );
      expect(s.posts.first.text, '不要用類固醇，加賴問我');
    });

    test('申訴成立 → 申訴人收到一則 App 內通知', () async {
      final s = _user();
      s.appealSource = _Appeals()
        ..approved = [const ApprovedBlock('u-me__blocked__1', '不要用類固醇，加賴問我')];
      final before = s.notifications.length;

      await s.loadMyApprovedTexts();

      expect(s.notifications.length, before + 1);
      final n = s.notifications.first;
      expect(n.kind, NotifyKind.inApp);
      expect(n.title, '你的申訴成立了');
      expect(n.body, contains('不要用類固醇，加賴問我'));
      expect(n.read, isFalse, reason: '要有紅點，使用者才注意得到');
    });

    test('同一筆成立只通知一次，重新讀取、重新登入都不再發', () async {
      final s = _user();
      s.appealSource = _Appeals()
        ..approved = [const ApprovedBlock('u-me__blocked__1', '不要用類固醇，加賴問我')];
      await s.loadMyApprovedTexts();
      await s.loadMyApprovedTexts();
      expect(
        s.notifications.where((n) => n.id == 'n-appeal-u-me__blocked__1'),
        hasLength(1),
      );

      // 通知會進存檔：換一個新的 AppState 讀回存檔，仍不再發。
      final reloaded = _user()..appealSource = s.appealSource;
      expect(reloaded.applySnapshot(s.toSnapshot()), isTrue);
      await reloaded.loadMyApprovedTexts();
      expect(
        reloaded.notifications.where(
          (n) => n.id == 'n-appeal-u-me__blocked__1',
        ),
        hasLength(1),
      );
    });

    test('沒有成立的申訴就沒有通知', () async {
      final s = _user();
      s.appealSource = _Appeals();
      final before = s.notifications.length;
      await s.loadMyApprovedTexts();
      expect(s.notifications.length, before);
    });

    test('順帶重讀最多每 5 分鐘一次，不然每個即時訊號都多一筆查詢', () async {
      addTearDown(resetAppClock);
      final s = _user();
      final src = _Appeals();
      s.appealSource = src;

      await s.refreshInbound();
      await s.refreshInbound();
      expect(src.approvedReads, 1);

      appClockOffset = const Duration(minutes: 6);
      await s.refreshInbound();
      expect(src.approvedReads, 2);
    });

    test('登出（endSession）後放行清單與最近攔截一併清掉', () async {
      final s = _user();
      final src = _Appeals()..approved = [const ApprovedBlock('a2', '某段原文詐騙')];
      s.appealSource = src;
      await s.loadMyApprovedTexts();
      s.publishPost('賣藥', PostVisibility.public);

      s.endSession();

      expect(s.lastBlocked, isNull);
      expect(s.screenContent('某段原文詐騙'), FilterVerdict.blocked);
    });
  });

  blockedDialogTests();
}

// 攔截彈窗的「申訴」按鈕（畫面層）。
//
// 2026-10-20 使用者實測：按「申訴」沒反應。原因是線上跑的是舊建置 ——
// 舊版那顆按鈕的回傳值被丟掉。這條把畫面層釘住：按下去要真的走到
// 理由輸入框、送出後要真的送到雲端，而不只是狀態層對。
void blockedDialogTests() {
  group('④ 攔截彈窗的申訴按鈕（畫面）', () {
    Future<void> open(WidgetTester tester, AppState s) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (c) => TextButton(
                onPressed: () =>
                    showBlockedDialog(c, s, kind: BlockedKind.post),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
    }

    testWidgets('按「申訴」→ 理由輸入框 → 送出 → 申訴上雲', (tester) async {
      final s = _user();
      final src = _Appeals();
      s.appealSource = src;
      s.publishPost('加賴買藥', PostVisibility.public);

      await open(tester, s);
      expect(find.text('內容已攔截'), findsOneWidget);

      await tester.tap(find.text('申訴'));
      await tester.pumpAndSettle();
      expect(
        find.text('申訴這次攔截'),
        findsOneWidget,
        reason: '按「申訴」要接到理由輸入框，不能什麼都不發生',
      );

      await tester.enterText(find.byType(TextField), '我是在勸大家不要');
      await tester.tap(find.text('送出申訴'));
      await tester.pumpAndSettle();

      expect(src.filed, hasLength(1));
      expect(src.filed.single.reason, '我是在勸大家不要');
      expect(src.filed.single.content, '加賴買藥');
    });

    testWidgets('按「我知道了」→ 不申訴', (tester) async {
      final s = _user();
      final src = _Appeals();
      s.appealSource = src;
      s.publishPost('加賴買藥', PostVisibility.public);

      await open(tester, s);
      await tester.tap(find.text('我知道了'));
      await tester.pumpAndSettle();

      expect(find.text('申訴這次攔截'), findsNothing);
      expect(src.filed, isEmpty);
    });
  });
}
