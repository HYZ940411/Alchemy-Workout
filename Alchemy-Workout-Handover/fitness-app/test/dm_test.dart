import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/admin.dart';
import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/domain/platform_config.dart';
import 'package:fitness_app/state/app_state.dart';

Conversation _with(AppState s, String peer) =>
    s.conversations.firstWhere((c) => c.peer == peer);

/// 造一個跟我毫無關係的對象。
Conversation _stranger(AppState s) {
  final c = Conversation(id: 'cx', peer: '路人甲', peerRank: 5);
  s.conversations.add(c);
  s.following.remove(s.personKeyOf('路人甲', null));
  s.followers.remove(s.personKeyOf('路人甲', null));
  return c;
}

void main() {
  setUp(platformConfig.reset);
  tearDown(platformConfig.reset);

  group('訊息分類於發送當下判定', () {
    test('互相關注 → 一般訊息', () {
      final s = AppState();
      final c = _stranger(s);
      s.toggleFollow(c.peer);
      s.gainFollower(c.peer);
      s.sendMessage(c, '嗨');
      expect(c.messages.last.category, MessageCategory.normal);
    });

    test('只有單向關注 → 仍是陌生訊息', () {
      final s = AppState();
      final c = _stranger(s);
      s.toggleFollow(c.peer); // 我關注他，他沒關注我
      s.sendMessage(c, '嗨');
      expect(c.messages.last.category, MessageCategory.stranger);
    });

    test('同團隊 → 一般訊息', () {
      final s = AppState();
      final mate = s.myTeam!.members
          .firstWhere((m) => m.name != s.displayName).name;
      final c = Conversation(id: 'cm', peer: mate, peerRank: 20);
      s.conversations.add(c);
      s.sendMessage(c, '嗨');
      expect(c.messages.last.category, MessageCategory.normal);
    });

    test('師徒關係 → 一般訊息', () {
      final s = AppState();
      final ins = s.instructors.first;
      s.myInstructor = ins;
      final c = Conversation(id: 'ci', peer: ins.name, peerRank: 50);
      s.conversations.add(c);
      s.sendMessage(c, '嗨');
      expect(c.messages.last.category, MessageCategory.normal);
    });

    test('毫無關係 → 陌生訊息，且不設數量上限', () {
      final s = AppState();
      final c = _stranger(s);
      for (var i = 0; i < 30; i++) {
        expect(s.sendMessage(c, '第 $i 則'), FilterVerdict.pass);
      }
      expect(c.messages.length, 30);
      expect(c.messages.every((m) => m.category == MessageCategory.stranger),
          isTrue);
    });

    test('分類不回溯改寫：關係轉正後，既有訊息仍是陌生訊息', () {
      final s = AppState();
      final c = _stranger(s);
      s.sendMessage(c, '第一則');
      expect(c.messages.last.category, MessageCategory.stranger);

      s.toggleFollow(c.peer);
      s.gainFollower(c.peer);
      s.sendMessage(c, '第二則');

      expect(c.messages.first.category, MessageCategory.stranger,
          reason: '既有訊息不回溯改寫');
      expect(c.messages.last.category, MessageCategory.normal);
    });

    test('回覆本身不建立關係，後續仍為陌生訊息', () {
      final s = AppState();
      final c = _stranger(s);
      c.messages.add(ChatMessage(false, '你好', s.now,
          category: MessageCategory.stranger));
      s.sendMessage(c, '你好啊'); // 我回覆了
      expect(c.messages.last.category, MessageCategory.stranger);
    });
  });

  group('送出前的自動過濾', () {
    test('明顯違規：當場攔截，不寫入，最後訊息時戳不變', () {
      final s = AppState();
      final c = _with(s, '增肌中');
      final before = c.messages.length;
      final lastAt = c.last?.at;

      expect(s.sendMessage(c, '加賴 詐騙'), FilterVerdict.blocked);
      expect(c.messages.length, before, reason: '不寫入私訊 Aggregate');
      expect(c.last?.at, lastAt, reason: '對話的最後訊息時戳不變');
    });

    test('疑似違規：照常送出，並自動開立檢舉案', () {
      final s = AppState();
      final c = _with(s, '增肌中');
      final cases = s.reports.length;
      final before = c.messages.length;

      expect(s.sendMessage(c, '有人推薦類固醇，你覺得呢'), FilterVerdict.flagged);
      expect(c.messages.length, before + 1, reason: '照常送出');
      expect(c.messages.last.pendingReview, isTrue);

      expect(s.reports.length, cases + 1, reason: '自動開立檢舉案');
      final r = s.reports.first;
      expect(r.origin, CaseOrigin.autoFlag);
      expect(r.target, ReportTarget.message);
      expect(r.reporterCount, 0, reason: '系統標記，沒有檢舉人');
    });

    test('貼文的疑似違規同樣自動開案', () {
      final s = AppState();
      final cases = s.reports.length;
      expect(s.publishPost('聽說禁藥很有效', PostVisibility.public), FilterVerdict.flagged);
      expect(s.reports.length, cases + 1);
      expect(s.reports.first.target, ReportTarget.post);
    });

    test('一般內容照常送出，不開案', () {
      final s = AppState();
      final c = _with(s, '增肌中');
      final cases = s.reports.length;
      expect(s.sendMessage(c, '明天一起練？'), FilterVerdict.pass);
      expect(c.messages.last.pendingReview, isFalse);
      expect(s.reports.length, cases);
    });

    test('空白訊息不送出', () {
      final s = AppState();
      final c = _with(s, '增肌中');
      final before = c.messages.length;
      s.sendMessage(c, '   ');
      expect(c.messages.length, before);
    });
  });

  group('對話清單的分區', () {
    test('取最後一則訊息的分類 —— 關係轉正後對話移到一般訊息', () {
      final s = AppState();
      final c = _stranger(s);
      s.sendMessage(c, '陌生的第一則');
      expect(c.bucket, MessageCategory.stranger);

      s.toggleFollow(c.peer);
      s.gainFollower(c.peer);
      s.sendMessage(c, '現在互相關注了');
      expect(c.bucket, MessageCategory.normal);
    });
  });
}
