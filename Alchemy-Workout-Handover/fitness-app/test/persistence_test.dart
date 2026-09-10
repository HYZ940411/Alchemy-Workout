import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/store.dart';
import 'package:fitness_app/data/store_io.dart';

import 'store_contract.dart';
import 'package:fitness_app/domain/ability.dart';
import 'package:fitness_app/domain/commerce.dart';
import 'package:fitness_app/domain/models.dart';
import 'package:fitness_app/domain/platform_config.dart';
import 'package:fitness_app/domain/rewards.dart';
import 'package:fitness_app/main.dart';
import 'package:fitness_app/screens/boot_screen.dart';
import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/state/app_state.dart';

const kBase = Size(393 * 3, 852 * 3);

/// 把 [s] 的狀態經由 [store] 存讀一輪，回傳新的一份 AppState。
Future<AppState> _roundTrip(AppState s, MemoryStore store) async {
  await s.saveNow();
  final next = AppState();
  await next.hydrate(store);
  return next;
}

/// 一個**已經有帳號**、且接上存檔的 AppState。
///
/// 這一組測試驗的是「存讀一輪，已取得的東西不消失」，前提是有東西可存。
/// 空的 store 現在代表「這台裝置還沒有帳號」，會被歸零 ——
/// 所以要先放一份存檔進去，才是這些測試真正要驗的情境。
Future<AppState> _connected(MemoryStore store) async {
  if (await store.load() == null) await store.save(AppState().toSnapshot());
  final s = AppState();
  await s.hydrate(store);
  return s;
}

void main() {
  setUp(platformConfig.reset);
  tearDown(platformConfig.reset);

  group('存讀一輪，進度不變', () {
    test('經濟與進度', () async {
      final store = MemoryStore();
      final s = await _connected(store);
      s.coins = 1234;
      s.totalExp = 5678;
      s.trainingStreakDays = 9;
      s.totalWorkouts = 77;
      s.makeupTickets = 4;
      s.aiPermanent = 3;

      final back = await _roundTrip(s, store);
      expect(back.coins, 1234);
      expect(back.totalExp, 5678);
      expect(back.rank, s.rank);
      expect(back.trainingStreakDays, 9);
      expect(back.totalWorkouts, 77);
      expect(back.makeupTickets, 4);
      expect(back.aiPermanent, 3);
    });

    test('六維能力值與待兌現實測值', () async {
      final store = MemoryStore();
      final s = await _connected(store);
      s.points[Dim.chest] = 512;
      s.pending[Dim.legs] = 88;

      final back = await _roundTrip(s, store);
      expect(back.points[Dim.chest], 512);
      expect(back.pending[Dim.legs], 88);
    });

    test('退步計時器 —— 不然重開就等於重新開始計時', () async {
      final store = MemoryStore();
      final s = await _connected(store);
      s.advanceDemoClock(const Duration(days: 12));
      final before = {
        for (final e in s.decayTimers.entries) e.key: e.value.cumulative,
      };

      final back = await _roundTrip(s, store);
      for (final d in Dim.values) {
        expect(back.decayTimers[d]!.cumulative, before[d]);
        expect(back.decayTimers[d]!.lastTrainedDate,
            s.decayTimers[d]!.lastTrainedDate);
      }
    });

    test('示範時鐘的位移', () async {
      final store = MemoryStore();
      final s = await _connected(store);
      s.advanceDemoClock(const Duration(days: 30));
      final back = await _roundTrip(s, store);
      expect(back.demoClockOffset.inDays, 30);
    });
  });

  group('存讀一輪，已取得的東西不消失', () {
    test('已購買的進階計畫', () async {
      final store = MemoryStore();
      final s = await _connected(store);
      final p = s.platformPlans.firstWhere((p) => p.unlockCoins != null);
      s.coins = 10000;
      s.purchasePlan(p);

      final back = await _roundTrip(s, store);
      expect(back.purchasedPlanIds, contains(p.id));
      expect(back.planUnlocked(p), isTrue);
    });

    test('成就的解鎖與領取狀態', () async {
      final store = MemoryStore();
      final s = await _connected(store);
      final a = s.achievements.firstWhere((a) => a.unlocked && !a.claimed);
      s.claimAchievement(a);

      final back = await _roundTrip(s, store);
      final same = back.achievements.firstWhere(
          (x) => x.category == a.category && x.threshold == a.threshold);
      expect(same.unlocked, isTrue);
      expect(same.claimed, isTrue);
    });

    test('已解鎖紀錄為單調遞增：當前進度掉下來也不撤銷', () async {
      final s = AppState();
      final a =
          s.achievements.firstWhere((a) => a.category == '累積訓練' && !a.unlocked);
      s.totalWorkoutDays = a.threshold;
      s.checkIn(); // 順帶觸發成就同步
      expect(a.unlocked, isTrue);

      // 手動把存檔裡的進度改低，模擬「解鎖過但當前值對不上」。
      final snap = s.toSnapshot();
      snap['totalWorkoutDays'] = 0;

      final back = AppState();
      expect(back.applySnapshot(snap), isTrue);
      final same = back.achievements.firstWhere(
          (x) => x.category == a.category && x.threshold == a.threshold);
      expect(same.unlocked, isTrue, reason: '一經解鎖不可撤銷');
      expect(back.totalWorkoutDays, 0);
    });

    test('訓練歷史 —— 逐組實績要留著，下次才帶得入', () async {
      final store = MemoryStore();
      final s = await _connected(store);
      s.history.clear();
      final plan = s.platformPlans.firstWhere(
          (p) => p.exercises.any((e) => e.exercise.id == 'bench'));
      s.startWorkout(plan);
      s.session!.records[0][0].weight = 57.5;
      s.completeCurrentSet();
      s.finishWorkout(EndKind.endedEarly);

      final back = await _roundTrip(s, store);
      expect(back.history.length, 1);
      final last = back.lastActualSets(s.history.first.exercises.first.id!);
      expect(last, isNotEmpty);
      expect(last.first.weight, 57.5);
    });

    test('獎勵信箱與領取狀態', () async {
      final store = MemoryStore();
      final s = await _connected(store);
      for (final t in s.dailyTasks) {
        t.progress = t.target;
      }
      s.advanceDemoClock(const Duration(days: 1));
      final n = s.mailbox.where((m) => m.source == '每日任務未領取').length;
      expect(n, greaterThan(0));

      final back = await _roundTrip(s, store);
      expect(back.mailbox.where((m) => m.source == '每日任務未領取').length, n);
    });

    test('自建動作', () async {
      final store = MemoryStore();
      final s = await _connected(store);
      final made = s.createCustomExercise(const Exercise(
        id: 'my_lateral',
        name: '我的側平舉',
        dim: Dim.shoulders,
        relativeIntensity: 1.0,
        equipment: '啞鈴',
        isCustom: true,
      ));
      expect(made, isTrue);

      final back = await _roundTrip(s, store);
      expect(back.myExercises.map((e) => e.name), contains('我的側平舉'));
      expect(back.myExercises.firstWhere((e) => e.name == '我的側平舉').isCustom,
          isTrue);
    });

    test('會員狀態與到期日', () async {
      final store = MemoryStore();
      final s = await _connected(store);
      s.subscribe(yearly: true);
      s.cancelSubscription();

      final back = await _roundTrip(s, store);
      expect(back.membership, MembershipState.cancelledPending);
      expect(back.membershipExpiry, s.membershipExpiry);
      expect(back.isMember, isTrue);
    });
  });

  group('存讀一輪，防刷的當日計數也要留著', () {
    test('同一天重開 App 不會讓訓練獎勵金幣再拿一次', () async {
      final store = MemoryStore();
      final s = await _connected(store);
      s.startWorkout(s.platformPlans.first);
      s.completeCurrentSet();
      final first = s.finishWorkout(EndKind.completed);
      expect(first.rewards.coins, greaterThan(0));

      final back = await _roundTrip(s, store);
      final coins = back.coins;
      back.startWorkout(back.platformPlans.first);
      back.completeCurrentSet();
      final second = back.finishWorkout(EndKind.completed);
      expect(second.rewards.coins, 0, reason: '重開 App 不是新的一天');
      expect(back.coins, coins);
    });

    test('同一天重開 App 不會讓簽到再簽一次', () async {
      final store = MemoryStore();
      final s = await _connected(store);
      s.checkIn();
      expect(s.checkedInToday, isTrue);

      final back = await _roundTrip(s, store);
      expect(back.checkedInToday, isTrue);
      final coins = back.coins;
      back.checkIn();
      expect(back.coins, coins);
    });

    test('互動獎勵的每日上限也跨得過重開', () async {
      final store = MemoryStore();
      final s = await _connected(store);
      final cap = platformConfig.i('reward', 'capLike');
      // 逐篇不同 —— 同一篇只發一次獎勵，循環按同一批吃不滿上限。
      final seeded = <Post>[];
      for (var i = 0; i < cap; i++) {
        final p = Post(
          id: 'keep-$i',
          author: '路人$i',
          authorRank: 20,
          text: '第 $i 篇',
          at: s.now,
        );
        s.posts.insert(0, p);
        seeded.add(p);
        s.toggleLike(p);
      }
      expect(s.interactionsToday('Like'), cap);

      final back = await _roundTrip(s, store);
      expect(back.interactionsToday('Like'), cap);
      // 請求識別碼也要跟著存檔走，否則重開 App 就能對同一篇再領一次。
      expect(back.rewardedRequests, containsAll(
          [for (final p in seeded) 'Like:${p.id}']));
    });
  });

  group('壞掉的存檔不該讓 App 開不起來', () {
    test('版本不符：整份忽略，沿用初始狀態', () async {
      final s = AppState();
      final coins = s.coins;
      expect(s.applySnapshot({'v': 999, 'coins': 1}), isFalse);
      expect(s.coins, coins);
    });

    test('欄位型別亂掉：能認的認，不能認的沿用原值', () async {
      final s = AppState();
      final exp = s.totalExp;
      final ok = s.applySnapshot({
        'v': kSnapshotVersion,
        'coins': 99,
        'totalExp': '不是數字',
        'points': '也不是 Map',
      });
      expect(ok, isTrue);
      expect(s.coins, 99);
      expect(s.totalExp, exp);
    });

    test('空存檔：照常啟動，而且是一個乾淨的新帳號', () async {
      // 空的 store ＝ 這台裝置還沒有帳號。原本這裡斷言「金幣 > 0」，
      // 那是拿示範資料當「有開起來」的替身；現在正確的期待是
      // **開得起來，而且身上沒有別人的東西**。
      final s = AppState();
      await s.hydrate(MemoryStore());
      expect(s.hydration, HydrationPhase.ready);
      expect(s.signUpCompleted, isFalse);
      expect(s.coins, 0);
      expect(s.rank, 1);
    });
  });

  group('寫入時機', () {
    test('讀完之前不寫 —— 否則初始狀態會蓋掉存檔', () async {
      // 存檔裡是 4321。讀取還沒回來的那段期間若有人改了狀態並存檔，
      // 假資料的 640 就會把 4321 蓋掉。
      final store = _SlowStore(const Duration(milliseconds: 600));
      await store.save({...AppState().toSnapshot(), 'coins': 4321});
      store.saves = 0;

      final s = AppState();
      final loading = s.hydrate(store);
      // 讀取進行中：這時候的變動不該觸發存檔。
      s.coins = 640;
      s.notifyListeners();
      // 等超過防抖的 300ms —— 若沒有 hydrate 這道閘，這時候已經寫下去了。
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(store.saves, 0, reason: '還沒讀完就不該寫');

      await loading;
      expect(s.coins, 4321, reason: '存檔沒有被初始狀態蓋掉');
    });

    test('狀態一變就排存檔，連續變動合併成一次', () async {
      final store = MemoryStore();
      final s = await _connected(store);
      final before = store.saves;
      for (var i = 0; i < 20; i++) {
        s.coins = i;
        s.notifyListeners();
      }
      expect(store.saves, before, reason: '防抖期間還沒寫');
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(store.saves, before + 1, reason: '20 次變動只寫一次');
    });

    test('clearSaved 清掉存檔', () async {
      final store = MemoryStore();
      final s = await _connected(store);
      s.coins = 4321;
      await s.saveNow();
      expect(await store.load(), isNotNull);
      await s.clearSaved();
      expect(await store.load(), isNull);
    });
  });

  group('端到端（畫面）', () {
    testWidgets('App 重開後金幣與階級不變', (t) async {
      t.view.physicalSize = kBase;
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);

      // 先放一份「已完成註冊」的存檔。空的 store 現在代表
      // 「這台裝置還沒有帳號」，會被導去註冊流程 ——
      // 而這支要驗的是重開之後資料還在，與首次啟動無關。
      final store = MemoryStore();
      await store.save(AppState().toSnapshot());

      await t.pumpWidget(FitnessApp(store: store));
      await t.pumpAndSettle();

      // 簽到一次，金幣與經驗值都會動。
      await t.tap(find.text('簽到　經驗值 10 ＋ 金幣 10'));
      await t.pumpAndSettle();
      expect(find.text('已簽到'), findsWidgets);
      await t.pump(const Duration(milliseconds: 400));

      // 換一個全新的 App 實例，接同一份存檔。
      await t.pumpWidget(FitnessApp(store: store));
      await t.pumpAndSettle();
      expect(find.text('已簽到'), findsWidgets,
          reason: '重開之後不該又變成「今天還沒簽到」');
    });
  });

  _bootGate();
  _fileStore();
}


/// 讀取會慢一拍的 Store，用來驗「讀完之前不寫」。
class _SlowStore extends MemoryStore {
  final Duration delay;
  _SlowStore(this.delay);

  @override
  Future<Map<String, dynamic>?> load() async {
    await Future<void>.delayed(delay);
    return super.load();
  }
}

/// 讀存檔期間不讓主畫面畫出來，讀不出來時不靜靜改用假資料。
void _bootGate() {
  group('讀存檔期間不讓人對著假資料操作', () {
    test('hydrate 一開始就進入 loading，第一次 build 就看得到', () {
      final s = AppState();
      expect(s.hydration, HydrationPhase.ready, reason: '沒接儲存就直接可用');
      final store = _SlowStore(const Duration(milliseconds: 200));
      s.hydrate(store); // 不 await：同步段就要設好
      expect(s.hydration, HydrationPhase.loading);
    });

    test('讀完才轉 ready', () async {
      final store = MemoryStore();
      final s = AppState();
      await s.hydrate(store);
      expect(s.hydration, HydrationPhase.ready);
    });

    testWidgets('載入期間畫的是載入中，不是主畫面', (t) async {
      t.view.physicalSize = kBase;
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);

      final store = _SlowStore(const Duration(milliseconds: 300));
      await store.save({...AppState().toSnapshot(), 'coins': 4321});

      await t.pumpWidget(FitnessApp(store: store));
      await t.pump();
      expect(find.byType(BootLoading), findsOneWidget);
      // 主畫面的任何東西都不該在這時候出現 —— 出現就按得到。
      expect(find.text('簽到　經驗值 10 ＋ 金幣 10'), findsNothing);

      await t.pumpAndSettle(const Duration(milliseconds: 500));
      expect(find.byType(BootLoading), findsNothing);
      expect(find.textContaining('4321'), findsWidgets);
    });
  });

  group('載入期間的操作不會被無聲蓋掉（原始缺陷）', () {
    testWidgets('讀取還沒回來時，簽到鈕根本按不到', (t) async {
      t.view.physicalSize = kBase;
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);

      final store = _SlowStore(const Duration(milliseconds: 300));
      final seed = AppState()..coins = 4321;
      await store.save(seed.toSnapshot());

      await t.pumpWidget(FitnessApp(store: store));
      await t.pump(const Duration(milliseconds: 50));
      // 缺陷版本在這裡已經畫出主畫面，使用者按得到簽到，
      // 而那次簽到會在 300ms 後被存檔整份蓋掉。
      expect(find.text('簽到　經驗值 10 ＋ 金幣 10'), findsNothing);

      await t.pumpAndSettle(const Duration(milliseconds: 500));
      expect(find.textContaining('4321'), findsWidgets);
    });
  });

  group('存檔讀不出來', () {
    test('停在 failed，不自動改用假資料', () async {
      final store = MemoryStore()
        ..failWith = const StoreLoadException('壞了', backupPath: '/tmp/x.bad');
      final s = AppState();
      await s.hydrate(store);
      expect(s.hydration, HydrationPhase.failed);
      expect(s.hydrationError?.backupPath, '/tmp/x.bad');
    });

    test('失敗期間不寫檔 —— 否則會把存檔換成一份假資料', () async {
      final store = MemoryStore()..failWith = const StoreLoadException('壞了');
      final s = AppState();
      await s.hydrate(store);
      s.coins = 1;
      s.notifyListeners();
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(store.saves, 0);
    });

    test('重試成功即進得去', () async {
      final store = MemoryStore()..failWith = const StoreLoadException('壞了');
      final s = AppState();
      await s.hydrate(store);
      expect(s.hydration, HydrationPhase.failed);

      store.failWith = null;
      await store.save({...AppState().toSnapshot(), 'coins': 777});
      await s.retryHydration();
      expect(s.hydration, HydrationPhase.ready);
      expect(s.coins, 777);
    });

    test('選擇先用示範資料進去，之後才開始存檔', () async {
      final store = MemoryStore()..failWith = const StoreLoadException('壞了');
      final s = AppState();
      await s.hydrate(store);
      s.continueWithoutSave();
      expect(s.hydration, HydrationPhase.ready);

      s.coins = 55;
      s.notifyListeners();
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(store.saves, 1, reason: '使用者自己決定放棄之後才存');
    });

    testWidgets('錯誤頁講得出發生什麼事，且兩條出口都在', (t) async {
      t.view.physicalSize = kBase;
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);

      final store = MemoryStore()
        ..failWith = const StoreLoadException('壞了', backupPath: '/tmp/x.bad');
      await t.pumpWidget(FitnessApp(store: store));
      await t.pumpAndSettle();

      expect(find.text('讀不到你的進度'), findsOneWidget);
      // 使用者第一個念頭一定是「我的資料是不是沒了」，那句話必須在。
      expect(find.textContaining('沒有被清空'), findsOneWidget);
      expect(find.text('再試一次'), findsOneWidget);
      expect(find.text('先用示範資料進去'), findsOneWidget);

      await t.tap(find.text('先用示範資料進去'));
      await t.pumpAndSettle();
      expect(find.text('讀不到你的進度'), findsNothing);
      expect(t.takeException(), isNull);
    });
  });
}

/// FileStore 是真正跑在使用者機器上的那一份，不能只驗 MemoryStore。
void _fileStore() {
  group('FileStore', () {
    late Directory dir;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('fitness_store_test');
    });
    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    FileStore make() => FileStore(directory: () async => dir);

    // 與瀏覽器版共用的同一份契約。下面那些 test 是檔案版**專屬**的
    // （暫存檔、原檔改名到磁碟上），共通的行為一律走契約，
    // 兩邊才不會各寫各的、悄悄分岔。
    runStoreContract(
      'FileStore',
      make: make,
      writeRaw: (t) => File('${dir.path}/state.json').writeAsString(t),
      readRaw: () async {
        final f = File('${dir.path}/state.json');
        return await f.exists() ? f.readAsString() : null;
      },
    );

    test('沒存過回傳 null，不是錯誤', () async {
      expect(await make().load(), isNull);
    });

    test('存了讀得回來', () async {
      final store = make();
      await store.save({'v': kSnapshotVersion, 'coins': 99});
      expect((await store.load())!['coins'], 99);
    });

    test('空檔等同沒存過', () async {
      await File('${dir.path}/state.json').writeAsString('   ');
      expect(await make().load(), isNull);
    });

    test('內容壞掉：丟錯誤，不當成沒存過', () async {
      await File('${dir.path}/state.json').writeAsString('{壞掉的 json');
      expect(make().load(), throwsA(isA<StoreLoadException>()));
    });

    test('壞掉的原檔改名保留，不直接刪掉', () async {
      final f = File('${dir.path}/state.json');
      await f.writeAsString('{壞掉的 json');
      try {
        await make().load();
        fail('應該要丟錯誤');
      } on StoreLoadException catch (e) {
        expect(e.backupPath, isNotNull);
        expect(await File(e.backupPath!).exists(), isTrue);
        expect(await File(e.backupPath!).readAsString(), '{壞掉的 json');
        expect(await f.exists(), isFalse);
      }
    });

    test('JSON 合法但不是一份存檔，同樣視為壞掉', () async {
      await File('${dir.path}/state.json').writeAsString('[1, 2, 3]');
      expect(make().load(), throwsA(isA<StoreLoadException>()));
    });

    test('寫入是先寫暫存檔再改名，不留半截檔', () async {
      final store = make();
      await store.save({'v': kSnapshotVersion, 'coins': 1});
      final names = dir.listSync().map((e) => e.path.split('/').last).toList();
      expect(names, ['state.json'], reason: '.tmp 不該留下來');
    });

    test('clear 刪掉存檔', () async {
      final store = make();
      await store.save({'v': kSnapshotVersion});
      await store.clear();
      expect(await store.load(), isNull);
    });
  });
}
