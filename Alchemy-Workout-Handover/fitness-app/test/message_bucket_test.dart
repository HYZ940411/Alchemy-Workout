import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/state/app_state.dart';

/// 使用者回報「追蹤後沒有從陌生訊息更新到一般訊息」。
///
/// **訊息的分類於發送當下固定，規格明訂不回溯改寫**（〈聊天私訊流程〉）——
/// 那是對的，沒有動它。但「對話歸哪一區」是 Read Model 的事，
/// 而它原本讀的是**最後一則訊息**的分類，所以關係轉正之後要等對方
/// 再傳一則才會移動。
///
/// **而且「一般訊息」要的是互相關注**，不是我單方追蹤 ——
/// 那個對話框原本承諾「追蹤之後他的訊息會進一般訊息」，是假的。
void main() {
  Conversation convo(String peer, {required MessageCategory lastCategory}) {
    final c = Conversation(id: 'c-$peer', peer: peer, peerRank: 10);
    c.messages.add(ChatMessage(false, '嗨', DateTime(2026, 9, 27),
        category: lastCategory));
    return c;
  }

  group('分區依此刻的關係，只升不降', () {
    test('單方追蹤還不夠 —— 要互相關注', () {
      final s = AppState();
      final c = convo('小美', lastCategory: MessageCategory.stranger);
      s.following.add('小美');
      expect(s.bucketOf(c), MessageCategory.stranger,
          reason: '規格：一般訊息的條件是互相關注');
    });

    test('互相關注之後立刻移到一般訊息，不必等對方再傳一則', () {
      final s = AppState();
      final c = convo('小美', lastCategory: MessageCategory.stranger);
      s.following.add('小美');
      s.followers.add('小美');
      expect(s.bucketOf(c), MessageCategory.normal);
    });

    test('同隊也算一般訊息', () {
      final s = AppState()
        ..myTeam = Team(
          id: 't1',
          name: '隊',
          isPublic: true,
          capacity: 5,
          members: [const TeamMember('小美', 10, TeamRole.member, uid: 'u2')],
        );
      final c = convo('小美', lastCategory: MessageCategory.stranger);
      expect(s.bucketOf(c), MessageCategory.normal);
    });

    test('**只升不降** —— 曾經是一般訊息就不會被丟回陌生區', () {
      // 曾經是隊友、後來退隊，那段對話不該回到陌生訊息。
      final s = AppState();
      final c = convo('小美', lastCategory: MessageCategory.normal);
      expect(s.following.contains('小美'), isFalse, reason: '現在沒有任何關係');
      expect(s.bucketOf(c), MessageCategory.normal);
    });

    test('沒有任何關係、最後一則也是陌生 → 陌生', () {
      final s = AppState();
      final c = convo('路人', lastCategory: MessageCategory.stranger);
      expect(s.bucketOf(c), MessageCategory.stranger);
    });
  });

  group('分類的定義只有一份', () {
    test('分區與發送時用的是同一支判斷', () {
      final s = AppState();
      s.following.add('小美');
      s.followers.add('小美');
      expect(s.currentCategoryWith('小美'), MessageCategory.normal);
      expect(s.currentCategoryWith('路人'), MessageCategory.stranger);
    });
  });
}
