// 離線緩存三件事（2026-10-16 使用者同意補，設計見 PROGRESS 3Y）：
//
// 1. Web 打開 Firestore 持久快取 —— 斷網期間的寫入重新整理後還在。
// 2. 資料送出超過 3 秒還沒完成 → 畫面頂端出現「離線中或網路不穩 · 資料尚未同步」。
// 3. 登出不卡住 —— 離線時 saveNow 永遠不會回來，原本直接 await 會卡死。
//
// 沒有可斷網的環境：用「save 永遠不完成」的假 Store 模擬 Firestore 離線時的行為。

import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart'
    show FirebaseFirestore, Settings, WebPersistentMultipleTabManager;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/firestore_setup.dart';
import 'package:fitness_app/data/store.dart';
import 'package:fitness_app/main.dart';
import 'package:fitness_app/state/app_state.dart';
import 'package:fitness_app/widgets/sync_status_banner.dart';

/// 離線時的 Firestore：寫入「送出去了」，但要等連上網才完成。
class _OfflineStore extends MemoryStore {
  final hung = <Completer<void>>[];
  bool offline = true;

  @override
  Future<void> save(Map<String, dynamic> data) {
    if (!offline) return super.save(data);
    final c = Completer<void>();
    hung.add(c);
    return c.future;
  }

  /// 連上網：之前卡住的寫入一併完成。
  void reconnect() {
    offline = false;
    for (final c in hung) {
      if (!c.isCompleted) c.complete();
    }
    hung.clear();
  }
}

/// 只記下被設定了什麼的 Firestore（假資料庫不支援 `settings =`）。
class _RecordingDb implements FirebaseFirestore {
  Settings? got;

  @override
  set settings(Settings value) => got = value;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

Future<AppState> _hydrated(Store st) async {
  final s = AppState(demo: false);
  await s.hydrate(st);
  return s;
}

void main() {
  group('① Firestore 持久快取設定', () {
    test('設定函式打開持久快取並用多分頁管理', () {
      final db = _RecordingDb();
      configureFirestorePersistence(db);
      expect(db.got, isNotNull, reason: '根本沒設定就等於用預設值（Web 預設不持久）');
      expect(db.got!.persistenceEnabled, isTrue);
      expect(
        db.got!.webPersistentTabManager,
        isA<WebPersistentMultipleTabManager>(),
        reason: '同帳號開兩個分頁，第二個不該退回無快取',
      );
    });

    test('診斷用開關：網址帶 ?nopersist=1 才關，其他一律開', () {
      expect(persistenceWanted(Uri.parse('https://x.web.app/')), isTrue);
      expect(persistenceWanted(Uri.parse('https://x.web.app/?a=1')), isTrue);
      expect(
        persistenceWanted(Uri.parse('https://x.web.app/?nopersist=1')),
        isFalse,
      );
      expect(
        persistenceWanted(Uri.parse('https://x.web.app/?nopersist=0')),
        isTrue,
      );
    });

    test('診斷用開關：網址帶 ?nosettings=1 才完全不碰設定，其他一律照常設定', () {
      expect(touchFirestoreSettings(Uri.parse('https://x.web.app/')), isTrue);
      expect(
        touchFirestoreSettings(Uri.parse('https://x.web.app/?nopersist=1')),
        isTrue,
        reason: 'nopersist 只是關持久，還是會呼叫 settings =',
      );
      expect(
        touchFirestoreSettings(Uri.parse('https://x.web.app/?nosettings=1')),
        isFalse,
      );
    });

    test('關掉時明確設成不持久（不是不設定）', () {
      final db = _RecordingDb();
      configureFirestorePersistence(db, enabled: false);
      expect(db.got, isNotNull);
      expect(db.got!.persistenceEnabled, isFalse);
    });

    test('main 在 Firebase 初始化之後、用到 Firestore 之前呼叫它', () {
      final src = File('lib/main.dart').readAsStringSync();
      final init = src.indexOf('Firebase.initializeApp(');
      final cfg = src.indexOf('configureFirestorePersistence(');
      final run = src.indexOf('runApp(');
      expect(init, isNot(-1));
      expect(cfg, isNot(-1), reason: '沒呼叫就等於沒打開，Web 上斷網寫入重新整理就沒了');
      expect(cfg, greaterThan(init));
      expect(cfg, lessThan(run));
    });
  });

  group('② 離線提示（狀態）', () {
    testWidgets('送出超過 3 秒還沒完成 → 亮；送完 → 滅', (t) async {
      final st = _OfflineStore()..offline = false;
      final s = await _hydrated(st);
      st.offline = true;

      unawaited(s.saveNow());
      await t.pump(const Duration(seconds: 2));
      expect(s.syncStalled, isFalse, reason: '才 2 秒，還不能說離線');
      await t.pump(const Duration(milliseconds: 1100));
      expect(s.syncStalled, isTrue, reason: '超過 3 秒還沒送完');

      st.reconnect();
      await t.pump();
      expect(s.syncStalled, isFalse, reason: '連上網、送完就自己消失');
    });

    testWidgets('正常很快就送完的，永遠不會亮', (t) async {
      final s = await _hydrated(_OfflineStore()..offline = false);
      for (var i = 0; i < 5; i++) {
        await s.saveNow();
        await t.pump(const Duration(seconds: 5));
      }
      expect(s.syncStalled, isFalse);
    });

    testWidgets('提示亮滅不會自己排新的存檔（否則離線時一直產生新存檔）', (t) async {
      final st = _OfflineStore()..offline = false;
      final s = await _hydrated(st);
      st.offline = true;
      unawaited(s.saveNow());
      await t.pump(const Duration(milliseconds: 300));
      final before = st.hung.length;
      await t.pump(const Duration(seconds: 4));
      expect(s.syncStalled, isTrue, reason: '前提');
      expect(st.hung.length, before, reason: '亮起來這件事不能再觸發存檔，不然離線時會越堆越多');
    });
  });

  group('② 離線提示（畫面）', () {
    testWidgets('停滯時整個 App 最上方出現提示；送完就消失', (t) async {
      t.view.physicalSize = const Size(393 * 3, 852 * 3);
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final st = _OfflineStore()..offline = false;
      await st.save(AppState().toSnapshot());
      await t.pumpWidget(FitnessApp(store: st));
      await t.pump(const Duration(seconds: 1));
      final s = AppScope.of(t.element(find.byType(MaterialApp)));
      expect(find.text(SyncStatusBanner.text), findsNothing);

      st.offline = true;
      unawaited(s.saveNow());
      await t.pump(const Duration(seconds: 4));
      expect(find.text(SyncStatusBanner.text), findsOneWidget);

      st.reconnect();
      await t.pump();
      await t.pump();
      expect(find.text(SyncStatusBanner.text), findsNothing);
    });

    testWidgets('提示不擋點擊', (t) async {
      await t.pumpWidget(
        AppScope(
          state: AppState()..syncStalled = true,
          child: MaterialApp(
            builder: (c, child) =>
                Stack(children: [?child, const SyncStatusBanner()]),
            home: Scaffold(
              body: Align(
                alignment: Alignment.topCenter,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => tapped = true,
                  child: const SizedBox(width: 200, height: 40),
                ),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.byType(GestureDetector));
      expect(tapped, isTrue, reason: '提示疊在上面，底下的按鈕仍要按得到');
      tapped = false;
    });
  });

  group('③ 登出不卡住', () {
    testWidgets('離線時 saveNowWithin 到時間就放棄，回 false，不會卡死', (t) async {
      final st = _OfflineStore()..offline = false;
      final s = await _hydrated(st);
      st.offline = true;
      bool? result;
      unawaited(
        s.saveNowWithin(const Duration(seconds: 3)).then((v) => result = v),
      );
      await t.pump(const Duration(seconds: 2));
      expect(result, isNull, reason: '還在等');
      await t.pump(const Duration(seconds: 2));
      expect(result, isFalse, reason: '原本直接 await saveNow 在這裡會永遠等下去');
    });

    testWidgets('連得上的時候回 true', (t) async {
      final s = await _hydrated(_OfflineStore()..offline = false);
      expect(await s.saveNowWithin(const Duration(seconds: 3)), isTrue);
    });

    testWidgets('資料送完 → 直接可以登出，不問', (t) async {
      final s = await _hydrated(_OfflineStore()..offline = false);
      var asked = false;
      final r = await s.flushForSignOut(
        askToForce: () async {
          asked = true;
          return true;
        },
      );
      expect(r, isTrue);
      expect(asked, isFalse);
    });

    testWidgets('資料沒送完、使用者仍要登出 → 回 false（放行，但知道資料沒送完）', (t) async {
      final st = _OfflineStore()..offline = false;
      final s = await _hydrated(st);
      st.offline = true;
      bool? r = true;
      var asked = 0;
      unawaited(
        s
            .flushForSignOut(
              askToForce: () async {
                asked++;
                return true;
              },
            )
            .then((v) => r = v),
      );
      await t.pump(const Duration(seconds: 4));
      expect(asked, 1);
      expect(r, isFalse);
    });

    testWidgets('資料沒送完、使用者選先不要 → 回 null（不登出）', (t) async {
      final st = _OfflineStore()..offline = false;
      final s = await _hydrated(st);
      st.offline = true;
      Object? r = 'unset';
      unawaited(
        s.flushForSignOut(askToForce: () async => false).then((v) => r = v),
      );
      await t.pump(const Duration(seconds: 4));
      expect(r, isNull);
    });

    test('設定頁登出走 flushForSignOut，並只在送完時才清本機快取', () {
      final src = File(
        'lib/screens/me/settings_screen.dart',
      ).readAsStringSync();
      expect(
        src,
        contains('flushForSignOut('),
        reason: '直接 await saveNow 離線時會卡死',
      );
      expect(src, isNot(contains('await state.saveNow();')));
      expect(
        src,
        contains('if (synced) await wipeLocalCacheAndReload('),
        reason: '沒送完就清快取，等於把還沒送出的變動一起丟掉',
      );
    });
  });
}

bool tapped = false;
