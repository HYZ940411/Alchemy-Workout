import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/store.dart';

import 'package:fitness_app/state/app_state.dart';

/// 重抽到指定判定來源的任務為止。抽取為隨機，故得試幾次。
DailyTaskProbe? drawUntil(AppState s, String event, {int tries = 80}) {
  for (var i = 0; i < tries; i++) {
    s.redrawDailyTasks();
    final hit = s.dailyTasks.where((t) => t.sourceEvent == event);
    if (hit.isNotEmpty) {
      return (progress: hit.first.progress, target: hit.first.target);
    }
  }
  return null;
}

typedef DailyTaskProbe = ({int progress, int target});

void main() {
  group('日中重抽的任務，進度自「今天已發生的事」起算', () {
    test('已簽到者重抽出的簽到任務即為完成', () {
      final s = AppState();
      s.checkIn();
      final t = drawUntil(s, '使用者已簽到');
      expect(t, isNotNull, reason: '池子裡有簽到項目');
      expect(t!.progress, t.target,
          reason: '上面寫「今日已簽到」，下面卻是 0/1 —— 同一個畫面自相矛盾');
    });

    test('未簽到者重抽出的簽到任務為 0', () {
      final s = AppState();
      expect(s.checkedInToday, isFalse);
      final t = drawUntil(s, '使用者已簽到');
      expect(t!.progress, 0);
    });

    test('今天按過的讚算進重抽出的按讚任務', () {
      final s = AppState();
      final posts = s.posts.where((p) => p.author != s.displayName).toList();
      s.toggleLike(posts[0]);
      s.toggleLike(posts[1]);
      final t = drawUntil(s, '互動者已按讚貼文');
      expect(t!.progress, 2);
    });

    test('今天留過的言算進重抽出的留言任務', () {
      final s = AppState();
      final p = s.posts.firstWhere((p) => p.author != s.displayName);
      s.addComment(p, '今天的第一則留言');
      final t = drawUntil(s, '互動者已留言');
      expect(t!.progress, greaterThanOrEqualTo(1));
    });

    test('進度不超過目標', () {
      final s = AppState();
      final posts = s.posts.where((p) => p.author != s.displayName).toList();
      for (final p in posts) {
        s.toggleLike(p);
      }
      final t = drawUntil(s, '互動者已按讚貼文');
      expect(t!.progress, lessThanOrEqualTo(t.target));
    });

    test('跨日重置時抽出來的任務一律自 0 起算', () {
      final s = AppState();
      s.checkIn();
      s.advanceDemoClock(const Duration(days: 1));
      // 新的一天還沒簽到，故新抽出的簽到任務為 0。
      for (final t in s.dailyTasks) {
        if (t.sourceEvent == '使用者已簽到') expect(t.progress, 0);
      }
    });

    test('沒有逐日計數的判定來源自 0 起算，不亂猜', () {
      final s = AppState();
      final t = drawUntil(s, '使用者已完成該組');
      expect(t!.progress, 0, reason: '組數沒有當日計數，猜一個數字比從 0 起算更糟');
    });
  });

  group('自存檔還原也要對帳', () {
    test('存檔裡是 0/1、今天卻已簽到 → 載入後補成 1/1', () {
      final s = AppState();
      s.checkIn();
      // 模擬存檔留下的舊進度：任務被重抽過、進度歸零。
      for (final t in s.dailyTasks) {
        t.progress = 0;
      }
      expect(s.reconcileDailyTasks(), isTrue);
      for (final t in s.dailyTasks) {
        if (t.sourceEvent == '使用者已簽到') {
          expect(t.progress, t.target,
              reason: '上面寫「今日已簽到」，下面就不能是 0/1');
        }
      }
    });

    test('只往上補，不砍掉沒有逐日計數的來源', () {
      final s = AppState();
      final sets = s.dailyTasks
          .where((t) => t.sourceEvent == '使用者已完成該組')
          .toList();
      if (sets.isEmpty) return;
      sets.first.progress = 5;
      s.reconcileDailyTasks();
      expect(sets.first.progress, 5,
          reason: '砍下去會把使用者真的做過的事抹掉');
    });

    test('對帳是冪等的', () {
      final s = AppState();
      s.checkIn();
      for (final t in s.dailyTasks) {
        t.progress = 0;
      }
      expect(s.reconcileDailyTasks(), isTrue);
      expect(s.reconcileDailyTasks(), isFalse, reason: '第二次沒有東西可補');
    });
  });

  group('存讀一輪之後仍然一致', () {
    test('存檔存下 0/1、今天已簽到 → 讀回來是 1/1', () async {
      final store = MemoryStore();
      final a = AppState();
      await a.hydrate(store);
      a.checkIn();
      // 把進度弄髒 —— 相當於任務在簽到之後才被重抽並存下。
      for (final t in a.dailyTasks) {
        t.progress = 0;
      }
      await a.saveNow();

      final b = AppState();
      await b.hydrate(store);
      expect(b.checkedInToday, isTrue);
      final t = b.dailyTasks
          .where((t) => t.sourceEvent == '使用者已簽到')
          .toList();
      expect(t, isNotEmpty, reason: '存檔裡本來就有一項簽到任務');
      expect(t.first.progress, t.first.target,
          reason: '讀回來的畫面不能自相矛盾');
    });
  });
}

class MemoryStore implements Store {
  Map<String, dynamic>? _data;
  @override
  Future<Map<String, dynamic>?> load() async => _data;
  @override
  Future<void> save(Map<String, dynamic> data) async =>
      _data = Map<String, dynamic>.from(data);
  @override
  Future<void> clear() async => _data = null;
}
