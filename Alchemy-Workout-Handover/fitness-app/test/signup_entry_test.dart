import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/models.dart';
import 'package:fitness_app/domain/registration.dart';
import 'package:fitness_app/domain/rewards.dart';
import 'package:fitness_app/main.dart';
import 'package:fitness_app/screens/me/more_screen.dart';
import 'package:fitness_app/screens/signup/choice_grid.dart';
import 'package:fitness_app/screens/signup/launch_screen.dart';
import 'package:fitness_app/widgets/common.dart';

/// 註冊前段（啟動 → 登入 → 手機驗證）與訓練計畫推薦
void main() {
  group('手機號碼格式', () {
    test('09 開頭的 10 位數字才算數', () {
      expect(isValidPhone('0912345678'), isTrue);
      expect(isValidPhone('0812345678'), isFalse, reason: '不是 09 開頭');
      expect(isValidPhone('091234567'), isFalse, reason: '少一碼');
      expect(isValidPhone('09123456789'), isFalse, reason: '多一碼');
      expect(isValidPhone('09abcdefgh'), isFalse);
    });

    test('空白與連字號不影響判定 —— 使用者不該為了格式重打一次', () {
      expect(isValidPhone('0912-345-678'), isTrue);
      expect(isValidPhone('0912 345 678'), isTrue);
    });
  });

  group('入口二選一', () {
    test('手機路徑須驗證通過才算完成', () {
      final d = SignUpDraft()..entry = SignUpEntry.phone;
      expect(d.entryDone, isFalse);
      d.phoneVerified = true;
      expect(d.entryDone, isTrue);
    });

    test('第三方授權完成即算完成，不需簡訊驗證', () {
      final d = SignUpDraft()..entry = SignUpEntry.thirdParty;
      expect(d.entryDone, isTrue);
    });

    test('沒選入口就不算完成', () {
      expect(SignUpDraft().entryDone, isFalse);
    });
  });

  group('訓練計畫推薦', () {
    WorkoutPlan plan(
      String id,
      String tier, {
      Set<String> exp = const {},
      Set<String> goals = const {},
    }) =>
        WorkoutPlan(
          id: id,
          name: id,
          source: PlanSource.official,
          exercises: const [],
          equipmentTier: tier,
          suitableExperience: exp,
          suitableGoals: goals,
        );

    WorkoutPlan? pick(
      List<WorkoutPlan> plans, {
      String? equipment,
      String? experience,
      String? goal,
    }) =>
        recommendPlan<WorkoutPlan>(
          plans,
          equipment: equipment,
          experience: experience,
          commonGoal: goal,
          tierOf: (p) => p.equipmentTier,
          experienceOf: (p) => p.suitableExperience,
          goalsOf: (p) => p.suitableGoals,
        );

    test('器材為硬約束、第一優先：徒手者拿不到健身房課表', () {
      final plans = [
        // 經驗與目標都命中，但器材不符
        plan('健身房課表',
            '健身房', exp: {'新手（未滿 6 個月）'}, goals: {'增肌'}),
        // 器材符合，其餘皆不符
        plan('徒手課表', '徒手', exp: {'進階（2 年以上）'}, goals: {'減重'}),
      ];
      final got = pick(plans,
          equipment: '徒手',
          experience: '新手（未滿 6 個月）',
          goal: '增肌');
      expect(got?.id, '徒手課表');
    });

    test('健身房可執行全部；居家可執行居家與徒手', () {
      final plans = [plan('居家課表', '居家'), plan('徒手課表', '徒手')];
      expect(pick(plans, equipment: '健身房（全器材）')?.id, '居家課表');
      expect(pick(plans, equipment: '居家器材（彈力繩、小啞鈴等）')?.id, '居家課表');
      expect(pick(plans, equipment: '徒手')?.id, '徒手課表');
    });

    test('器材同層時比經驗，再比常見目標', () {
      final plans = [
        plan('只中目標', '徒手', exp: {'進階（2 年以上）'}, goals: {'增肌'}),
        plan('只中經驗', '徒手', exp: {'新手（未滿 6 個月）'}, goals: {'減重'}),
      ];
      // 經驗的優先序高於常見目標 —— 經驗不符有受傷風險，
      // 目標不符仍是一份有效訓練。
      expect(
        pick(plans,
                equipment: '徒手',
                experience: '新手（未滿 6 個月）',
                goal: '增肌')
            ?.id,
        '只中經驗',
      );
    });

    test('同分者取建立時間最早，不隨機取一', () {
      final plans = [
        plan('先建立的', '徒手', exp: {'新手（未滿 6 個月）'}, goals: {'增肌'}),
        plan('後建立的', '徒手', exp: {'新手（未滿 6 個月）'}, goals: {'增肌'}),
      ];
      for (var i = 0; i < 5; i++) {
        expect(
          pick(plans,
                  equipment: '徒手',
                  experience: '新手（未滿 6 個月）',
                  goal: '增肌')
              ?.id,
          '先建立的',
          reason: '同樣條件要重現得出同一份計畫',
        );
      }
    });

    test('動機類不參與比對 —— 它與課表內容無對應關係', () {
      // recommendPlan 根本沒有動機類的參數：簽章本身就擋住了。
      final plans = [plan('唯一', '徒手')];
      expect(pick(plans, equipment: '徒手')?.id, '唯一');
    });

    test('沒有任何計畫時回傳空值，不假裝推薦成功', () {
      expect(pick(const []), isNull);
    });

    test('適用條件為空的計畫視為不限，仍可被推薦', () {
      final plans = [plan('不限', '徒手')];
      expect(
        pick(plans,
                equipment: '徒手',
                experience: '進階（2 年以上）',
                goal: '減重')
            ?.id,
        '不限',
      );
    });
  });

  group('走一遍註冊前段', () {
    testWidgets('啟動 → 登入 → 手機驗證 → 條款', (t) async {
      t.view.physicalSize = const Size(393 * 3, 852 * 3);
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(const FitnessApp());
      await t.pumpAndSettle();

      await t.tap(find.text('我的').last);
      await t.pumpAndSettle();
      final list = find
          .descendant(
              of: find.byType(MoreScreen), matching: find.byType(Scrollable))
          .first;
      final entry = find.descendant(
          of: find.byType(MoreScreen), matching: find.text('註冊流程'));
      await t.scrollUntilVisible(entry, 120, scrollable: list);
      await t.pumpAndSettle();
      await t.tap(entry);
      await t.pumpAndSettle();

      // 啟動頁靠計時器自己走完 —— pumpAndSettle 只會推進到下一次排程的影格，
      // 推不動還沒到期的 Timer，故明確快轉 1.5 秒。
      expect(find.byType(LaunchScreen), findsOneWidget);
      await t.pump(const Duration(milliseconds: 1500));
      await t.pumpAndSettle();
      expect(find.byType(LaunchScreen), findsNothing);
      expect(find.text('歡迎回來'), findsOneWidget);

      // 號碼沒填完，發送鈕不可按
      expect(
        t.widget<AppButton>(find.widgetWithText(AppButton, '發送驗證碼')).onPressed,
        isNull,
      );

      // 格式錯的號碼被擋下，並以文字說明
      await t.enterText(find.byType(TextField).first, '0812345678');
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(AppButton, '發送驗證碼'));
      await t.pumpAndSettle();
      expect(find.textContaining('格式不正確'), findsOneWidget);
      expect(find.text('輸入驗證碼'), findsNothing);

      await t.enterText(find.byType(TextField).first, '0912345678');
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(AppButton, '發送驗證碼'));
      await t.pumpAndSettle();

      // 驗證頁：號碼分段呈現，未輸滿六碼時下一步不可按
      expect(find.text('已發送至 0912 345 678'), findsOneWidget);
      expect(
        t.widget<AppButton>(find.widgetWithText(AppButton, '下一步')).onPressed,
        isNull,
      );
      await t.enterText(find.byType(TextField).first, '4928');
      await t.pumpAndSettle();
      expect(
        t.widget<AppButton>(find.widgetWithText(AppButton, '下一步')).onPressed,
        isNull,
        reason: '四碼還不夠',
      );

      await t.enterText(find.byType(TextField).first, '492817');
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(AppButton, '下一步'));
      await t.pumpAndSettle();

      expect(find.widgetWithText(AppButton, '同意並建立帳號'), findsOneWidget);
    });

    testWidgets('第三方登入跳過簡訊驗證，並帶入電子郵件', (t) async {
      t.view.physicalSize = const Size(393 * 3, 852 * 3);
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(const FitnessApp());
      await t.pumpAndSettle();

      await t.tap(find.text('我的').last);
      await t.pumpAndSettle();
      final list = find
          .descendant(
              of: find.byType(MoreScreen), matching: find.byType(Scrollable))
          .first;
      final entry = find.descendant(
          of: find.byType(MoreScreen), matching: find.text('註冊流程'));
      await t.scrollUntilVisible(entry, 120, scrollable: list);
      await t.pumpAndSettle();
      await t.tap(entry);
      await t.pumpAndSettle();

      await t.pump(const Duration(milliseconds: 1500));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(AppButton, '使用 Apple 帳號繼續'));
      await t.pumpAndSettle();

      // 直接到條款，不經過驗證碼
      expect(find.text('輸入驗證碼'), findsNothing);
      expect(find.widgetWithText(AppButton, '同意並建立帳號'), findsOneWidget);
    });
  });

  group('問卷的選項格與往前', () {
    Future<void> toQuestions(WidgetTester t) async {
      t.view.physicalSize = const Size(393 * 3, 852 * 3);
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(const FitnessApp());
      await t.pumpAndSettle();

      await t.tap(find.text('我的').last);
      await t.pumpAndSettle();
      final list = find
          .descendant(
              of: find.byType(MoreScreen), matching: find.byType(Scrollable))
          .first;
      final entry = find.descendant(
          of: find.byType(MoreScreen), matching: find.text('註冊流程'));
      await t.scrollUntilVisible(entry, 120, scrollable: list);
      await t.pumpAndSettle();
      await t.tap(entry);
      await t.pumpAndSettle();
      await t.pump(const Duration(milliseconds: 1500));
      await t.pumpAndSettle();

      await t.tap(find.widgetWithText(AppButton, '使用 Apple 帳號繼續'));
      await t.pumpAndSettle();
      await t.tap(find.byType(AppSwitch));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(AppButton, '同意並建立帳號'));
      await t.pumpAndSettle();
    }

    testWidgets('第一題沒有上一步；之後每一題都有', (t) async {
      await toQuestions(t);
      expect(find.text('第 1／9'), findsOneWidget);
      expect(find.widgetWithText(AppButton, '上一步'), findsNothing,
          reason: '帳號已建立，第一題回不去');

      await t.tap(find.widgetWithText(AppButton, '下一步'));
      await t.pumpAndSettle();
      expect(find.text('第 2／9'), findsOneWidget);
      expect(find.widgetWithText(AppButton, '上一步'), findsOneWidget);
    });

    testWidgets('上一步會回到前一題，且已填的值還在', (t) async {
      await toQuestions(t);
      // 1 身高 → 2 體重 → 3 性別
      await t.tap(find.widgetWithText(AppButton, '下一步'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(AppButton, '下一步'));
      await t.pumpAndSettle();
      expect(find.text('你的性別？'), findsOneWidget);

      await t.tap(find.text('女'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(AppButton, '上一步'));
      await t.pumpAndSettle();
      expect(find.text('你的體重？'), findsOneWidget);

      await t.tap(find.widgetWithText(AppButton, '下一步'));
      await t.pumpAndSettle();
      // 回來時「女」仍是選中的：下一步可按就是證據
      expect(
        t.widget<AppButton>(find.widgetWithText(AppButton, '下一步')).onPressed,
        isNotNull,
      );
    });

    testWidgets('選項格等寬等高，且每格都有圖示', (t) async {
      await toQuestions(t);
      // 逐題走到「你的健身經驗？」——三個選項的字數差很多，最容易露出參差。
      // 身高、體重一進畫面就有預設值，直接下一步即可。
      Future<void> next() async {
        await t.tap(find.widgetWithText(AppButton, '下一步'));
        await t.pumpAndSettle();
      }

      await next(); // 1 身高 → 2 體重
      await next(); // 2 體重 → 3 性別
      await t.tap(find.text('男'));
      await t.pumpAndSettle();
      await next(); // 3 性別 → 4 生日
      // 生日用抽屜選年份，挑一個滿 13 歲的。
      // 年欄預設顯示 25 年前，點它開抽屜。
      await t.tap(find.text('${DateTime.now().year - 25}'));
      await t.pumpAndSettle();
      final sheet = find.byType(BottomSheet);
      final sheetScroll = find
          .descendant(of: sheet, matching: find.byType(Scrollable))
          .first;
      final year2000 = find.descendant(of: sheet, matching: find.text('2000'));
      await t.scrollUntilVisible(year2000, 200, scrollable: sheetScroll);
      await t.pumpAndSettle();
      await t.tap(year2000);
      await t.pumpAndSettle();
      await next(); // 4 生日 → 5 健身目標
      await t.tap(find.text('增肌'));
      await t.pumpAndSettle();
      await next(); // 5 健身目標 → 6 健身經驗

      expect(find.text('你的健身經驗？'), findsOneWidget);

      final tiles = find.byType(ChoiceGrid);
      expect(tiles, findsOneWidget);
      final grid = t.widget<ChoiceGrid>(tiles);
      expect(grid.options.length, 3);
      // 「新手（未滿 6 個月）」要被拆成主標與副標，否則格子高度會被撐開
      expect(grid.options.first.title, '新手');
      expect(grid.options.first.subtitle, '未滿 6 個月');
      for (final o in grid.options) {
        expect(o.icon, isNot(Icons.circle_outlined),
            reason: '${o.value} 沒有指定圖示');
      }

      // 等高要拿「有副標」與「沒副標」混在一起的那一題來驗 ——
      // 健身經驗三格都有副標，就算高度交給內容決定也會剛好一樣高，
      // 驗不出東西。器材那題的「徒手」沒有副標，才是真正的考題。
      await t.tap(find.text('新手'));
      await t.pumpAndSettle();
      await next(); // 6 健身經驗 → 7 每週天數
      await t.tap(find.text('3'));
      await t.pumpAndSettle();
      await next(); // 7 每週天數 → 8 每次時長
      await t.tap(find.text('30–60 分鐘'));
      await t.pumpAndSettle();
      await next(); // 8 每次時長 → 9 器材
      expect(find.text('你有哪些器材？'), findsOneWidget);

      final cards = find.descendant(
          of: find.byType(ChoiceGrid), matching: find.byType(AppCard));
      expect(cards, findsNWidgets(3));
      final boxes = [for (var i = 0; i < 3; i++) t.getSize(cards.at(i))];
      expect(boxes[1], boxes[0], reason: '「居家器材」與「健身房」高度須一致');
      expect(boxes[2], boxes[0], reason: '沒有副標的「徒手」也要一樣高');
    });

    testWidgets('375px 下選項格不溢位', (t) async {
      t.view.physicalSize = const Size(375 * 3, 812 * 3);
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(const FitnessApp());
      await t.pumpAndSettle();

      await t.tap(find.text('我的').last);
      await t.pumpAndSettle();
      final list = find
          .descendant(
              of: find.byType(MoreScreen), matching: find.byType(Scrollable))
          .first;
      final entry = find.descendant(
          of: find.byType(MoreScreen), matching: find.text('註冊流程'));
      await t.scrollUntilVisible(entry, 120, scrollable: list);
      await t.pumpAndSettle();
      await t.tap(entry);
      await t.pumpAndSettle();
      await t.pump(const Duration(milliseconds: 1500));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(AppButton, '使用 Apple 帳號繼續'));
      await t.pumpAndSettle();
      await t.tap(find.byType(AppSwitch));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(AppButton, '同意並建立帳號'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(AppButton, '下一步'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(AppButton, '下一步'));
      await t.pumpAndSettle();

      // 溢位時 Flutter 會丟例外，測試框架直接判定失敗 ——
      // 不需要（也不該）再寫一個永遠回傳 false 的假斷言。
      expect(find.text('你的性別？'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });
}
