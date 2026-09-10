// 切換條件，畫面就該跟著變。
//
// 六維的時間維度壞掉時，「現在／30 天前／90 天前」三張圖一模一樣，
// 而且不報錯 —— 查不到資料就默默退回現在的值。這一類 bug 測不到例外，
// 只能靠「切了 A 跟切了 B 必須不同」把它釘住。
//
// 這支把同型的切換器都掃一遍。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/ability.dart';
import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/main.dart';
import 'package:fitness_app/state/app_state.dart';

/// 真的在畫面**可視範圍內**的文字。
///
/// 不能用 `find.byType(Text)` 全抓：TabBarView 的兩個分頁都在樹上，
/// 沒被選中的那一頁只是被移到畫面外，全抓的話兩邊量出來永遠一樣，
/// 於是測試永遠「通過」也永遠測不到東西。
String visibleText(WidgetTester t) {
  final screen = t.view.physicalSize / t.view.devicePixelRatio;
  final out = <String>[];
  for (final e in find.byType(Text).evaluate()) {
    final w = e.widget as Text;
    final d = w.data;
    if (d == null || d.trim().isEmpty) continue;
    final box = e.renderObject;
    if (box is! RenderBox || !box.hasSize) continue;
    final r = box.localToGlobal(Offset.zero) & box.size;
    if (r.right <= 0 ||
        r.bottom <= 0 ||
        r.left >= screen.width ||
        r.top >= screen.height) {
      continue;
    }
    out.add(d);
  }
  return out.join('|');
}


Future<void> boot(WidgetTester t) async {
  t.view.physicalSize = const Size(393 * 3, 852 * 3);
  t.view.devicePixelRatio = 3.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(const FitnessApp());
  await t.pumpAndSettle();
}

void main() {
  group('六維：時間維度', () {
    List<int> pts(AppState s) =>
        [for (final d in Dim.values) s.displayedPoints[d]!];

    test('每個檔位指向不同的快照，鍵漂掉之後也一樣', () {
      for (final days in [0, 1, 17, 40]) {
        final s = AppState();
        if (days > 0) s.advanceDemoClock(Duration(days: days));
        expect(s.snapshotOptions.toSet(), hasLength(s.snapshotOptions.length),
            reason: '快轉 $days 天後有重複的檔位');
        expect(s.snapshotOptions.length, greaterThan(1),
            reason: '快轉 $days 天後只剩一個檔位');
        for (final opt in s.snapshotOptions) {
          s.setSnapshot(opt);
          expect(s.snapshotDaysAgo, opt,
              reason: '快轉 $days 天後，切到 $opt 卻落在 \${s.snapshotDaysAgo}');
        }
      }
    });

    test('假資料的三個檔位數值互不相同', () {
      // 值相同不必然是 bug ——那段期間真的沒訓練就會一樣。
      // 但假資料本來就給了三組不同的數字，全部相等就是查不到資料退回現在。
      for (final days in [0, 1]) {
        final s = AppState();
        if (days > 0) s.advanceDemoClock(Duration(days: days));
        final seen = <String>{};
        for (final opt in s.snapshotOptions) {
          s.setSnapshot(opt);
          expect(seen.add(pts(s).join(',')), isTrue,
              reason: '快轉 $days 天後，檔位 $opt 與前面某一個長得一樣');
        }
      }
    });
  });

  group('排行榜：週榜與月榜', () {
    test('兩個榜的資料不同', () {
      final s = AppState();
      final w = s.leaderboardWindow(weekly: true);
      final m = s.leaderboardWindow(weekly: false);
      expect(w.map((e) => '${e.name}:${e.score}').toList(),
          isNot(m.map((e) => '${e.name}:${e.score}').toList()),
          reason: '週榜與月榜是兩個獨立計數器，不該給出同一份榜單');
    });

    test('我的分數各自來自各自的計數器', () {
      final s = AppState();
      s.weeklyScore = 111;
      s.monthlyScore = 222;
      expect(s.leaderboardWindow(weekly: true).firstWhere((e) => e.isSelf).score,
          111);
      expect(
          s.leaderboardWindow(weekly: false).firstWhere((e) => e.isSelf).score,
          222);
    });
  });

  group('動態牆：關注與探索', () {
    List<Post> following(AppState s) => s.visiblePosts
        .where((p) =>
            p.author == s.displayName ||
            (s.following.contains(p.author) &&
                p.visibility != PostVisibility.private))
        .toList();

    List<Post> explore(AppState s) => s.visiblePosts
        .where((p) => p.visibility == PostVisibility.public)
        .toList();

    test('兩個分頁的貼文集合不同', () {
      final s = AppState();
      expect(following(s).map((p) => p.id).toList(),
          isNot(explore(s).map((p) => p.id).toList()),
          reason: '關注是「我追的人 ＋ 我自己」，探索是「全平台公開」，兩者不該一樣');
    });

    test('關注分頁看得到自己的私人貼文，探索看不到', () {
      final s = AppState();
      final mine = Post(
        id: 'mine-private',
        author: s.displayName,
        authorRank: s.rank,
        text: '只給自己看',
        at: s.now,
        visibility: PostVisibility.private,
      );
      s.posts.insert(0, mine);
      expect(following(s).any((p) => p.id == mine.id), isTrue);
      expect(explore(s).any((p) => p.id == mine.id), isFalse,
          reason: '私人貼文出現在探索分頁就是可見範圍沒生效');
    });

    test('未關注者的公開貼文只在探索出現', () {
      final s = AppState();
      final other = Post(
        id: 'stranger-public',
        author: '完全沒關注的人',
        authorRank: 10,
        text: '公開貼文',
        at: s.now,
      );
      s.posts.insert(0, other);
      expect(explore(s).any((p) => p.id == other.id), isTrue);
      expect(following(s).any((p) => p.id == other.id), isFalse);
    });
  });

  group('畫面上真的切得動', () {
    testWidgets('動態牆切到探索，看得見的貼文會變', (t) async {
      await boot(t);
      await t.tap(find.text('社群').last);
      await t.pumpAndSettle();

      // 放一則「沒關注的人」的公開貼文：只該出現在探索。
      final s = AppScope.of(t.element(find.byType(Scaffold).first));
      const mark = '這是陌生人的公開貼文';
      s.posts.insert(
        0,
        Post(
          id: 'stranger-visible',
          author: '完全沒關注的人',
          authorRank: 10,
          text: mark,
          at: s.now,
        ),
      );
      // 直接改集合不會觸發重繪 —— 少了這一行，貼文根本沒被畫出來，
      // 「關注分頁看不到它」就成了一句空話，兩個斷言都測不到東西。
      s.notifyListeners();
      await t.pumpAndSettle();

      expect(visibleText(t).contains(mark), isFalse,
          reason: '關注分頁不該看到沒關注的人的貼文');

      await t.tap(find.text('探索').last);
      await t.pumpAndSettle();
      // TabBarView 要切過去才會建那一頁，所以這個前提只能放在切換之後。
      expect(find.text(mark), findsOneWidget,
          reason: '前提：貼文要真的被畫出來，否則下面那個斷言是空的');
      expect(visibleText(t).contains(mark), isTrue,
          reason: '切到探索卻看不到全平台的公開貼文');
    });

    testWidgets('訓練歷史切到動作趨勢，內容會變', (t) async {
      await boot(t);
      await t.tap(find.text('我的').last);
      await t.pumpAndSettle();
      final entry = find.text('訓練歷史');
      if (entry.evaluate().isEmpty) return;
      await t.tap(entry.last);
      await t.pumpAndSettle();

      final before = visibleText(t);
      await t.tap(find.text('動作趨勢').last);
      await t.pumpAndSettle();
      expect(visibleText(t), isNot(before));
    });
  });
}
