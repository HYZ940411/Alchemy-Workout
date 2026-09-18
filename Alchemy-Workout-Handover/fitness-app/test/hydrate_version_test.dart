// 存檔格式版本對不上時，不可以靜靜地給一個空白帳號（2026-09-19 使用者回報）。
//
// 回報的症狀是：「之前註冊過的帳號登入後直接歸零，而且沒有重新看見註冊流程。」
// 那個組合很有指向性 —— 正常路徑上「資料歸零」與「回到註冊流程」是綁在一起的
// （`hydrate` 讀不到存檔時，兩件事在同一個 else 分支裡發生）。兩者只出現一件，
// 表示走的是第三條路。
//
// 那條路是：`applySnapshot` 對不上 `v` 時「整份忽略並回傳 false」，
// 而 `hydrate` **沒有檢查那個回傳值**。後果是一串，而且沒有任何一步會報錯：
//
//   ① 使用者拿到一個全新的 AppState；
//   ② `signUpCompleted` 是欄位預設的 true → **看不到註冊流程**；
//   ③ 接了後端時 `demo` 為 false，所有集合都是空的 → 紀錄「歸零」；
//   ④ 300 毫秒後自動存檔把這份空白寫回雲端 → **真的清掉了**。
//
// 第 ④ 步才是最嚴重的：它把一個「讀取問題」變成「資料遺失」。

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/store.dart';
import 'package:fitness_app/state/app_state.dart';

Future<MemoryStore> _storeWith(Map<String, dynamic> snapshot) async {
  final store = MemoryStore();
  await store.save(snapshot);
  return store;
}

void main() {
  group('版本對不上', () {
    test('停在讀取失敗，不是給一個空白帳號', () async {
      final store = await _storeWith(AppState().toSnapshot()..['v'] = 1);
      final s = AppState(demo: false);
      await s.hydrate(store);

      expect(s.hydration, HydrationPhase.failed);
      expect(s.hydrationError, isNotNull);
      expect(s.hydrationError!.reason, contains('版本'));
    });

    test('**原始存檔一個位元都沒被動到** —— 這是最要緊的一條', () async {
      // 少了這道檢查，自動存檔會在 300ms 後把空白寫回去。
      // 那時使用者的訓練紀錄、能力值、金幣就真的沒了。
      final original = AppState().toSnapshot()..['v'] = 1;
      final store = await _storeWith(original);
      final s = AppState(demo: false);
      await s.hydrate(store);

      // 即使呼叫端硬要存，也存不進去 —— _hydrated 維持 false。
      await s.saveNow();

      final still = (await store.load())!;
      expect(still['v'], 1, reason: '存檔還是原來那一份');
      expect(still['totalExp'], original['totalExp']);
      expect(still['coins'], original['coins']);
    });

    test('沒有靜靜地跳過註冊流程', () async {
      // 症狀的另一半：使用者沒看到註冊流程，因為 signUpCompleted
      // 停在欄位預設的 true。現在整個畫面是錯誤頁，不會走到那個判斷。
      final store = await _storeWith(AppState().toSnapshot()..['v'] = 1);
      final s = AppState(demo: false);
      await s.hydrate(store);
      expect(s.hydration, isNot(HydrationPhase.ready));
    });
  });

  group('版本對得上', () {
    test('照常讀回來，而且會開始存檔', () async {
      final snap = AppState().toSnapshot();
      final store = await _storeWith(snap);
      final s = AppState(demo: false);
      await s.hydrate(store);

      expect(s.hydration, HydrationPhase.ready);
      expect(s.totalExp, snap['totalExp']);
      expect(s.signUpCompleted, isTrue);
    });

    test('真的沒存過就回到註冊流程，並且歸零', () async {
      // 這才是「歸零」該發生的時機 —— 而且一定伴隨註冊流程。
      final s = AppState(demo: false);
      await s.hydrate(MemoryStore());

      expect(s.hydration, HydrationPhase.ready);
      expect(s.signUpCompleted, isFalse, reason: '歸零就要看得到註冊流程');
      expect(s.totalExp, 0);
    });
  });
}
