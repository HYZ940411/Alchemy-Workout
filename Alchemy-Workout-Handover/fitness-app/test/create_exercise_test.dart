import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_app/domain/ability.dart';
import 'package:fitness_app/domain/models.dart';
import 'package:fitness_app/screens/train/create_exercise_screen.dart';
import 'package:fitness_app/widgets/common.dart';

/// 單獨掛載受測畫面 —— 表單規則屬畫面層級，不需要整個導覽堆疊。
Future<void> pumpForm(WidgetTester t) async {
  t.view.physicalSize = const Size(393 * 3, 852 * 3);
  t.view.devicePixelRatio = 3.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(const MaterialApp(home: CreateExerciseScreen()));
  await t.pumpAndSettle();
}

/// 從一個空白頁 push 受測畫面，才收得到 pop 的回傳值。
Future<Exercise?> pumpAndCreate(
  WidgetTester t,
  Future<void> Function(WidgetTester) fill,
) async {
  t.view.physicalSize = const Size(393 * 3, 852 * 3);
  t.view.devicePixelRatio = 3.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);

  Exercise? result;
  await t.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () async {
              result = await Navigator.of(context).push<Exercise>(
                MaterialPageRoute(builder: (_) => const CreateExerciseScreen()),
              );
            },
            child: const Text('開始'),
          ),
        ),
      ),
    ),
  ));
  await t.pumpAndSettle();
  await t.tap(find.text('開始'));
  await t.pumpAndSettle();
  await fill(t);
  return result;
}

AppButton cta(WidgetTester t) =>
    t.widget<AppButton>(find.widgetWithText(AppButton, '建立動作'));

/// 直接從畫面中央往上拖 —— TextField 自己也是 Scrollable，
/// 用 finder 指名表單那一個會在捲動途中失效（被指名的項目捲出建構範圍）。
Future<void> scrollTo(WidgetTester t, Finder target) async {
  for (var i = 0; i < 12 && target.evaluate().isEmpty; i++) {
    await t.dragFrom(const Offset(196, 500), const Offset(0, -240));
    await t.pumpAndSettle();
  }
  expect(target, findsWidgets, reason: '捲了 12 次仍找不到目標');
}

void main() {
  group('建立自訂動作（Command：建立自訂動作）', () {
    testWidgets('所屬肌群必填 —— 未選前不給建立', (t) async {
      await pumpForm(t);
      await t.enterText(find.byType(TextField).first, '彈力帶側走');
      await t.pumpAndSettle();
      expect(cta(t).onPressed, isNull,
          reason: '自建動作的所屬肌群必填 —— 留空會在動作庫與訓練歷史變成孤兒項');

      await t.tap(find.text('腿'));
      await t.pumpAndSettle();
      expect(cta(t).onPressed, isNotNull);
    });

    testWidgets('名稱必填', (t) async {
      await pumpForm(t);
      await t.tap(find.text('腿'));
      await t.pumpAndSettle();
      expect(cta(t).onPressed, isNull);
    });

    testWidgets('有氧不填肌群，改填 MET —— 肌群欄位整段消失', (t) async {
      await pumpForm(t);
      await t.enterText(find.byType(TextField).first, '爬樓梯');
      await t.tap(find.text('有氧'));
      await t.pumpAndSettle();

      // 動作類型為有氧者，所屬肌群為空值。
      expect(find.text('所屬肌群'), findsNothing);
      // MET 值供估算消耗大卡，有氧必填、重訓為空值。
      expect(find.text('MET 值'), findsOneWidget);
      expect(cta(t).onPressed, isNotNull);
    });

    testWidgets('切到有氧會清掉已選的肌群，切回來須重選', (t) async {
      await pumpForm(t);
      await t.enterText(find.byType(TextField).first, '爬樓梯');
      await t.tap(find.text('腿'));
      await t.pumpAndSettle();
      expect(cta(t).onPressed, isNotNull);

      await t.tap(find.text('有氧'));
      await t.pumpAndSettle();
      await t.tap(find.text('重訓'));
      await t.pumpAndSettle();
      expect(cta(t).onPressed, isNull);
    });

    testWidgets('所需器材選填 —— 留空者不參與器材比對', (t) async {
      await pumpForm(t);
      await scrollTo(t, find.textContaining('不參與器材比對'));
      expect(find.textContaining('不參與器材比對'), findsOneWidget);
    });

    testWidgets('可練場所由所需器材推導：多項器材取交集', (t) async {
      await pumpForm(t);
      await scrollTo(t, find.text('彈力繩'));

      // 彈力繩：健身房 / 居家。
      await t.tap(find.text('彈力繩'));
      await t.pumpAndSettle();
      await scrollTo(t, find.text('可練場所'));
      expect(find.text('健身房 / 居家'), findsOneWidget);

      // 再加槓鈴（只有健身房）→ 同時具備兩者的場所只剩健身房。
      await t.tap(find.text('槓鈴'));
      await t.pumpAndSettle();
      expect(find.text('健身房'), findsOneWidget);
      expect(find.text('健身房 / 居家'), findsNothing);

      // 徒手到處都能練，但交集仍受槓鈴限制。
      await t.tap(find.text('徒手'));
      await t.pumpAndSettle();
      expect(find.text('健身房'), findsOneWidget);
    });

    testWidgets('建立後回傳的動作標為自建，且不計入能力值', (t) async {
      final result = await pumpAndCreate(t, (t) async {
        await t.enterText(find.byType(TextField).first, '農夫走路 2.0');
        await t.pumpAndSettle();
        await t.tap(find.text('核心'));
        await t.pumpAndSettle();
        await t.tap(find.widgetWithText(AppButton, '建立動作'));
        await t.pumpAndSettle();
      });

      expect(result, isNotNull);
      result!;
      expect(result.name, '農夫走路 2.0');
      expect(result.isCustom, isTrue,
          reason: '自建動作僅建立者本人可選用，且不計入能力值計算');
      expect(result.dim, Dim.core);
      expect(result.type, ExerciseType.strength);
    });
  });

  group('底部固定動作列', () {
    testWidgets('不得撐滿畫面 —— AppButton 收到寬鬆約束會吃掉整個高度', (t) async {
      await pumpForm(t);
      final bar = t.getSize(find.ancestor(
        of: find.widgetWithText(AppButton, '建立動作'),
        matching: find.byType(SafeArea),
      ).last);
      expect(bar.height, lessThan(120),
          reason: '底部列若撐滿，上方表單會被壓成 0 高度、整頁看不到內容');
      // 表單確實還有高度。
      expect(t.getSize(find.byType(ListView)).height, greaterThan(400));
    });

    testWidgets('375 最窄檢查點：不爆版', (t) async {
      t.view.physicalSize = const Size(375 * 3, 667 * 3);
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(const MaterialApp(home: CreateExerciseScreen()));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);

      await t.tap(find.text('有氧'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);

      await scrollTo(t, find.text('可練場所'));
      expect(t.takeException(), isNull);
    });
  });
}
