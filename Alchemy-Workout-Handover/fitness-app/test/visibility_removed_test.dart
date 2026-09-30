// 可見範圍已移除，貼文一律公開（使用者裁決 2026-09-26）。
//
// ## 為什麼是移除而不是修好
//
// 它**從來沒有生效過**：
//
//   · 動態牆的 `visiblePosts` 只濾掉「已刪除」，可見範圍一個字都沒看
//   · `firestore.rules` 的貼文讀取是 `allow read: if request.auth != null`
//     —— **任何登入者都讀得到每一篇**，包括標「私人」的
//
// 只有檔案頁的 `postsBy()` 有濾，而那只是讓「我自己」看不到別人的
// 私人貼文，別人照樣在動態牆上看得到。那個開關一直在對使用者說一件
// 不是真的事。
//
// 要真的做對，「僅關注者」得讓安全規則判斷「讀的人有沒有關注作者」，
// 而那在查詢裡做不到（Firestore 要求查詢條件本身就證明得了權限），
// 得把可見名單反正規化到每一篇貼文上 —— 關注一個人就要回頭改他所有
// 的貼文。成本與效益不成比例。
//
// 使用者裁決：移除選項。**停止假裝有保護，比留著一個擋不住任何人的
// 開關誠實。**
//
// ## 列舉留著不刪
//
// 雲端既有的貼文文件上有 `visibility` 欄位，刪掉列舉的話舊文件解不出來。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/screens/social/compose_post_screen.dart';
import 'package:fitness_app/screens/social/mentor_screen.dart';
import 'package:fitness_app/state/app_state.dart';

Post _post(PostVisibility v, {String author = '小明'}) => Post(
      id: 'p-${v.name}',
      author: author,
      authorRank: 1,
      text: '${v.name} 的貼文',
      at: DateTime(2026, 9, 26),
      visibility: v,
    );

void main() {
  group('發文頁沒有可見範圍的選擇器', () {
    testWidgets('三個選項都不在了', (t) async {
      t.view.physicalSize = const Size(393 * 3, 852 * 4);
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(AppScope(
        state: AppState(),
        child: const MaterialApp(home: ComposePostScreen()),
      ));
      await t.pumpAndSettle();

      expect(find.text('可見範圍'), findsNothing);
      expect(find.text('公開'), findsNothing);
      expect(find.text('僅關注者'), findsNothing);
      expect(find.text('私人'), findsNothing);
    });
  });

  group('新發的貼文一律公開', () {
    test('publishPost 寫的是 public', () {
      final s = AppState(demo: false)..displayName = '我';
      s.publishPost('今天練腿', PostVisibility.public);
      expect(s.posts.first.visibility, PostVisibility.public);
    });
  });

  group('舊貼文不論當初標什麼都看得到', () {
    test('檔案頁列出全部', () {
      final s = AppState(demo: false)..myUid = 'u-me';
      s.posts.addAll([
        _post(PostVisibility.public),
        _post(PostVisibility.followersOnly),
        _post(PostVisibility.private),
      ]);

      // 這不是新的曝光 —— 它們本來就在所有人的動態牆上。
      expect(s.postsBy('小明'), hasLength(3));
    });

    test('動態牆本來就沒在濾 —— 這條是為了說明「移除沒有放寬任何東西」', () {
      final s = AppState(demo: false)..myUid = 'u-me';
      s.posts.addAll([
        _post(PostVisibility.private),
        _post(PostVisibility.followersOnly),
      ]);
      expect(s.visiblePosts, hasLength(2));
    });

    test('已刪除的仍然不列 —— 那是另一條規則', () {
      final s = AppState(demo: false)..myUid = 'u-me';
      final p = _post(PostVisibility.public)..deleted = true;
      s.posts.add(p);
      expect(s.visiblePosts, isEmpty);
      expect(s.postsBy('小明'), isEmpty);
    });
  });

  group('列舉留著不刪', () {
    test('三個值都還在 —— 雲端舊文件要解得出來', () {
      expect(PostVisibility.values, hasLength(3));
    });
  });

  _mentorPageEntry();
}

/// 社群 → 師徒頁的教官申請入口（使用者裁決 2026-09-26）。
///
/// 入口原本只在「我的」→ 更多底下，而會想當教官的人，
/// 正是在這一頁看別人教官檔案的人。
void _mentorPageEntry() {
  group('師徒頁的教官申請入口', () {
    Future<void> pump(WidgetTester t, AppState s) async {
      t.view.physicalSize = const Size(393 * 3, 852 * 4);
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(AppScope(
          state: s, child: const MaterialApp(home: Scaffold(body: MentorScreen()))));
      await t.pumpAndSettle();
    }

    testWidgets('還不是教官 → 看得到入口', (t) async {
      await pump(t, AppState());
      expect(find.text('我要成為教官'), findsOneWidget);
    });

    testWidgets('已經是教官 → 不顯示', (t) async {
      // 那一頁對他只剩「你已通過」一句話。
      await pump(t, AppState()..isInstructor = true);
      expect(find.text('我要成為教官'), findsNothing);
    });
  });
}
