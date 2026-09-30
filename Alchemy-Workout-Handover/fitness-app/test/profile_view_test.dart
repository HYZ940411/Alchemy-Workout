// 別人的檔案頁要顯示**別人**的資料（接在 `[QA-02i]` 之後）。
//
// `[QA-02i]` 把入口接上之後，畫面終於點得進去 —— 也才看得出裡面的欄位
// 幾乎全部讀的是 `s.`：我的階級、我的粉絲數、我的六維點數，
// 以及動態牆的前兩則貼文（不是這個人寫的）。於是每一個人的檔案頁
// 長得一模一樣，而且顯示的是看的人自己。
//
// 與 `[QA-02f]`／`[QA-02i]` 是同一種病：每一塊各自是對的，接縫是斷的。
// 那一種缺陷只有把「看別人」整條路走一遍的測試抓得到，
// 所以這個檔案一律以「看某一位指定的人」為前提，不測自己那一頁。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/public_profile.dart';
import 'package:fitness_app/domain/ability.dart';
import 'package:fitness_app/design/components.dart';
import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/screens/me/profile_screen.dart';
import 'package:fitness_app/screens/social/chat_screen.dart';
import 'package:fitness_app/state/app_state.dart';
import 'package:fitness_app/widgets/radar_chart.dart';

Future<void> _open(WidgetTester t, AppState s, String? who) async {
  t.view.physicalSize = const Size(393 * 3, 852 * 3);
  t.view.devicePixelRatio = 3.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(AppScope(
    state: s,
    child: MaterialApp(home: ProfileScreen(viewing: who)),
  ));
  await t.pumpAndSettle();
}

void main() {
  group('數字讀的是對方的，不是我的', () {
    test('階級', () {
      final s = AppState();
      // 前提：這兩個數字本來就不一樣，否則這條測試證明不了東西。
      expect(s.rank, isNot(27));
      expect(s.rankOf('早鳥訓練'), 27);
      expect(s.rankOf(s.displayName), s.rank);
    });

    test('粉絲數', () {
      final s = AppState();
      expect(s.followersOf('早鳥訓練'),
          s.otherFollowerCounts[s.personKeyOf('早鳥訓練', null)]);
      expect(s.followersOf('早鳥訓練'), isNot(s.followerCount));
      expect(s.followersOf(s.displayName), s.followerCount);
    });

    test('教官聲望：非教官沒有這個數字', () {
      final s = AppState();
      expect(s.reputationOf('CoreMax'), 610);
      expect(s.reputationOf('早鳥訓練'), isNull);
    });

    testWidgets('畫面上顯示的階級是對方的', (t) async {
      final s = AppState();
      await _open(t, s, '早鳥訓練');
      expect(find.text('27'), findsOneWidget);
      expect(find.text('${s.rank}'), findsNothing, reason: '我的階級不該出現在他的頁面上');
    });
  });

  group('能力值', () {
    test('教官看得到六維 —— 教官身分讓兩個可見度開關失效', () {
      final s = AppState();
      final ins = s.instructors.firstWhere((i) => i.name == 'CoreMax');
      expect(s.abilityOf('CoreMax'), ins.ability);
      expect(s.abilityOf('CoreMax'), isNot(s.points));
    });

    test('拿不到六維時回空值 —— 不拿我自己的頂上', () {
      final s = AppState();
      expect(s.abilityOf('早鳥訓練'), isNull,
          reason: '他不是教官、也不在公開檔案裡，我們就是沒有他的六維明細');
    });

    test('雲端讀回來的公開檔案會保留六維', () {
      final s = AppState();
      const six = {
        Dim.chest: 120, Dim.back: 130, Dim.legs: 140,
        Dim.shoulders: 110, Dim.arms: 100, Dim.core: 150,
      };
      s.applyPublicProfiles([
        const PublicProfile(
            uid: 'u-neo', displayName: 'Neo', rank: 16,
            grade: 'C', ability: six, followers: 3),
      ]);
      expect(s.abilityOf('Neo'), six);
      expect(s.rankOf('Neo'), 16);
      expect(s.followersOf('Neo'), 3);
    });

    test('雲端來了本機沒有的人也加得進去 —— 示範清單必須是可增長的', () {
      // `buildSocialUsers()` 原本回傳 `const [...]`，於是 `applyPublicProfiles`
      // 的 `socialUsers.add()` 會拋 `Cannot add to an unmodifiable list`。
      // 也就是說這條路從 `[BE-11]` 批次 1 寫出來就是壞的 —— 只要雲端回傳
      // 一位本機沒有的使用者就當場炸。沒人發現，是因為沒有測試餵過新名字。
      final s = AppState();
      final before = s.socialUsers.length;
      s.applyPublicProfiles([
        const PublicProfile(uid: 'u-new', displayName: '新來的', rank: 5),
      ]);
      expect(s.socialUsers.length, before + 1);
      expect(s.userOf('新來的').rank, 5);
    });

    test('對方關掉六維可見度時仍拿不到，綜合等級照給', () {
      final s = AppState();
      s.applyPublicProfiles([
        const PublicProfile(
            uid: 'u-x', displayName: '阿丁', rank: 20, grade: 'C'),
      ]);
      expect(s.abilityOf('阿丁'), isNull);
      expect(s.gradeOf('阿丁'), 'C');
    });

    testWidgets('沒有六維資料時不畫雷達圖', (t) async {
      final s = AppState();
      await _open(t, s, '早鳥訓練');
      expect(find.byType(RadarChart), findsNothing,
          reason: '沒有他的點數卻畫出一張圖，畫的就是我自己的');
      expect(find.text('C'), findsWidgets, reason: '綜合等級還是給得出來');
    });

    testWidgets('有六維資料時畫的是對方的點數', (t) async {
      final s = AppState();
      await _open(t, s, 'CoreMax');
      final chart = t.widget<RadarChart>(find.byType(RadarChart));
      expect(chart.points, s.instructors.firstWhere((i) => i.name == 'CoreMax').ability);
      expect(chart.points, isNot(s.points));
    });
  });

  group('公開貼文', () {
    test('只列這個人寫的', () {
      final s = AppState();
      final mine = s.postsBy('深蹲王');
      expect(mine, isNotEmpty);
      expect(mine.every((p) => p.author == '深蹲王'), isTrue);
      expect(s.postsBy('深蹲王').length, isNot(s.visiblePosts.length),
          reason: '原本取的是整個動態牆');
    });

    // 原本驗「看別人時不列僅關注者與私人的貼文」。
    // **可見範圍已移除**（使用者裁決 2026-09-26）—— 理由見
    // `PostVisibility` 的註解：它從來沒有生效過。
    test('看別人時，舊貼文不論當初標什麼都列出來', () {
      final s = AppState();
      for (final v in [PostVisibility.followersOnly, PostVisibility.private]) {
        s.posts.insert(0, Post(
          id: 'p-$v', author: '早鳥訓練', authorRank: 27,
          text: '${v.name} 的貼文', at: DateTime.now(), visibility: v));
      }
      final got = s.postsBy('早鳥訓練').map((p) => p.text);
      expect(got, contains('private 的貼文'));
      expect(got, contains('followersOnly 的貼文'));
    });

    test('看自己時三種可見範圍都列 —— 那本來就是我的東西', () {
      final s = AppState();
      s.posts.insert(0, Post(
        id: 'p-priv', author: s.displayName, authorRank: 45,
        text: '只給自己看', at: DateTime.now(),
        visibility: PostVisibility.private));
      expect(s.postsBy(s.displayName).any((p) => p.id == 'p-priv'), isTrue);
    });

    test('已刪除的不列', () {
      final s = AppState();
      s.posts.insert(0, Post(
        id: 'p-del', author: '早鳥訓練', authorRank: 27,
        text: '刪掉了', at: DateTime.now(), deleted: true));
      expect(s.postsBy('早鳥訓練').any((p) => p.id == 'p-del'), isFalse);
    });

    testWidgets('一則都沒有時說得出來，不是留一張空卡片', (t) async {
      final s = AppState();
      s.posts.removeWhere((p) => p.author == '早鳥訓練');
      await _open(t, s, '早鳥訓練');
      expect(find.text('早鳥訓練 沒有公開的貼文。'), findsOneWidget);
    });
  });

  group('開始聊天', () {
    test('沒有對話就開一段新的', () {
      final s = AppState();
      expect(s.conversations.any((c) => c.peer == 'Yuki'), isFalse, reason: '前提');
      final c = s.conversationWith('Yuki');
      expect(c.peer, 'Yuki');
      expect(c.peerRank, s.rankOf('Yuki'));
      expect(c.messages, isEmpty);
      expect(s.visibleConversations.contains(c), isTrue);
    });

    test('再開一次是同一段，不會長出第二段', () {
      final s = AppState();
      final a = s.conversationWith('Yuki');
      final b = s.conversationWith('Yuki');
      expect(identical(a, b), isTrue);
      expect(s.conversations.where((c) => c.peer == 'Yuki').length, 1);
    });

    test('已經有對話就沿用既有那段，不清掉訊息', () {
      final s = AppState();
      final before = s.conversations.firstWhere((c) => c.peer == 'CoreMax');
      final n = before.messages.length;
      expect(n, greaterThan(0), reason: '前提：這段對話本來就有訊息');
      final c = s.conversationWith('CoreMax');
      expect(identical(c, before), isTrue);
      expect(c.messages.length, n);
    });

    test('單方刪除過的對話，我主動找他就回來', () {
      final s = AppState();
      final c = s.conversations.firstWhere((x) => x.peer == 'CoreMax');
      s.deleteConversation(c);
      expect(s.visibleConversations.contains(c), isFalse, reason: '前提：已刪除');

      s.conversationWith('CoreMax');
      expect(c.deletedByMe, isFalse);
      expect(s.visibleConversations.contains(c), isTrue);
    });

    test('新對話的 ID 不與既有的撞號', () {
      final s = AppState();
      final ids = s.conversations.map((c) => c.id).toSet();
      final c = s.conversationWith('Yuki');
      expect(ids.contains(c.id), isFalse);
      expect(s.conversations.map((c) => c.id).toSet().length,
          s.conversations.length);
    });

    testWidgets('別人的檔案頁上有這顆按鈕，按了進得去對話', (t) async {
      final s = AppState();
      await _open(t, s, 'Yuki');
      expect(find.text('開始聊天'), findsOneWidget);

      await t.tap(find.text('開始聊天'));
      await t.pumpAndSettle();

      expect(find.byType(ChatScreen), findsOneWidget);
      expect(s.conversations.any((c) => c.peer == 'Yuki'), isTrue);
    });

    testWidgets('自己那一頁沒有這顆按鈕', (t) async {
      await _open(t, AppState(), null);
      expect(find.text('開始聊天'), findsNothing);
    });

    testWidgets('封鎖過的人不給聊', (t) async {
      final s = AppState();
      // **不能挑 Yuki** —— 他是我隊伍的成員，而規格明訂同隊的人不能封鎖
      // （`blockBlockedReason`）。挑一個不在隊上的人，並把封鎖成功
      // 這件事當成前提斷言 —— 否則封鎖失敗時這條測試會靜靜地驗錯東西。
      expect(s.blockUser('Ashley'), isTrue, reason: '前提：封鎖要真的成立');
      await _open(t, s, 'Ashley');
      final btn = t.widget<AppButton>(
        find.ancestor(of: find.text('開始聊天'), matching: find.byType(AppButton)));
      expect(btn.onPressed, isNull);
    });
  });
}
