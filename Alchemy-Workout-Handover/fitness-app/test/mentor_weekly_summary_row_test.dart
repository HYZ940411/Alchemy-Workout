// 學徒頁「本週互動摘要」：評分鈕與兩個數字同一列，其餘說明文字拿掉
// （使用者 2026-10-17，附截圖與 SVG 預覽）。
//
// 拿掉的：「本週已／尚未評分 · 距週一重置剩 N 天」、「每週最多評一次…」整段、
// 其中的教官聲望與帶徒上限。已評分改由按鈕標籤表達。

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/screens/social/mentor_screen.dart';
import 'package:fitness_app/state/app_state.dart';
import 'package:fitness_app/widgets/common.dart';

AppState _apprentice() => AppState()
  ..myInstructor = Instructor(
    name: '老王',
    uid: 'u-教官',
    rank: 40,
    reputation: 137,
    apprentices: 1,
    apprenticeCap: 4,
    ability: const {},
    specialties: const ['增肌'],
    avgRating: 4.5,
    ratingCount: 10,
  );

void main() {
  Future<void> open(WidgetTester t, AppState s, {double width = 393}) async {
    t.view.physicalSize = Size(width * 3, 852 * 3);
    t.view.devicePixelRatio = 3.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(AppScope(
      state: s,
      child: const MaterialApp(home: Scaffold(body: MentorScreen())),
    ));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.text('本週互動摘要'), 200,
        scrollable: find.byType(Scrollable).first);
    await t.pumpAndSettle();
  }

  testWidgets('評分鈕、兩個數字在同一列', (t) async {
    await open(t, _apprentice());
    final a = t.getCenter(find.text('提問 / 回覆')).dy;
    final b = t.getCenter(find.text('任務指派 / 完成')).dy;
    expect((a - b).abs(), lessThan(1), reason: '兩個數字本來就同一列');
    // 按鈕中心落在數字區的垂直範圍內 —— 在同一列，而不是掉到下面一行。
    final tile = t.getRect(find.byType(StatTile).first);
    final button = t.getRect(find.widgetWithText(AppButton, '評分'));
    expect(button.center.dy, inInclusiveRange(tile.top, tile.bottom));
    expect(button.left, greaterThan(tile.right), reason: '按鈕在數字的右邊');
  });

  testWidgets('說明文字都拿掉了', (t) async {
    await open(t, _apprentice());
    expect(find.textContaining('本週尚未評分'), findsNothing);
    expect(find.textContaining('本週已評分'), findsNothing);
    expect(find.textContaining('距週一重置'), findsNothing);
    expect(find.textContaining('每週最多評一次'), findsNothing);
    expect(find.textContaining('教官聲望目前'), findsNothing);
  });

  testWidgets('還沒評分：主要樣式、按得下去', (t) async {
    await open(t, _apprentice());
    final b = t.widget<AppButton>(find.widgetWithText(AppButton, '評分'));
    expect(b.kind, BtnKind.primary);
    expect(b.onPressed, isNotNull);
  });

  testWidgets('已評分：標籤變「已評分」，按不下去', (t) async {
    final s = _apprentice()..ratedThisWeek = true;
    await open(t, s);
    expect(find.widgetWithText(AppButton, '評分'), findsNothing);
    final b = t.widget<AppButton>(find.widgetWithText(AppButton, '已評分'));
    expect(b.onPressed, isNull);
  });

  // 專案支援的最窄是 375（見 screen_crawl_test）；360 另外守。
  // **320 不守**：那裡「任務指派 / 完成」只剩約 95 寬而它要 110，會被截成「…」。
  for (final w in [393.0, 375.0, 360.0]) {
    testWidgets('寬 ${w.toInt()}：兩個標籤與按鈕文字都不被截斷', (t) async {
      await open(t, _apprentice(), width: w);
      for (final label in ['提問 / 回覆', '任務指派 / 完成']) {
        final p = t.renderObject<RenderParagraph>(find.text(label));
        expect(p.didExceedMaxLines, isFalse, reason: '$label 被截斷了');
      }
      final bp = t.renderObject<RenderParagraph>(
          find.descendant(
              of: find.widgetWithText(AppButton, '評分'),
              matching: find.text('評分')));
      expect(bp.size.height, lessThan(40), reason: '按鈕文字換行了');
      expect(t.takeException(), isNull);
    });
  }
}
