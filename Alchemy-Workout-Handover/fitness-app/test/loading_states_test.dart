import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/design/components.dart';
import 'package:fitness_app/design/error_state.dart';
import 'package:fitness_app/design/skeleton.dart';
import 'package:fitness_app/screens/design/state_gallery_screen.dart';
import 'package:fitness_app/state/app_state.dart';
import 'package:fitness_app/widgets/load_boundary.dart';

/// 骨架屏顯示期間**不可用 pumpAndSettle** —— 掃光是重複播放的動畫，
/// 永遠等不到穩定狀態。本檔一律用 pump(duration)。
Widget host(AppState s, Widget child) => AppScope(
      state: s,
      child: MaterialApp(home: Scaffold(body: child)),
    );

Widget boundary({int rows = 3, bool landing = false}) => LoadBoundary(
      id: 'x',
      kind: SkeletonKind.listA,
      rows: rows,
      landing: landing,
      builder: (_) => const Text('真的內容'),
    );

void main() {
  group('載入邊界', () {
    testWidgets('預設不模擬載入 —— 假資料就在記憶體裡，不平白讓人等', (t) async {
      final s = AppState();
      expect(s.demoLoadMs, 0);
      await t.pumpWidget(host(s, boundary()));
      await t.pump();
      expect(find.text('真的內容'), findsOneWidget);
      expect(find.byType(Skeleton), findsNothing);
    });

    testWidgets('開啟後首次進入顯示骨架屏，時間到才換成內容', (t) async {
      final s = AppState()..demoLoadMs = 900;
      await t.pumpWidget(host(s, boundary()));
      await t.pump();
      expect(find.byType(Skeleton), findsOneWidget);
      expect(find.text('真的內容'), findsNothing);

      await t.pump(const Duration(milliseconds: 1000));
      expect(find.byType(Skeleton), findsNothing);
      expect(find.text('真的內容'), findsOneWidget);
    });

    testWidgets('骨架屏只給首次載入 —— 回到同一頁不再骨架一次', (t) async {
      final s = AppState()..demoLoadMs = 900;
      await t.pumpWidget(host(s, boundary()));
      await t.pump(const Duration(milliseconds: 1000));
      expect(s.hasLoadedOnce('x'), isTrue);

      // 重新掛載同一個邊界
      await t.pumpWidget(host(s, const SizedBox()));
      await t.pumpWidget(host(s, boundary()));
      await t.pump();
      expect(find.byType(Skeleton), findsNothing);
      expect(find.text('真的內容'), findsOneWidget);
    });

    testWidgets('模擬離線走錯誤頁，重試後回到內容', (t) async {
      final s = AppState()
        ..demoLoadMs = 900
        ..demoOffline = true;
      await t.pumpWidget(host(s, boundary()));
      await t.pump(const Duration(milliseconds: 1000));
      expect(find.byType(ErrorState), findsOneWidget);
      expect(find.text('重新載入'), findsOneWidget);

      s.demoOffline = false;
      await t.tap(find.text('重新載入'));
      await t.pump();
      expect(find.byType(Skeleton), findsOneWidget, reason: '重試要重新走一次載入');
      await t.pump(const Duration(milliseconds: 1000));
      expect(find.text('真的內容'), findsOneWidget);
    });

    testWidgets('錯誤必須有文字，不可只靠紅色', (t) async {
      final s = AppState()
        ..demoLoadMs = 900
        ..demoOffline = true;
      await t.pumpWidget(host(s, boundary()));
      await t.pump(const Duration(milliseconds: 1000));
      expect(find.text('載入失敗'), findsOneWidget);
      expect(find.textContaining('檢查連線'), findsOneWidget);
    });

    testWidgets('著陸頁與次層頁的錯誤文案不同 —— 一個講連線，一個講這份清單', (t) async {
      final s = AppState()
        ..demoLoadMs = 900
        ..demoOffline = true;
      await t.pumpWidget(host(s, boundary(landing: true)));
      await t.pump(const Duration(milliseconds: 1000));
      expect(find.text('暫時連不上'), findsOneWidget);
      expect(find.text('載入失敗'), findsNothing);
    });
  });

  group('六種骨架不共用形狀', () {
    Future<void> show(WidgetTester t, SkeletonKind k, int rows) async {
      await t.pumpWidget(host(
        AppState(),
        SingleChildScrollView(child: Skeleton(kind: k, rows: rows)),
      ));
      await t.pump();
    }

    testWidgets('A 清單型有頭像圓，B 卡片列表型沒有', (t) async {
      await show(t, SkeletonKind.listA, 6);
      expect(find.byType(SkeletonCircle), findsNWidgets(6));
      await show(t, SkeletonKind.cardListB, 2);
      expect(find.byType(SkeletonCircle), findsNothing);
    });

    testWidgets('C 卡片格狀型是兩欄 —— 三列就是六張', (t) async {
      await show(t, SkeletonKind.gridC, 3);
      expect(find.byType(SkeletonBox), findsNWidgets(6));
    });

    testWidgets('D 對話型的泡泡左右交錯', (t) async {
      await show(t, SkeletonKind.chatD, 4);
      final rows = t.widgetList<Row>(find.byType(Row)).toList();
      final aligns = rows.map((r) => r.mainAxisAlignment).toSet();
      expect(aligns.contains(MainAxisAlignment.start), isTrue);
      expect(aligns.contains(MainAxisAlignment.end), isTrue);
    });

    testWidgets('E 詳情型的段落最後一條為 60%，模擬段落結尾', (t) async {
      await show(t, SkeletonKind.detailE, 3);
      final bars = t
          .widgetList<SkeletonBar>(find.byType(SkeletonBar))
          .map((b) => b.widthFactor)
          .toList();
      expect(bars.contains(0.6), isTrue);
    });

    testWidgets('F 圖表型畫的是六邊形，不是清單條', (t) async {
      await show(t, SkeletonKind.chartF, 4);
      expect(find.byType(CustomPaint), findsWidgets);
      expect(find.byType(SkeletonCircle), findsNothing);
    });
  });

  group('空狀態的文案規則', () {
    testWidgets('型錄裡四個空狀態都說明了為什麼是空的，且都給了下一步', (t) async {
      await t.pumpWidget(host(AppState(), const StateGalleryScreen()));
      await t.pump();
      expect(kGalleryEmptyStates.length, 4,
          reason: 'E 詳情型與 F 圖表型不需要空狀態');
      for (final e in kGalleryEmptyStates) {
        final st = e.$4;
        expect(st.title, isNot(contains('暫無資料')));
        expect(st.message.length, greaterThan(6), reason: '要說明為什麼是空的');
        expect(st.action, isNotNull, reason: '必須提供一個下一步');
      }
    });

    testWidgets('行動按鈕寬度依內容，不是拉滿整列', (t) async {
      await t.pumpWidget(host(
        AppState(),
        const EmptyState(
          icon: Icons.inbox_outlined,
          title: '信箱是空的',
          message: '完成任務或成就後，獎勵會寄到這裡',
          action: AppButton(label: '看看今天的任務', kind: BtnKind.secondary),
        ),
      ));
      await t.pump();
      final w = t.getSize(find.byType(AppButton)).width;
      final page = t.getSize(find.byType(EmptyState)).width;
      expect(w, greaterThanOrEqualTo(120));
      expect(w, lessThan(page - 2 * 32), reason: '拉滿會看起來像頁面的主 CTA');
    });
  });

  group('型錄', () {
    testWidgets('十二張都列得出來', (t) async {
      t.view.physicalSize = const Size(393 * 3, 852 * 3);
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(host(AppState(), const StateGalleryScreen()));
      await t.pump();
      for (final n in skeletonKindNames.values) {
        expect(find.text(n), findsOneWidget);
      }
      await t.scrollUntilVisible(find.text('E2 著陸頁'), 200);
      await t.pump();
      expect(find.text('E1 次層頁'), findsOneWidget);
      expect(find.text('E2 著陸頁'), findsOneWidget);
    });

    testWidgets('點進 A 清單型看得到骨架', (t) async {
      t.view.physicalSize = const Size(393 * 3, 852 * 3);
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(AppScope(
        state: AppState(),
        child: const MaterialApp(home: StateGalleryScreen()),
      ));
      await t.pump();
      await t.tap(find.text('A 清單型'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.byType(Skeleton), findsOneWidget);
      expect(find.text('對話'), findsOneWidget, reason: '骨架要放在真的外殼裡才看得出對不對齊');
    });
  });
}
