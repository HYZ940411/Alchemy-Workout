// 課表詳情頁的「我的評分」入口。
//
// 使用者回報：「評過的課表在 App 裡看不到。」結算頁那張評分卡的條件是
// 「還沒評過才顯示」，一評完就消失，而**沒有第二個入口** ——
// 於是自己評了幾星、寫了什麼，評完那一刻起就再也查不到，更改不了。
//
// `RateExperienceScreen` 從第一天起就會讀回既有評分並允許修改
// （`didChangeDependencies` 裡那段），所以這件事缺的從頭到尾只是一個入口。
// 與「經驗值只有刪帳號頁看得到」同型：功能做好了，路沒接上。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/models.dart';
import 'package:fitness_app/domain/novice_wrapup.dart';
import 'package:fitness_app/mock/mock_extra.dart';
import 'package:fitness_app/screens/train/plan_detail_screen.dart';
import 'package:fitness_app/state/app_state.dart';

void main() {
  /// 找一份已解鎖的課表來測 —— 未解鎖的課表底下那一整區按鈕都不出現，
  /// 驗到的就不是評分這件事。
  WorkoutPlan unlockedPlan(AppState s) =>
      s.platformPlans.firstWhere(s.planUnlocked);

  /// 讓這個帳號「練過」某份課表。訓練歷史存的是課表**名稱**
  /// （`HistoryEntry.planName`），不是 ID —— 這一點畫面那側也一樣。
  void markTrained(AppState s, WorkoutPlan p) {
    s.history.insert(0, HistoryEntry(DateTime(2026, 9, 1), p.name, 1000, 45,
        300, const [], completion: 1));
  }

  /// 開課表詳情頁，並**捲到底**。
  ///
  /// 「我的評分」在課表內容底下，而 `ListView` 不會建出畫面外的項目 ——
  /// 不捲的話 `find.text` 連「存在但看不到」與「根本沒有」都分不出來。
  Future<void> open(WidgetTester t, AppState s, WorkoutPlan p) async {
    await t.pumpWidget(AppScope(
      state: s,
      child: MaterialApp(home: PlanDetailScreen(plan: p)),
    ));
    await t.pumpAndSettle();
    final list = find.byType(Scrollable).first;
    for (var i = 0; i < 15; i++) {
      await t.drag(list, const Offset(0, -400));
      await t.pump();
    }
    await t.pumpAndSettle();
  }

  testWidgets('評過之後，課表詳情頁看得到自己評了什麼', (t) async {
    final s = AppState();
    final p = unlockedPlan(s);
    markTrained(s, p);
    s.rateExperience(RatingTarget.trainingPlan, p.id, 4,
        feedback: '動作安排很順，但最後一組太重。');

    await open(t, s, p);

    expect(find.text('我的評分'), findsOneWidget);
    expect(find.text('4 星'), findsOneWidget);
    expect(find.text('動作安排很順，但最後一組太重。'), findsOneWidget);
    expect(find.text('修改評分'), findsOneWidget,
        reason: '看得到還不夠 —— 誤觸一次就永久留著一筆錯的，所以要改得動');
  });

  testWidgets('按「修改評分」進得去，而且帶著原本的評分', (t) async {
    final s = AppState();
    final p = unlockedPlan(s);
    markTrained(s, p);
    s.rateExperience(RatingTarget.trainingPlan, p.id, 2, feedback: '太硬了');

    await open(t, s, p);
    await t.tap(find.text('修改評分'));
    await t.pumpAndSettle();

    // 評分畫面讀回了既有的評語 —— 不是一張空白表單。
    expect(find.text('太硬了'), findsOneWidget);
  });

  testWidgets('練過但還沒評 —— 給一個補評的入口', (t) async {
    final s = AppState();
    final p = unlockedPlan(s);
    markTrained(s, p);

    await open(t, s, p);

    expect(find.text('我的評分'), findsOneWidget);
    expect(find.text('評分這份課表'), findsOneWidget);
    expect(find.text('修改評分'), findsNothing);
  });

  testWidgets('沒練過也沒評過 —— 整段不出現', (t) async {
    final s = AppState();
    final p = unlockedPlan(s);
    // 示範資料的訓練歷史裡可能剛好有同名課表，先清乾淨。
    s.history.removeWhere((h) => h.planName == p.name);

    await open(t, s, p);

    expect(find.text('我的評分'), findsNothing,
        reason: '沒做過的課表評不出「做起來如何」，那只會往管理員的彙總裡倒雜訊');
    expect(find.text('評分這份課表'), findsNothing);
  });
}
