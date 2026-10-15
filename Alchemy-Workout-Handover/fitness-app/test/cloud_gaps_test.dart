// 四個線上回報的缺陷，三種病因。
//
// ## 一、發放只改狀態，沒發東西
// 買「AI 點數 ×10」→ 訂單顯示已發放 → 餘額一點都沒增加。
// `deliverOrder()` 只把 `state` 設成 delivered。
//
// ## 二、方法寫好了，沒有呼叫端
// `TeamSource.openTeams()` 有實作、有測試，就是沒有人叫它 ——
// 真實帳號的「找團隊」永遠是空的。
// AI 點數頁的兩個購買入口也一樣：`const _Channel(...)` 沒有 `onTap`。
//
// ## 三、整段共用一個 try，一塊失敗全滅
// `AuthGate._syncProfile()` 的六個網路 await 包在同一個 try 裡。
// 任何一個拋例外，後面全部不執行 —— 而且沒有任何跡象。
// 這個結構造成過三次線上故障（AI 代理沒接上、團隊刷新就消失、私訊讀不到）。

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/team_data.dart';
import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/domain/commerce.dart';
import 'package:fitness_app/state/app_state.dart';

void main() {
  group('虛擬商品要真的發放', () {
    Order buy(AppState s, String productId) {
      final p = s.products.firstWhere((x) => x.id == productId);
      expect(s.confirmPurchase(p, p.specs.first, 1), isNull, reason: '前提：買得成');
      return s.orders.first;
    }

    test('買 AI 點數 ×10，付款後永久點數 +10', () {
      final s = AppState()..coins = 99999;
      final before = s.aiPermanent;

      final o = buy(s, 'v1');
      expect(s.aiPermanent, before, reason: '待付款階段不該先發');

      s.payOrder(o);

      expect(o.state, OrderState.delivered);
      expect(s.aiPermanent, before + 10);
    });

    test('單次調整使用權 +1 點', () {
      final s = AppState()..coins = 99999;
      final before = s.aiPermanent;
      s.payOrder(buy(s, 'v2'));
      expect(s.aiPermanent, before + 1);
    });

    test('發放數額在下單當下凍結 —— 事後改商品不回溯', () {
      final s = AppState()..coins = 99999;
      final o = buy(s, 'v1');
      expect(o.aiCredits, 10);

      // 管理員把商品改成只發 1 點。
      final i = s.products.indexWhere((x) => x.id == 'v1');
      final old = s.products[i];
      s.products[i] = Product(
        id: old.id, name: old.name, emoji: old.emoji,
        specs: old.specs, aiCredits: 1,
      );

      final before = s.aiPermanent;
      s.payOrder(o);
      expect(s.aiPermanent, before + 10, reason: '已成立的訂單照原本的發');
    });

    test('補簽券與計畫解鎖不發 AI 點數', () {
      final s = AppState()..coins = 99999;
      for (final id in ['v3', 'v4']) {
        expect(s.products.firstWhere((x) => x.id == id).aiCredits, 0);
      }
    });

    test('發放進異動明細，查得到是哪一筆買的', () {
      final s = AppState()..coins = 99999;
      s.payOrder(buy(s, 'v1'));
      final e = s.creditHistory.first;
      expect(e.kind, CreditChange.purchase);
      expect(e.delta, 10);
      expect(e.source, contains('AI 點數'));
    });
  });

  group('公開團隊要看得到', () {
    CloudTeam team(String id, String name, {bool isPublic = true}) => CloudTeam(
          id: id,
          name: name,
          isPublic: isPublic,
          members: {
            'u-$id': CloudMember(
              name: '隊長$id',
              rank: 10,
              role: TeamRole.leader,
              joinedAt: DateTime(2026, 1, 1),
            ),
          },
        );

    test('雲端的公開團隊會進 publicTeams', () {
      final s = AppState(demo: false);
      expect(s.publicTeams, isEmpty, reason: '前提：真實帳號本來是空的');

      s.applyPublicTeams([team('a', '晨跑隊'), team('b', '重訓隊')]);

      expect(s.publicTeams.map((t) => t.name), ['晨跑隊', '重訓隊']);
      expect(s.publicTeams.first.members, hasLength(1));
    });

    test('自己已經在的那一隊不重複出現', () {
      final s = AppState(demo: false);
      s.applyCloudTeam(team('mine', '我的隊'));
      s.applyPublicTeams([team('mine', '我的隊'), team('other', '別人的隊')]);
      expect(s.publicTeams.map((t) => t.name), ['別人的隊']);
    });

    test('已解散的不列', () {
      final s = AppState(demo: false);
      s.applyPublicTeams([
        const CloudTeam(id: 'x', name: '沒了', members: {}, disbanded: true),
      ]);
      expect(s.publicTeams, isEmpty);
    });
  });

  group('複合查詢都要有索引', () {
    // fake_cloud_firestore 不檢查索引，所以 20 條團隊測試全綠、線上卻查不到。
    // 這條測試讀的是索引宣告檔，不連任何服務。
    final declared = (jsonDecode(
      File('firestore.indexes.json').readAsStringSync(),
    ) as Map)['indexes'] as List;

    String key(String col, List<String> fields) => '$col:${fields.join(",")}';
    final have = {
      for (final i in declared)
        key(i['collectionGroup'] as String,
            [for (final f in i['fields']) f['fieldPath'] as String]),
    };

    for (final want in const [
      ['conversations', 'participants', 'lastAt'],
      ['teams', 'memberUids', 'disbanded'],
      ['teams', 'isPublic', 'disbanded'],
      ['mentor_bonds', 'apprenticeUid', 'state'],
      ['requests', 'uid', 'isInvite'],
    ]) {
      test('${want.first} 的 ${want.skip(1).join(" + ")} 有索引', () {
        expect(have, contains(key(want.first, want.skip(1).toList())),
            reason: '缺了它，線上這個查詢會直接拋例外');
      });
    }

    test('程式碼裡的複合查詢沒有新增未宣告的', () {
      // 新增複合查詢卻忘了宣告索引，是這次四個故障裡兩個的成因。
      final files = Directory('lib/data')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('_firestore.dart'));
      var chains = 0;
      for (final f in files) {
        final src = f.readAsStringSync();
        for (final m in RegExp(r'(?:\.where|\.orderBy)\([^)]*\)\s*(?:\.where|\.orderBy)\(')
            .allMatches(src)) {
          chains++;
          expect(m, isNotNull);
        }
      }
      // 6 而不是 5：`requestsFor()` 多了一段「我自己送出、還沒被回應的
      // 申請」（collection group，uid + isInvite）。它與「誰邀我入隊」
      // **兩個欄位相同、都是等值比較**，所以共用同一個複合索引，
      // 不必新增宣告 —— 這條測試要的是「你有沒有回頭確認過」，
      // 不是「每條查詢都要有自己的索引」。
      //
      // 9 而不是 6：`watchTeams()` 的三條監聽（`[BE-16]` 即時訂閱）。
      // 三條的欄位組合都**逐字照抄**既有的查詢，所以三個索引都已經
      // 在線上了：
      //
      //   · memberUids + disbanded ← 抄 `myTeam()`
      //   · requests: uid + isInvite（true）← 抄「誰邀我入隊」
      //   · requests: uid + isInvite（false）← 抄「我送出的申請」
      //
      // **照抄是刻意的。** 自己湊一組條件就要重新確認安全規則與索引，
      // 而那兩件事錯了都是「畫面成功、雲端無聲拒絕」——
      // `bond()` 那次就是這樣。
      //
      // 特別注意第二三條不可以合併成只查 `uid`：線上那個索引是
      // COLLECTION_GROUP 範圍的 `(uid, isInvite)` 複合索引，
      // 只查單一欄位的 collection group 查詢需要「集合群組範圍的
      // 單欄位索引」，而那種索引**不會自動建立**。
      // 2026-09-28 由 9 增為 11：排行榜的
      // `(weeklyGroup, weeklyScore)` 與 `(monthlyGroup, monthlyScore)`，
      // 兩個索引都已加進 `firestore.indexes.json`。
      expect(chains, 11,
          reason: '複合查詢從 11 個變了 —— 請同步檢查 firestore.indexes.json');
    });
  });

  group('登入後同步：一塊失敗不該波及其他塊', () {
    final src = File('lib/screens/auth_gate.dart').readAsStringSync();

    test('每一塊各自 try，不是整段共用一個', () {
      final i = src.indexOf('Future<void> _syncProfile(');
      expect(i, isNot(-1));
      final body = src.substring(i, src.indexOf('@override', i));
      expect(RegExp(r'await step\(').allMatches(body).length, greaterThanOrEqualTo(6),
          reason: '公開檔案、貼文、私訊、我的團隊、公開團隊、師徒、關注各一塊');
    });

    test('來源在載入之前就接好 —— 讀取失敗不該讓之後的寫入全掉', () {
      final i = src.indexOf('Future<void> _syncProfile(');
      final body = src.substring(i, src.indexOf('@override', i));
      for (final f in ['postSource', 'chatSource', 'teamSource', 'mentorSource',
        'followSource']) {
        expect(body.indexOf('state.$f ='), lessThan(body.indexOf('await step(')),
            reason: '$f 要排在第一個 await 之前');
      }
    });

    test('平台資料的來源也要交給狀態層 —— 不然後台改了東西寫不回去', () {
      final i = src.indexOf('Future<void> _loadPlatformData(');
      expect(i, isNot(-1));
      final body = src.substring(i, src.indexOf('\n  }', i));
      expect(body, contains('state.platformSource = '),
          reason: '在此之前 AuthGate 讀完就把來源丟了，'
              '而 AppState 沒有任何寫回雲端的管道 —— 那正是 P123 的症狀');
      expect(body.indexOf('state.platformSource = '),
          lessThan(body.indexOf('await src.load()')),
          reason: '載入失敗時來源仍要接著，否則連重試都寫不回去');
    });

    // 即時訂閱的開關（`[BE-16]`）。這兩條與上面同一種寫法：讀原始碼。
    // 訂閱要接上 Firebase 才跑得起來，而這個專案的測試不連任何服務 ——
    // 所以至少釘住「這兩行有沒有在該在的位置」。
    test('訂閱排在同步的最後 —— 團隊那條需要先知道我在哪一隊', () {
      final i = src.indexOf('Future<void> _syncProfile(');
      final body = src.substring(i, src.indexOf('@override', i));
      final start = body.indexOf('startCloudWatch()');
      expect(start, isNot(-1), reason: '登入後沒有開始訂閱，即時就是沒接上');
      // 監看「別人申請加入我的隊」要帶隊伍 ID，而那是上面「我的團隊」
      // 那一塊讀回來的。排在前面的話隊長永遠收不到申請的訊號。
      expect(start, greaterThan(body.lastIndexOf('await step(')),
          reason: '要排在所有同步區塊之後');
    });

    test('登入時讀管理員 claim —— 判準要與 firestore.rules 同源', () {
      final i = src.indexOf('Future<void> _syncProfile(');
      final body = src.substring(i, src.indexOf('@override', i));
      // 規則的 isAdmin() 看 request.auth.token.admin。畫面上若各自判斷，
      // 會做出「後台進得去、每個寫入都被規則擋下」——
      // 那是最難查的一種，兩邊都覺得自己是對的，而失敗是靜默的。
      expect(body, contains('applyAdminClaim'),
          reason: '不讀 claim 的話，真管理員永遠不是管理員');
      expect(body, contains("claims['admin']"));
    });

    test('登出時收掉訂閱 —— 不收會讓下一個帳號被上一個的變動叫醒', () {
      // 訂閱綁在建立它的那個 Source 上（帶著當時的 uid），
      // Source 換掉了舊訂閱不會自己停。
      final i = src.indexOf('if (user == null) {');
      expect(i, isNot(-1));
      final body = src.substring(i, src.indexOf('}', i));
      expect(body, contains('stopCloudWatch()'));
    });
  });
}
