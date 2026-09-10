// 從真實存檔的不變條件檢查中揪出來的行為 bug，各自釘住。
//
// 這幾個都不是「規格沒實作」，而是「兩處對同一件事給出不同答案」——
// 使用者在畫面上直接看得到的矛盾。

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/commerce.dart';
import 'package:fitness_app/state/app_state.dart';
import 'package:fitness_app/data/store.dart';

void main() {
  group('存檔格式改了就要升版本', () {
    test('舊版存檔整份忽略，不半套載入', () {
      final s = AppState();
      final coins = s.coins;
      expect(s.applySnapshot({'v': 1, 'coins': 1, 'mailbox': []}), isFalse,
          reason: 'v1 是 MailReward 改欄位之前的格式');
      expect(s.coins, coins, reason: '版本不符就整份不套用');
    });

    test('信箱不留數額為 0 的獎勵', () {
      final s = AppState();
      final ok = s.applySnapshot({
        'v': kSnapshotVersion,
        'mailbox': [
          {
            'source': '排行榜週期結算',
            // 欄位對不上時就會長這樣 —— 四個數額全部缺席。
            'at': '2026-09-03T15:42:27.000',
            'claimed': false,
          },
          {
            'source': '每日任務未領取',
            'coins': 6,
            'at': '2026-09-02T15:42:27.000',
            'claimed': false,
          },
        ],
      });
      expect(ok, isTrue);
      expect(s.mailbox, hasLength(1), reason: '領了會是「無」的那一筆不該留著');
      expect(s.mailbox.single.coins, 6);
      expect(s.mailbox.every((m) => !m.isEmpty), isTrue);
    });

    test('數額完整的信箱正常存讀', () async {
      final store = MemoryStore();
      final s = AppState();
      s.mailbox.insert(
        0,
        MailReward(source: '排行榜週期結算', coins: 300, exp: 120, at: s.now),
      );
      await store.save(s.toSnapshot());

      final back = AppState();
      back.applySnapshot((await store.load())!);
      final m = back.mailbox.first;
      expect(m.coins, 300);
      expect(m.exp, 120);
      expect(m.content, '金幣 300 ＋ 經驗值 120');
    });
  });

  group('成就以存檔為準，不被假資料汙染', () {
    test('存檔說沒解鎖就是沒解鎖', () {
      final s = AppState();
      // 建構子已經對假資料（totalExp 1700 ＝ 45 階）跑過一次解鎖判定。
      expect(
          s.achievements
              .any((a) => a.category == '階級' && a.threshold == 45 && a.unlocked),
          isTrue,
          reason: '前提：假資料確實會解開這一枚');

      final ok = s.applySnapshot({
        'v': kSnapshotVersion,
        'totalExp': 1230, // ＝ 38 階
        'achievements': {
          '階級#10': {'unlocked': true, 'claimed': false},
        },
      });
      expect(ok, isTrue);
      expect(s.rank, 38);
      final r45 = s.achievements
          .firstWhere((a) => a.category == '階級' && a.threshold == 45);
      expect(r45.unlocked, isFalse,
          reason: '成就頁寫「達到 45 階 ✓」、個人頁寫「38 階」，兩者不能並存');
    });

    test('載入後仍依真實進度補上該解的', () {
      final s = AppState();
      s.applySnapshot({
        'v': kSnapshotVersion,
        'totalExp': 1230,
        'achievements': <String, dynamic>{}, // 存檔一枚都沒記
      });
      final r25 = s.achievements
          .firstWhere((a) => a.category == '階級' && a.threshold == 25);
      expect(r25.unlocked, isTrue, reason: '38 階確實達到了 25 階的門檻');
    });

    test('已解鎖的成就不因當前進度掉回去', () {
      final s = AppState();
      s.applySnapshot({
        'v': kSnapshotVersion,
        'totalExp': 1230,
        'achievements': {
          // 連簽成就：現在只連 2 天，但當初確實連過 5 天。
          '連簽#5': {'unlocked': true, 'claimed': false},
        },
      });
      final a = s.achievements
          .firstWhere((a) => a.category == '連簽' && a.threshold == 5);
      expect(a.unlocked, isTrue,
          reason: '同一個帳號存續期間，解鎖紀錄單調遞增、不可撤銷');
    });
  });

  group('新帳號一律自零起算', () {
    test('成就全部歸零 —— 不繼承上一個帳號的', () {
      final s = AppState();
      expect(s.achievements.where((a) => a.unlocked), isNotEmpty,
          reason: '前提：預設狀態確實有已解鎖的成就');

      s.resetToNewAccount();
      expect(s.rank, 1);
      expect(s.achievements.where((a) => a.unlocked), isEmpty,
          reason: '階級 1 的新帳號不該有「達到 45 階」');
    });

    test('新帳號沒有可以直接領走的成就獎勵', () {
      final s = AppState();
      s.resetToNewAccount();
      final free = s.achievements
          .where((a) => a.unlocked && !a.claimed)
          .fold<int>(0, (n, a) => n + a.rewardCoins);
      expect(free, 0, reason: '否則一開新帳號就白拿一筆金幣');
      expect(s.coins, 0);
    });

    test('內容與關係一併清掉，不留下自相矛盾的帳號', () {
      final s = AppState();
      s.resetToNewAccount();
      expect(s.totalWorkoutDays, 0);
      expect(s.history, isEmpty, reason: '零次訓練卻有 5 筆訓練歷史');
      expect(s.orders, isEmpty);
      expect(s.conversations, isEmpty);
      expect(s.followers, isEmpty);
      expect(s.following, isEmpty);
      expect(s.myTeam, isNull, reason: '新帳號不該一開就在某支隊伍裡');
      expect(s.apprentices, isEmpty, reason: '新帳號不該一開就有學徒');
      expect(s.myInstructor, isNull);
      expect(s.customPlans.where((c) => c.isMine), isEmpty);
      expect(s.posts.where((p) => p.author == s.displayName), isEmpty);
    });

    test('別人的東西留著 —— 清的是我，不是這個世界', () {
      final s = AppState();
      final othersPosts = s.posts.where((p) => p.author != s.displayName).length;
      final othersPlans = s.customPlans.where((c) => !c.isMine).length;
      expect(othersPosts, greaterThan(0));
      s.resetToNewAccount();
      expect(s.posts.where((p) => p.author != s.displayName).length, othersPosts,
          reason: '新使用者打開社群不該是一片空白');
      expect(s.customPlans.where((c) => !c.isMine).length, othersPlans);
      expect(s.platformPlans, isNotEmpty);
    });

    test('歸零後照常依新帳號的進度解鎖', () {
      final s = AppState();
      s.resetToNewAccount();
      s.checkIn();
      final a = s.achievements
          .firstWhere((x) => x.category == '連簽' && x.threshold == 1);
      expect(a.unlocked, isTrue, reason: '歸零不等於從此不再解鎖');
    });
  });
}
