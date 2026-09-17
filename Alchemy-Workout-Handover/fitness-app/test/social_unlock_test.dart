// 社群互動要先解鎖（`[QA-02f]`）。
//
// 使用者回報「功能一開始就全開，沒有依事件風暴逐一解鎖」。查下去發現
// `socialUnlocked` 這個旗標**存在、會存檔、會還原、狀態層還有測試** ——
// 但整個 `lib/screens/` 底下沒有任何一處讀它。旗標做好了，閘門沒裝。
//
// 規格（〈新手任務流程〉）明訂解鎖範圍為**發文、按讚、留言、分享、關注
// 五項**，不是整個社群分頁。看得到但不能互動，才有動機去把任務做完；
// 整頁擋掉的話新使用者連社群長什麼樣都不知道。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/screens/social/feed_screen.dart';
import 'package:fitness_app/widgets/common.dart';
import 'package:fitness_app/state/app_state.dart';

/// 真正的新帳號：走 hydrate 讀不到存檔那條路的狀態。
AppState _newUser() {
  final s = AppState()..resetToNewAccount();
  s.posts.insert(
    0,
    Post(
      id: 'p-test',
      author: '測試對象',
      authorRank: 30,
      text: '今天練完了。',
      at: DateTime.now(),
    ),
  );
  return s;
}

Future<void> _openFeed(WidgetTester t, AppState s) async {
  t.view.physicalSize = const Size(393 * 3, 852 * 3);
  t.view.devicePixelRatio = 3.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(AppScope(
    state: s,
    child: const MaterialApp(home: Scaffold(body: FeedScreen())),
  ));
  await t.pumpAndSettle();
  await t.tap(find.text('探索'));
  await t.pumpAndSettle();
}

void main() {
  group('旗標本身', () {
    test('新帳號尚未解鎖', () {
      expect((AppState()..resetToNewAccount()).socialUnlocked, isFalse);
    });

    test('示範用身分早就解鎖了 —— 階級 45、練過 63 場的人不會沒做過新手任務', () {
      expect(AppState().socialUnlocked, isTrue);
    });

    test('完成新手任務即解鎖', () {
      final s = AppState()..resetToNewAccount();
      s
        ..startNovice()
        ..selectNovice('n_squat')
        ..toggleNoviceCheck()
        ..finishNovice();
      expect(s.socialUnlocked, isTrue);
    });
  });

  group('閘門裝在五個動作上，不是裝在分頁上', () {
    testWidgets('社群分頁照樣看得到 —— 看不到就沒有動機去解鎖', (t) async {
      final s = _newUser();
      await _openFeed(t, s);
      expect(find.text('測試對象'), findsOneWidget);
      expect(find.text('今天練完了。'), findsOneWidget);
    });

    testWidgets('按讚被擋下，而且說得出怎麼解開', (t) async {
      final s = _newUser();
      await _openFeed(t, s);

      await t.tap(find.byIcon(Icons.favorite_border).first);
      await t.pumpAndSettle();

      expect(s.posts.first.likedByMe, isFalse, reason: '沒有真的按下去');
      expect(find.textContaining('新手任務'), findsWidgets,
          reason: '只說「不能按」沒有用，要說得出怎麼解開');
    });

    testWidgets('發文被擋下', (t) async {
      final s = _newUser();
      await _openFeed(t, s);

      await t.tap(find.widgetWithText(AppButton, '發文'));
      await t.pumpAndSettle();

      expect(find.textContaining('新手任務'), findsWidgets);
    });

    testWidgets('解鎖之後按讚就通了', (t) async {
      // 這一條是反面 —— 少了它，把閘門寫成「永遠擋」也會全綠。
      final s = _newUser()..socialUnlocked = true;
      await _openFeed(t, s);

      await t.tap(find.byIcon(Icons.favorite_border).first);
      await t.pumpAndSettle();

      expect(s.posts.first.likedByMe, isTrue);
    });
  });
}
