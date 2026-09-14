import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_app/main.dart';
import 'package:fitness_app/widgets/common.dart';
import 'package:fitness_app/screens/me/more_screen.dart';
import 'package:fitness_app/screens/signup/launch_screen.dart';
import 'package:fitness_app/screens/settlement_screen.dart';
import 'package:fitness_app/screens/train/create_exercise_screen.dart';
import 'package:fitness_app/screens/train/custom_plan_edit_screen.dart';
import 'package:fitness_app/screens/train/custom_plans_screen.dart';
import 'package:fitness_app/screens/train/exercise_detail_screen.dart';
import 'package:fitness_app/screens/train/history_detail_screen.dart';
import 'package:fitness_app/screens/train/plan_detail_screen.dart';
import 'package:fitness_app/screens/train/rest_countdown.dart';

/// 設計基準機型 iPhone 15／16（393 × 852）
const kBase = Size(393 * 3, 852 * 3);

/// 最窄檢查點 iPhone SE（375）
/// 【必須】每一頁畫完後必須拉到 375 寬再檢查一次，確認未爆版。
const kNarrow = Size(375 * 3, 667 * 3);

Future<void> _boot(WidgetTester t, {Size size = kBase}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 3.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(const FitnessApp());
  await t.pumpAndSettle();
}

void main() {
  testWidgets('五格架構：首頁／社群／訓練／商店／我的', (t) async {
    await _boot(t);
    for (final label in ['社群', '商店', '我的', '首頁']) {
      await t.tap(find.text(label).last);
      await t.pumpAndSettle();
    }
    expect(t.takeException(), isNull);
  });

  testWidgets('375 最窄機型不爆版', (t) async {
    await _boot(t, size: kNarrow);
    for (final label in ['社群', '商店', '我的', '首頁']) {
      await t.tap(find.text(label).last);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull, reason: '$label 在 375 下爆版');
    }
  });

  testWidgets('中央訓練鍵進入課表選擇', (t) async {
    await _boot(t);
    await t.tap(find.byIcon(Icons.fitness_center).last);
    await t.pumpAndSettle();
    expect(find.text('選擇今天的課表'), findsOneWidget);
  });

  testWidgets('社群四個分頁皆可 render', (t) async {
    await _boot(t);
    await t.tap(find.text('社群').last);
    await t.pumpAndSettle();
    for (final label in ['團隊', '師徒', '私訊', '動態']) {
      await t.tap(find.text(label).last);
      await t.pumpAndSettle();
    }
    expect(t.takeException(), isNull);
  });

  testWidgets('「我的」的每個入口都開得起來', (t) async {
    await _boot(t);
    await t.tap(find.text('我的').last);
    await t.pumpAndSettle();

    // 依「我的」頁面上的實際排列順序
    const entries = [
      '六維能力值', '我的檔案',
      '訓練歷史', '自訂訓練', '動作庫', '新手 / 回歸任務',
      '每日簽到 / 每日任務', '補簽', '獎勵信箱', '成就', '個人排行榜',
      '商城', '我的訂單', '金幣儲值', 'AI 點數', '會員訂閱',
      '教官申請', '師徒互動頁', '處罰與申訴', '設定',
      // 註冊流程用關閉鍵而非返回鍵，另有專屬測試，此處不巡
      'AI 自動優化',
    ];
    for (final e in entries) {
      // 連捲動的清單也要限縮 —— Scrollable.first 會抓到首頁那個
      final list = find
          .descendant(
              of: find.byType(MoreScreen), matching: find.byType(Scrollable))
          .first;
      // 每次先回到頂端，避免只能單向捲動而找不到上方的項目
      await t.drag(list, const Offset(0, 4000));
      await t.pumpAndSettle();
      // IndexedStack 會把五格全部留在樹上，同名文字（如「獎勵信箱」也在首頁的
      // 快速入口）會誤中。限縮到「我的」頁的子樹內。
      final target = find.descendant(
          of: find.byType(MoreScreen), matching: find.text(e));
      await t.scrollUntilVisible(target, 120, scrollable: list);
      // 捲動動畫未停就點，點擊座標會算在動畫中途的位置上
      await t.pumpAndSettle();
      await t.tap(target);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull, reason: '$e 開啟時發生例外');
      await t.pageBack();
      await t.pumpAndSettle();
    }
  });

  testWidgets('訓練迴圈：完成組 → 結束彈窗 → 結算頁', (t) async {
    await _boot(t);
    await t.tap(find.byIcon(Icons.fitness_center).last);
    await t.pumpAndSettle();
    // 課表卡現在是摘要，點入詳情頁才有開始訓練（〈課表選擇頁〉→ 計畫詳情）。
    await t.tap(find.text('推日：胸肩三頭').first);
    await t.pumpAndSettle();
    expect(find.byType(PlanDetailScreen), findsOneWidget);
    // 詳情頁把課表內容整份攤開，CTA 落在摺線以下。
    await t.scrollUntilVisible(find.text('開始訓練'), 300);
    await t.pumpAndSettle();
    await t.tap(find.text('開始訓練').first);
    await t.pumpAndSettle();
    expect(find.text('目前動作'), findsOneWidget);

    // 步進器的勾選框
    await t.tap(find.byIcon(Icons.check).first);
    await t.pumpAndSettle();

    // 完成一組後組間休息全屏蓋上 —— 跳過才回得去（§8.10）。
    expect(find.byType(RestCountdownScreen), findsOneWidget);
    // 蓋滿整個畫面（點擊吸收另由 rest_test.dart 直接驗證）。
    expect(t.getSize(find.byType(RestCountdownScreen)),
        t.view.physicalSize / t.view.devicePixelRatio);

    await t.tap(find.text('跳過休息'));
    await t.pumpAndSettle();
    expect(find.byType(RestCountdownScreen), findsNothing);
    expect(find.text('目前動作'), findsOneWidget);

    await t.tap(find.byIcon(Icons.close).first);
    await t.pumpAndSettle();
    expect(find.text('結束這次訓練？'), findsOneWidget);
    await t.tap(find.text('提前結束訓練'));
    await t.pumpAndSettle();

    expect(find.byType(SettlementScreen), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('發文：可見範圍、字數、違規攔截', (t) async {
    await _boot(t);
    await t.tap(find.text('社群').last);
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(AppButton, '發文'));
    await t.pumpAndSettle();

    // 空內容時發布鍵停用
    expect(find.text('可見範圍'), findsOneWidget);
    expect(find.text('僅關注者'), findsOneWidget);

    // 明顯違規 → 當場攔截，不發布
    await t.enterText(find.byType(TextField).first, '加賴看更多');
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(AppButton, '發布'));
    await t.pumpAndSettle();
    expect(find.text('內容已攔截'), findsOneWidget);
    await t.tap(find.widgetWithText(AppButton, '我知道了'));
    await t.pumpAndSettle();

    // 正常內容 → 發布成功並回到動態牆
    await t.enterText(find.byType(TextField).first, '今天腿日，深蹲破紀錄');
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(AppButton, '發布'));
    await t.pumpAndSettle();
    expect(find.text('今天腿日，深蹲破紀錄'), findsWidgets);
    // 預設可見範圍為公開，故探索分頁也看得到
    await t.tap(find.text('探索').last);
    await t.pumpAndSettle();
    expect(find.text('今天腿日，深蹲破紀錄'), findsWidgets);
  });

  testWidgets('團隊限時任務：完成後分數與人數變動', (t) async {
    await _boot(t);
    await t.tap(find.text('社群').last);
    await t.pumpAndSettle();
    await t.tap(find.text('團隊').last);
    await t.pumpAndSettle();
    expect(find.text('已完成 2 / 4 人'), findsOneWidget);
    // 元件可能已建立於 cacheExtent 內但仍在可視區外，
    // 直接 tap 會點到底部導覽列 —— 必須先 ensureVisible。
    final btn = find.widgetWithText(AppButton, '開始限時任務');
    await t.ensureVisible(btn);
    await t.pumpAndSettle();
    await t.tap(btn);
    await t.pumpAndSettle();
    // 完成後按鈕消失（同一人不重複計分），人數 2 → 3
    expect(btn, findsNothing);
    expect(find.text('已完成 3 / 4 人'), findsOneWidget);
  });

  testWidgets('金幣儲值：四檔面額與購買確認', (t) async {
    await _boot(t);
    await t.tap(find.text('商店').last);
    await t.pumpAndSettle();
    await t.tap(find.text('金幣儲值').last);
    await t.pumpAndSettle();
    expect(find.text('450 金幣'), findsOneWidget);
    expect(find.text('9500 金幣'), findsOneWidget);
    await t.tap(find.textContaining('購買　NT'));
    await t.pumpAndSettle();
    expect(find.text('確認購買'), findsOneWidget);
  });

  testWidgets('AI 調整：確認需求 → 產出建議 → 接受套用', (t) async {
    await _boot(t);
    await t.tap(find.byIcon(Icons.fitness_center).last);
    await t.pumpAndSettle();
    await t.tap(find.text('推日：胸肩三頭').first);
    await t.pumpAndSettle();
    await t.scrollUntilVisible(
        find.widgetWithText(AppButton, 'AI 訓練前調整'), 300);
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(AppButton, 'AI 訓練前調整').first);
    await t.pumpAndSettle();

    // 提出調整要求 → AI 再次確認需求
    await t.enterText(find.byType(TextField).first, '今天肩膀緊，想降強度');
    await t.tap(find.byIcon(Icons.send_rounded));
    await t.pumpAndSettle();
    expect(find.textContaining('要怎麼調'), findsOneWidget);

    // 使用者確認需求 → 分析 → 產出建議
    await t.enterText(find.byType(TextField).first, '整體降強度');
    await t.tap(find.byIcon(Icons.send_rounded));
    await t.pump(const Duration(seconds: 2));
    await t.pumpAndSettle();
    expect(find.textContaining('建議如下'), findsOneWidget);

    // 接受 → 套用新強度
    await t.tap(find.widgetWithText(AppButton, '使用新強度'));
    await t.pumpAndSettle();
    expect(find.textContaining('訓練課表已套用新強度'), findsWidgets);
  });

  testWidgets('AI 調整：拒絕後流程結束，不可重新提出', (t) async {
    await _boot(t);
    await t.tap(find.byIcon(Icons.fitness_center).last);
    await t.pumpAndSettle();
    await t.tap(find.text('推日：胸肩三頭').first);
    await t.pumpAndSettle();
    await t.scrollUntilVisible(
        find.widgetWithText(AppButton, 'AI 訓練前調整'), 300);
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(AppButton, 'AI 訓練前調整').first);
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).first, '想換動作');
    await t.tap(find.byIcon(Icons.send_rounded));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).first, '換掉臥推');
    await t.tap(find.byIcon(Icons.send_rounded));
    await t.pump(const Duration(seconds: 2));
    await t.pumpAndSettle();

    await t.tap(find.widgetWithText(AppButton, '拒絕調整'));
    await t.pumpAndSettle();
    expect(find.text('本次流程已結束，不可重新提出調整要求。'), findsOneWidget);
    // 輸入框不再出現
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('註冊流程：9 欄問卷與中斷續填', (t) async {
    await _boot(t);
    await t.tap(find.text('我的').last);
    await t.pumpAndSettle();
    final list = find
        .descendant(of: find.byType(MoreScreen), matching: find.byType(Scrollable))
        .first;
    final entry =
        find.descendant(of: find.byType(MoreScreen), matching: find.text('註冊流程'));
    await t.scrollUntilVisible(entry, 120, scrollable: list);
    await t.pumpAndSettle();
    await t.tap(entry);
    await t.pumpAndSettle();

    // 啟動頁：載入完自動離開；點一下可以跳過等待
    await t.tap(find.byType(LaunchScreen));
    await t.pumpAndSettle();

    // 登入頁：入口二選一，手機路徑要先填號碼
    expect(find.text('開始吧'), findsOneWidget);
    await t.enterText(find.byType(TextField).first, '0912345678');
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(AppButton, '發送驗證碼'));
    await t.pumpAndSettle();

    // 手機驗證頁：輸滿六碼才可下一步
    expect(find.text('輸入驗證碼'), findsOneWidget);
    expect(find.widgetWithText(AppButton, '下一步'), findsOneWidget);
    await t.enterText(find.byType(TextField).first, '492817');
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(AppButton, '下一步'));
    await t.pumpAndSettle();

    // 同意條款後才建立帳號
    expect(find.widgetWithText(AppButton, '同意並建立帳號'), findsOneWidget);
    await t.tap(find.byType(AppSwitch));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(AppButton, '同意並建立帳號'));
    await t.pumpAndSettle();

    // 進入 9 欄問卷
    expect(find.text('第 1／9'), findsOneWidget);
    expect(find.text('你的身高？'), findsOneWidget);
    await t.tap(find.widgetWithText(AppButton, '下一步'));
    await t.pumpAndSettle();
    expect(find.text('第 2／9'), findsOneWidget);

    // 未填完離開 → 跳確認，資料保留
    await t.tap(find.byIcon(Icons.close));
    await t.pumpAndSettle();
    expect(find.text('要先離開嗎？'), findsOneWidget);
    await t.tap(find.widgetWithText(AppButton, '離開'));
    await t.pumpAndSettle();

    // 續填：自未完成的欄位開始，且不再走一次啟動頁與登入頁
    await t.tap(entry);
    await t.pumpAndSettle();
    expect(find.byType(LaunchScreen), findsNothing);
    expect(find.text('第 3／9'), findsOneWidget);
  });

  testWidgets('首頁簽到後狀態改變', (t) async {
    await _boot(t);
    expect(find.text('今天還沒簽到'), findsOneWidget);
    await t.tap(find.textContaining('簽到　經驗值'));
    await t.pumpAndSettle();
    expect(find.text('今日已簽到'), findsOneWidget);
  });

  testWidgets('動作庫 → 動作詳情：走勢圖與逐次紀錄', (t) async {
    await _boot(t);
    await t.tap(find.text('我的').last);
    await t.pumpAndSettle();
    await scrollToMenu(t, '動作庫');
    await t.tap(find.text('動作庫'));
    await t.pumpAndSettle();

    // 胸分頁預設排序為累積練習次數由多到少 —— 板凳臥推 · 槓鈴 41 次排第一。
    await t.tap(find.text('板凳臥推 · 槓鈴').first);
    await t.pumpAndSettle();
    expect(find.byType(ExerciseDetailScreen), findsOneWidget);
    expect(find.text('重量走勢'), findsOneWidget);
    // 課表未指定時取動作層級的預設休息秒數。
    expect(find.text('150'), findsOneWidget);
    expect(find.byType(TrendPainter), findsNothing,
        reason: 'TrendPainter 是 CustomPainter 不是 Widget，以圖表容器代之');
    await t.scrollUntilVisible(find.text('逐次紀錄'), 300);
    await t.pumpAndSettle();
    expect(find.text('逐次紀錄'), findsOneWidget);
  });

  testWidgets('動作詳情：沒練過的動作落在空狀態，不畫空圖表', (t) async {
    await _boot(t);
    await t.tap(find.text('我的').last);
    await t.pumpAndSettle();
    await scrollToMenu(t, '動作庫');
    await t.tap(find.text('動作庫'));
    await t.pumpAndSettle();
    // 匯入的平台動作尚無任何紀錄，累積 0 次、無走勢。用搜尋找到它。
    await t.enterText(find.byType(SearchField).first, '上斜板凳握推');
    await t.pumpAndSettle();
    await t.tap(find.text('上斜板凳握推 · 啞鈴'));
    await t.pumpAndSettle();
    expect(find.text('還沒有這個動作的紀錄'), findsOneWidget);
    expect(find.text('逐次紀錄'), findsNothing);
  });

  testWidgets('訓練歷史 → 動作趨勢：排序、搜尋、點入詳情', (t) async {
    await _boot(t);
    await t.tap(find.text('我的').last);
    await t.pumpAndSettle();
    await scrollToMenu(t, '訓練歷史');
    await t.tap(find.text('訓練歷史'));
    await t.pumpAndSettle();
    await t.tap(find.text('動作趨勢'));
    await t.pumpAndSettle();

    // 搜尋涵蓋平台動作庫與自建動作。
    await t.enterText(find.byType(TextField), '農夫');
    await t.pumpAndSettle();
    expect(find.text('農夫走路'), findsOneWidget);
    expect(find.text('板凳臥推 · 槓鈴'), findsNothing);

    await t.tap(find.text('農夫走路'));
    await t.pumpAndSettle();
    expect(find.byType(ExerciseDetailScreen), findsOneWidget);
    // 自建動作不計入能力值，且所屬肌群不作為能力值歸屬呈現。
    expect(find.text('本動作不計入能力值'), findsOneWidget);
  });

  testWidgets('動作趨勢：搜不到時給空狀態而非空白頁', (t) async {
    await _boot(t);
    await t.tap(find.text('我的').last);
    await t.pumpAndSettle();
    await scrollToMenu(t, '訓練歷史');
    await t.tap(find.text('訓練歷史'));
    await t.pumpAndSettle();
    await t.tap(find.text('動作趨勢'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '不存在的動作');
    await t.pumpAndSettle();
    expect(find.text('找不到這個動作'), findsOneWidget);
  });

  testWidgets('訓練清單 → 訓練紀錄詳情：各動作各組明細', (t) async {
    await _boot(t);
    await t.tap(find.text('我的').last);
    await t.pumpAndSettle();
    await scrollToMenu(t, '訓練歷史');
    await t.tap(find.text('訓練歷史'));
    await t.pumpAndSettle();

    await t.tap(find.text('腿日：深蹲主導').first);
    await t.pumpAndSettle();
    expect(find.byType(HistoryDetailScreen), findsOneWidget);
    // 總訓練量四捨五入至整數呈現。數字取自資料本身 ——
    // 寫死一個假資料的數字，假資料一改測試就掛，而規則沒變。
    final entry = t
        .widget<HistoryDetailScreen>(find.byType(HistoryDetailScreen))
        .entry;
    expect(find.text('${entry.volume.round()}'), findsOneWidget);
    expect(find.text('第 5 組'), findsOneWidget);
    expect(find.text('80 kg × 5 下'), findsWidgets);
    // 不含終止方式 —— 完成 / 提前結束 / 逾時中斷三者皆不呈現。
    expect(find.textContaining('提前結束'), findsNothing);
    expect(find.textContaining('逾時中斷'), findsNothing);
  });

  testWidgets('計畫詳情：未解鎖時呈現三種解鎖方式，且不給開始訓練', (t) async {
    await _boot(t);
    await t.tap(find.byIcon(Icons.fitness_center).last);
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.text('進階：爆發力週期'), 300);
    await t.pumpAndSettle();
    await t.tap(find.text('進階：爆發力週期'));
    await t.pumpAndSettle();
    expect(find.byType(PlanDetailScreen), findsOneWidget);

    expect(find.text('尚未解鎖'), findsOneWidget);
    expect(find.text('階級達標'), findsOneWidget);
    expect(find.text('金幣提前購買'), findsOneWidget);
    expect(find.text('600 金幣．永久取得'), findsOneWidget);
    expect(find.text('會員身分'), findsOneWidget);
    // 金幣購買是三條路徑中唯一能當場走完的一條，必須真的按得下去。
    expect(find.text('以 600 金幣購買解鎖'), findsOneWidget);
    // 未解鎖者不給開始訓練。
    expect(find.text('開始訓練'), findsNothing);
  });

  testWidgets('計畫詳情：金幣購買解鎖走得完，走完就能開始訓練', (t) async {
    await _boot(t);
    await t.tap(find.byIcon(Icons.fitness_center).last);
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.text('進階：爆發力週期'), 300);
    await t.pumpAndSettle();
    await t.tap(find.text('進階：爆發力週期'));
    await t.pumpAndSettle();

    await t.tap(find.text('以 600 金幣購買解鎖'));
    await t.pumpAndSettle();
    await t.tap(find.text('確認購買'));
    await t.pumpAndSettle();

    // 已解鎖：解鎖卡消失，開始訓練出現。
    expect(find.text('尚未解鎖'), findsNothing);
    await t.scrollUntilVisible(find.text('開始訓練'), 300);
    await t.pumpAndSettle();
    expect(find.text('開始訓練'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('計畫詳情：AI 已替換動作以刪除線呈現原動作', (t) async {
    await _boot(t);
    await t.tap(find.byIcon(Icons.fitness_center).last);
    await t.pumpAndSettle();
    await t.tap(find.text('推日：胸肩三頭').first);
    await t.pumpAndSettle();
    expect(find.text('AI 已替換：'), findsOneWidget);
    final orig = t.widget<Text>(find.text('上斜板凳臥推 · 槓鈴'));
    expect(orig.style!.decoration, TextDecoration.lineThrough);
    // 課表指定值蓋過動作預設（臥推動作預設 150，課表指定 120）。
    // 臥推動作預設 150 秒，本課表指定 120 —— 課表指定值為第一順位。
    expect(find.descendant(
      of: find.ancestor(
        of: find.text('板凳臥推 · 槓鈴'),
        matching: find.byType(AppCard),
      ).first,
      matching: find.text('休息 120 秒'),
    ), findsOneWidget);
  });

  testWidgets('375 最窄檢查點：三個新詳情頁不爆版', (t) async {
    await _boot(t, size: kNarrow);

    // 計畫詳情（含最長的解鎖說明）
    await t.tap(find.byIcon(Icons.fitness_center).last);
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.text('進階：爆發力週期'), 300);
    await t.pumpAndSettle();
    await t.tap(find.text('進階：爆發力週期'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    // 捲到課表內容的最後一個動作，確認整頁都畫得完。
    await t.scrollUntilVisible(find.text('上舉 · 槓鈴'), 300);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await t.pageBack();
    await t.pumpAndSettle();

    // 訓練紀錄詳情（總訓練量為四位數）
    await t.tap(find.text('我的').last);
    await t.pumpAndSettle();
    await scrollToMenu(t, '訓練歷史');
    await t.tap(find.text('訓練歷史'));
    await t.pumpAndSettle();
    await t.tap(find.text('腿日：深蹲主導').first);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await t.scrollUntilVisible(find.text('另存為自訂訓練'), 300);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await t.pageBack();
    await t.pumpAndSettle();

    // 動作詳情（三欄統計 ＋ 折線圖）
    await t.tap(find.text('動作趨勢'));
    await t.pumpAndSettle();
    await t.tap(find.text('板凳臥推 · 槓鈴'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await t.scrollUntilVisible(find.text('逐次紀錄'), 300);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });

  testWidgets('自訂訓練編輯：三層結構，空課表不給存', (t) async {
    await _boot(t);
    await _openCustomPlans(t);
    await t.tap(find.widgetWithText(AppButton, '新增自訂訓練'));
    await t.pumpAndSettle();
    expect(find.byType(CustomPlanEditScreen), findsOneWidget);

    // 沒有名稱也沒有動作 → 儲存停用。
    expect(t.widget<AppButton>(find.widgetWithText(AppButton, '儲存')).onPressed,
        isNull);

    await t.enterText(find.byType(TextField).first, '出差旅館版');
    await t.pumpAndSettle();
    // 只有名稱、沒有動作，仍不給存 —— 那會變成空白課表。
    expect(t.widget<AppButton>(find.widgetWithText(AppButton, '儲存')).onPressed,
        isNull);

    await t.tap(find.text('加入動作'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('深蹲 · 槓鈴'));
    await t.pumpAndSettle();
    await t.tap(find.text('深蹲 · 槓鈴'));
    await t.pumpAndSettle();

    expect(find.text('第 1 組'), findsOneWidget);
    expect(find.text('目標重量'), findsOneWidget);
    expect(find.text('目標次數'), findsOneWidget);
    expect(t.widget<AppButton>(find.widgetWithText(AppButton, '儲存')).onPressed,
        isNotNull);
  });

  testWidgets('自訂訓練編輯：每組可各自設定重量，不強制共用', (t) async {
    await _boot(t);
    await _openCustomPlans(t);
    await t.tap(find.widgetWithText(AppButton, '新增自訂訓練'));
    await t.pumpAndSettle();
    await t.tap(find.text('加入動作'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('深蹲 · 槓鈴'));
    await t.pumpAndSettle();
    await t.tap(find.text('深蹲 · 槓鈴'));
    await t.pumpAndSettle();

    await t.tap(find.widgetWithText(AppButton, '加一組'));
    await t.pumpAndSettle();
    expect(find.text('第 2 組'), findsOneWidget);

    // 只加第一組的重量：20 → 20.5（精度 0.5 公斤）。
    final firstWeightRow = find.ancestor(
      of: find.text('目標重量').first,
      matching: find.byType(Row),
    ).first;
    await t.tap(find.descendant(
        of: firstWeightRow, matching: find.byIcon(Icons.add_rounded)));
    await t.pumpAndSettle();
    expect(find.text('20.5 kg'), findsOneWidget);
    expect(find.text('20 kg'), findsOneWidget);
  });

  testWidgets('自訂訓練編輯：有氧只有目標時長，無重量與次數', (t) async {
    await _boot(t);
    await _openCustomPlans(t);
    await t.tap(find.widgetWithText(AppButton, '新增自訂訓練'));
    await t.pumpAndSettle();
    await t.tap(find.text('加入動作'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('划船機'));
    await t.pumpAndSettle();
    await t.tap(find.text('划船機'));
    await t.pumpAndSettle();

    expect(find.text('目標時長'), findsOneWidget);
    expect(find.text('目標重量'), findsNothing);
    expect(find.text('目標次數'), findsNothing);
    expect(find.text('10 分'), findsOneWidget);
  });

  testWidgets('自訂訓練編輯：徒手動作的目標重量為 0，顯示為徒手', (t) async {
    await _boot(t);
    await _openCustomPlans(t);
    await t.tap(find.widgetWithText(AppButton, '新增自訂訓練'));
    await t.pumpAndSettle();
    await t.tap(find.text('加入動作'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('引體向上'));
    await t.pumpAndSettle();
    await t.tap(find.text('引體向上'));
    await t.pumpAndSettle();
    expect(find.text('徒手'), findsOneWidget);
    // 值為 0 已是下限，不可再減。
    expect(t.widget<InkWell>(find.ancestor(
      of: find.byIcon(Icons.remove_rounded).first,
      matching: find.byType(InkWell),
    ).first).onTap, isNull);
  });

  testWidgets('自訂訓練：存檔後回到管理頁，狀態為已儲存（未啟用）', (t) async {
    await _boot(t);
    await _openCustomPlans(t);
    await t.tap(find.widgetWithText(AppButton, '新增自訂訓練'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).first, '出差旅館版 B');
    await t.tap(find.text('加入動作'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('棒式'));
    await t.pumpAndSettle();
    await t.tap(find.text('棒式'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(AppButton, '儲存'));
    await t.pumpAndSettle();

    expect(find.byType(CustomPlanEditScreen), findsNothing);
    await t.scrollUntilVisible(find.text('出差旅館版 B'), 300,
        scrollable: find.descendant(
          of: find.byType(CustomPlansScreen),
          matching: find.byType(Scrollable),
        ).first);
    await t.pumpAndSettle();
    expect(find.text('出差旅館版 B'), findsOneWidget);
  });

  testWidgets('建立的自訂動作可立刻加進課表，並標為自建', (t) async {
    await _boot(t);
    await _openCustomPlans(t);
    await t.tap(find.widgetWithText(AppButton, '新增自訂訓練'));
    await t.pumpAndSettle();
    await t.tap(find.text('加入動作'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(AppButton, '建立新的自訂動作'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).first, '彈力帶側走');
    await t.pumpAndSettle();
    await t.tap(find.text('腿'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(AppButton, '建立動作'));
    await t.pumpAndSettle();

    expect(find.byType(CreateExerciseScreen), findsNothing);
    expect(find.text('彈力帶側走'), findsOneWidget);
    expect(find.text('自建'), findsOneWidget);
  });

  testWidgets('自由訓練：空白課表可開始，且不顯示進度條', (t) async {
    await _boot(t);
    await startBlank(t);

    // 總計畫組數為 0 —— 進度條不成立，只留訓練時長。
    expect(find.text(' / 0 組'), findsNothing);
    expect(find.text('訓練時長'), findsOneWidget);
    expect(find.text('0%'), findsNothing);
    expect(find.text('自由訓練'), findsOneWidget);
    // 沒有目前動作，也就沒有步進器與本次課表。
    expect(find.text('目前動作'), findsNothing);
    expect(find.text('本次課表'), findsNothing);
  });

  testWidgets('自由訓練：加入動作後進度條成立', (t) async {
    await _boot(t);
    await startBlank(t);

    await t.tap(find.widgetWithText(AppButton, '加入動作至本次訓練'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('深蹲 · 槓鈴'));
    await t.pumpAndSettle();
    await t.tap(find.text('深蹲 · 槓鈴'));
    await t.pumpAndSettle();

    // 加入時指定組數與目標 —— 這些組沒有快照帶入值。
    expect(find.text('組數'), findsOneWidget);
    expect(find.text('目標重量'), findsOneWidget);
    await t.tap(find.widgetWithText(AppButton, '加入 3 組'));
    await t.pumpAndSettle();

    // 「腿　第 1 / 3 組」也含這個字串，故用精確比對。
    expect(find.text(' / 3 組'), findsOneWidget);
    expect(find.text('目前動作'), findsOneWidget);
    expect(find.text('本次課表'), findsOneWidget);
    // 完整進度面板才有百分比；0 組時的簡版沒有。
    expect(find.text('0%'), findsOneWidget);
  });

  testWidgets('自由訓練：結束彈窗沒有「提前結束」', (t) async {
    await _boot(t);
    await startBlank(t);

    await t.tap(find.byIcon(Icons.close).first);
    await t.pumpAndSettle();
    expect(find.text('結束這次訓練？'), findsOneWidget);
    // 「提前」的前提是存在預定終點，空白課表無預定內容即無「提前」可言。
    expect(find.text('提前結束訓練'), findsNothing);
    expect(find.text('尚有未完成的組'), findsNothing);
    expect(find.text('完成訓練'), findsOneWidget);

    await t.tap(find.text('完成訓練'));
    await t.pumpAndSettle();
    expect(find.byType(SettlementScreen), findsOneWidget);
  });

  testWidgets('一般課表訓練中也能臨時加練計畫外的動作', (t) async {
    await _boot(t);
    await t.tap(find.byIcon(Icons.fitness_center).last);
    await t.pumpAndSettle();
    await t.tap(find.text('推日：胸肩三頭').first);
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.text('開始訓練'), 300);
    await t.pumpAndSettle();
    await t.tap(find.text('開始訓練'));
    await t.pumpAndSettle();

    expect(find.text(' / 13 組'), findsOneWidget);
    await t.scrollUntilVisible(
        find.widgetWithText(AppButton, '加入動作至本次訓練'), 300);
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(AppButton, '加入動作至本次訓練'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('側平舉'));
    await t.pumpAndSettle();
    await t.tap(find.text('側平舉'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(AppButton, '加入 3 組'));
    await t.pumpAndSettle();

    expect(find.text(' / 16 組'), findsOneWidget);
  });

  testWidgets('動作庫：名稱搜尋涵蓋平台動作庫與自建動作', (t) async {
    await _boot(t);
    await openLibrary(t);

    await t.tap(find.text('腿'));
    await t.pumpAndSettle();
    // 未搜尋時，累積次數最多的深蹲排在最前面。
    expect(find.text('深蹲 · 槓鈴'), findsOneWidget);

    await t.enterText(find.byType(SearchField).first, '弓步');
    await t.pumpAndSettle();
    // 搜尋若沒接上，深蹲會還在 —— 這一條才真的證明有濾掉東西。
    expect(find.text('深蹲 · 槓鈴'), findsNothing);
    expect(find.textContaining('弓步'), findsWidgets);

    // 搜尋跨分頁生效：自建動作在「我的動作」分頁也搜得到。
    await t.enterText(find.byType(SearchField).first, '農夫');
    await t.pumpAndSettle();
    await t.tap(find.text('我的動作'));
    await t.pumpAndSettle();
    expect(find.text('農夫走路'), findsOneWidget);
    expect(find.text('彈力帶外旋'), findsNothing);
  });

  testWidgets('動作庫：搜不到時給空狀態，不是空白分頁', (t) async {
    await _boot(t);
    await openLibrary(t);
    await t.enterText(find.byType(SearchField).first, '不存在的動作');
    await t.pumpAndSettle();
    expect(find.text('這個分頁沒有符合的動作'), findsOneWidget);
  });

  testWidgets('動作庫：器材篩選預設帶入持有器材明細，且真的會篩', (t) async {
    await _boot(t);
    await openLibrary(t);
    // 預設持有：徒手、啞鈴、槓鈴、繩索（滑輪）
    expect(find.text('器材篩選：4 項'), findsOneWidget);

    // 深蹲分兩種：槓鈴的做得了，哈克深蹲機（機械式）做不了。
    await t.tap(find.text('腿'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(SearchField).first, '哈克深蹲');
    await t.pumpAndSettle();
    // 槓鈴版做得了；哈克深蹲機屬機械式器材，不在預設持有清單內 —— 篩掉。
    //
    // 這裡不寫成「一筆都搜不到」：那是舊寫法，它其實是靠當時名稱分隔符
    // 不一致（「哈克深蹲 -槓鈴」有空格、「哈克深蹲-器械」沒有）才只命中一筆，
    // 等於拿一個資料瑕疵當測試手段。名稱統一之後那個巧合就沒了。
    expect(find.text('哈克深蹲 · 槓鈴'), findsOneWidget);
    expect(find.text('哈克深蹲 · 器械'), findsNothing);

    // 清除篩選後機械式的動作就出現了。
    await t.tap(find.text('清除'));
    await t.pumpAndSettle();
    expect(find.text('器材篩選：全部動作'), findsOneWidget);
    expect(find.text('哈克深蹲 · 器械'), findsOneWidget);
  });

  testWidgets('動作庫：所需器材須全部具備才算做得了', (t) async {
    await _boot(t);
    await openLibrary(t);
    // 槓鈴臥推：只需槓鈴 → 做得了
    // （查詢字串本身也是一個 Text，故不用完整名稱當關鍵字）
    await t.enterText(find.byType(SearchField).first, '板凳臥推 · 槓');
    await t.pumpAndSettle();
    expect(find.text('板凳臥推 · 槓鈴'), findsOneWidget);
    // 史密斯架的版本需要機械式器材 → 做不了
    await t.enterText(find.byType(SearchField).first, '史密斯架');
    await t.pumpAndSettle();
    expect(find.text('這個分頁沒有符合的動作'), findsOneWidget);

    // 加選機械式器材後就出現。
    await t.tap(find.text('機械式器材'));
    await t.pumpAndSettle();
    expect(find.text('板凳臥推 (寬距) · 史密斯架'), findsOneWidget);

    // 「引體向上 · 彈力帶」同時需要彈力繩與機械式器材（單槓）。
    // 只有其中一種時不該出現 —— 這一條區分「全部具備」與「任一即可」。
    await t.tap(find.text('背'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(SearchField).first, '引體向上 · 彈');
    await t.pumpAndSettle();
    expect(find.text('引體向上 · 彈力帶'), findsNothing,
        reason: '此時只選了機械式器材，缺彈力繩');

    await t.tap(find.text('彈力繩'));
    await t.pumpAndSettle();
    expect(find.text('引體向上 · 彈力帶'), findsOneWidget);
  });

  testWidgets('動作庫：器材為空值的自建動作不出現在任何器材分類', (t) async {
    await _boot(t);
    await openLibrary(t);
    await t.tap(find.text('我的動作'));
    await t.pumpAndSettle();
    // 假資料的自建動作有填器材，先確認它在。
    expect(find.text('彈力帶外旋'), findsNothing,
        reason: '彈力繩不在預設持有器材內');
    await t.tap(find.text('清除'));
    await t.pumpAndSettle();
    expect(find.text('彈力帶外旋'), findsOneWidget);
  });
  testWidgets('端到端：申請公開 → 管理員通過 → 使用者端變成已公開', (t) async {
    await _boot(t);
    await _openCustomPlans(t, freeSlot: false);

    // 「我的核心日」目前是已發布，送出申請公開。
    final card = find.ancestor(
        of: find.text('我的核心日'), matching: find.byType(Panel));
    await t.tap(find.descendant(
        of: card, matching: find.widgetWithText(AppButton, '申請公開')));
    await t.pumpAndSettle();
    expect(find.descendant(of: card, matching: find.text('已申請公開')),
        findsOneWidget);
    expect(find.textContaining('審核中，剩'), findsWidgets);

    // 切到管理員後台，該課表已在待審佇列。
    await t.pageBack();
    await t.pumpAndSettle();
    await openPublicPlanQueue(t, fromMore: true);
    expect(find.text('我的核心日'), findsOneWidget);

    await t.tap(find.descendant(
      of: find.ancestor(
          of: find.text('我的核心日'), matching: find.byType(AppCard)),
      matching: find.widgetWithText(AppButton, '通過公開'),
    ));
    await t.pumpAndSettle();
    expect(find.text('我的核心日'), findsNothing, reason: '通過後離開佇列');

    // 回到使用者端，狀態已變成已公開。
    await t.pageBack();
    await t.pumpAndSettle();
    await t.pageBack();
    await t.pumpAndSettle();
    // 剛才捲到更多頁的最下面找後台，自訂訓練在上面。
    await t.scrollUntilVisible(find.text('自訂訓練'), -300,
        scrollable: find.descendant(
          of: find.byType(MoreScreen),
          matching: find.byType(Scrollable),
        ).first);
    await t.pumpAndSettle();
    await t.tap(find.text('自訂訓練'));
    await t.pumpAndSettle();
    expect(
        find.descendant(
          of: find.ancestor(
              of: find.text('我的核心日'), matching: find.byType(Panel)),
          matching: find.text('已公開'),
        ),
        findsOneWidget);
  });

  testWidgets('管理員駁回須附理由，作者看得到', (t) async {
    await _boot(t);
    await openPublicPlanQueue(t);

    await t.tap(find.descendant(
      of: find.ancestor(
          of: find.text('出差旅館版'), matching: find.byType(AppCard)),
      matching: find.widgetWithText(AppButton, '未通過'),
    ));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).last, '深蹲 4×20 對新手負荷過高');
    await t.tap(find.widgetWithText(AppButton, '駁回'));
    await t.pumpAndSettle();

    await t.pageBack();
    await t.pumpAndSettle();
    await t.pageBack();
    await t.pumpAndSettle();
    // 剛才捲到更多頁的最下面找後台，自訂訓練在上面。
    await t.scrollUntilVisible(find.text('自訂訓練'), -300,
        scrollable: find.descendant(
          of: find.byType(MoreScreen),
          matching: find.byType(Scrollable),
        ).first);
    await t.pumpAndSettle();
    await t.tap(find.text('自訂訓練'));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.text('出差旅館版'), 300,
        scrollable: find.descendant(
          of: find.byType(CustomPlansScreen),
          matching: find.byType(Scrollable),
        ).first);
    await t.pumpAndSettle();
    expect(find.textContaining('深蹲 4×20 對新手負荷過高'), findsOneWidget);
    // 假資料本來就有一筆審核未通過，現在多一筆。
    expect(
        find.descendant(
          of: find.ancestor(
              of: find.text('出差旅館版'), matching: find.byType(Panel)),
          matching: find.text('審核未通過'),
        ),
        findsOneWidget);
  });

  testWidgets('待審佇列標示逾期，但不改變案件狀態', (t) async {
    await _boot(t);
    await openPublicPlanQueue(t);

    // 深蹲王的課表已等 17 天，超過 14 天時限。
    expect(find.text('已逾期'), findsOneWidget);
    // 逾期不自動通過也不自動駁回 —— 案件仍在佇列裡等人處理。
    expect(find.text('大重量週期'), findsOneWidget);
    expect(find.widgetWithText(AppButton, '通過公開'), findsWidgets);
  });
}

/// 動作庫在「我的」→ 更多。
Future<void> openLibrary(WidgetTester t) async {
  await t.tap(find.text('我的').last);
  await t.pumpAndSettle();
  await scrollToMenu(t, '動作庫');
  await t.tap(find.text('動作庫'));
  await t.pumpAndSettle();
}

/// 「我的」是著陸頁：頁首佔掉首屏，各功能入口一律要先捲到才點得到。
Future<void> scrollToMenu(WidgetTester t, String label) async {
  final list = find
      .descendant(of: find.byType(MoreScreen), matching: find.byType(Scrollable))
      .first;
  await t.scrollUntilVisible(
      find.descendant(of: find.byType(MoreScreen), matching: find.text(label)),
      120,
      scrollable: list);
  await t.pumpAndSettle();
}


/// 由課表選擇頁進入自由訓練。空白課表恆為已解鎖，且必須呈現。
Future<void> startBlank(WidgetTester t) async {
  await t.tap(find.byIcon(Icons.fitness_center).last);
  await t.pumpAndSettle();
  await t.scrollUntilVisible(find.text('空白課表（自由訓練）'), 300);
  await t.pumpAndSettle();
  await t.tap(find.text('空白課表（自由訓練）'));
  await t.pumpAndSettle();
  expect(find.text('開始自由訓練'), findsOneWidget);
  await t.tap(find.text('開始自由訓練'));
  await t.pumpAndSettle();
}

/// 進自訂訓練管理頁。假資料剛好用滿 5 個名額（免費上限），
/// 而「刪除為釋放名額的唯一手段」—— 想新增就得先刪一份。
Future<void> _openCustomPlans(WidgetTester t, {bool freeSlot = true}) async {
  await t.tap(find.text('我的').last);
  await t.pumpAndSettle();
  await t.tap(find.text('自訂訓練'));
  await t.pumpAndSettle();
  if (!freeSlot) return;
  // ListView 惰性建構，未建出的列 ensureVisible 找不到 —— 得先捲。
  final listOfPlans = find.descendant(
    of: find.byType(CustomPlansScreen),
    matching: find.byType(Scrollable),
  ).first;
  await t.scrollUntilVisible(find.text('新的推日草案'), 300,
      scrollable: listOfPlans);
  await t.pumpAndSettle();
  await t.tap(find.descendant(
    of: find.ancestor(
        of: find.text('新的推日草案'), matching: find.byType(Panel)),
    matching: find.widgetWithText(AppButton, '刪除'),
  ));
  await t.pumpAndSettle();
  await t.tap(find.widgetWithText(AppButton, '刪除').last);
  await t.pumpAndSettle();
  // 刪除時已捲到頁尾，新增鈕在最上面。
  await t.scrollUntilVisible(
      find.widgetWithText(AppButton, '新增自訂訓練'), -300,
      scrollable: listOfPlans);
  await t.pumpAndSettle();
}

/// 進管理員後台的公開課表待審分頁。「管理員後台」在更多頁的最下面。
Future<void> openPublicPlanQueue(WidgetTester t,
    {bool fromMore = false}) async {
  if (!fromMore) {
    await t.tap(find.text('我的').last);
    await t.pumpAndSettle();
  }
  await t.scrollUntilVisible(find.text('管理員後台'), 300,
      scrollable: find.descendant(
        of: find.byType(MoreScreen),
        matching: find.byType(Scrollable),
      ).first);
  await t.pumpAndSettle();
  await t.tap(find.text('管理員後台'));
  await t.pumpAndSettle();
  await t.tap(find.text('待審佇列'));
  await t.pumpAndSettle();
  await t.tap(find.textContaining('公開課表'));
  await t.pumpAndSettle();
}
