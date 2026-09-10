import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/design/components.dart';
import 'package:fitness_app/design/tokens.dart';
import 'package:fitness_app/domain/ability.dart';
import 'package:fitness_app/domain/novice.dart';
import 'package:fitness_app/domain/platform_config.dart';
import 'package:fitness_app/main.dart';
import 'package:fitness_app/screens/me/account_delete_screen.dart';
import 'package:fitness_app/screens/me/more_screen.dart';
import 'package:fitness_app/screens/train/novice_task_screen.dart';
import 'package:fitness_app/state/app_state.dart';

// 對比一律算出來，不用眼睛看。沿用色票測試那份 WCAG 相對亮度實作。
import 'palette_test.dart' show contrast;

void main() {
  group('新手任務：三選一與四個關卡', () {
    test('開始與選擇是兩個不同的決定 —— 沒開始就選不了', () {
      final s = AppState();
      s.selectNovice('n_squat');
      expect(s.noviceSelected, isNull, reason: '未開始前不進入該次執行');

      s.startNovice();
      expect(s.noviceStarted, isTrue);
      s.selectNovice('n_squat');
      expect(s.noviceSelected, 'n_squat');
    });

    test('選定後未勾選完成前可改選，覆蓋原值', () {
      final s = AppState()..startNovice();
      s.selectNovice('n_squat');
      s.selectNovice('n_plank');
      expect(s.noviceSelected, 'n_plank');
    });

    test('勾選可取消 —— 誤觸而失去引導正好違背它存在的目的', () {
      final s = AppState()..startNovice();
      s.selectNovice('n_squat');
      s.toggleNoviceCheck();
      expect(s.noviceChecked, isTrue);
      s.toggleNoviceCheck();
      expect(s.noviceChecked, isFalse);
      s.finishNovice();
      expect(s.noviceFinished, isFalse, reason: '取消勾選後即不可完成');
    });

    test('完成須手動按下，非勾選後自動發生', () {
      final s = AppState()..startNovice();
      s.selectNovice('n_squat');
      s.toggleNoviceCheck();
      expect(s.noviceFinished, isFalse, reason: '勾了還不算完成');
      s.finishNovice();
      expect(s.noviceFinished, isTrue);
    });

    test('不產生任何下游資料 —— 它形似一次訓練，但不是一次訓練', () {
      final s = AppState();
      final before = (
        s.totalWorkouts,
        s.trainingStreakDays,
        s.weeklyScore,
        s.history.length,
      );
      s
        ..startNovice()
        ..selectNovice('n_squat')
        ..toggleNoviceCheck()
        ..finishNovice();
      expect(
        (s.totalWorkouts, s.trainingStreakDays, s.weeklyScore, s.history.length),
        before,
      );
    });

    test('拉高的是初始值（地板），腿與核心由此不得低於 30', () {
      final s = AppState();
      expect(s.initialOf(Dim.legs), kInitialPoints);
      s
        ..startNovice()
        ..selectNovice('n_plank')
        ..toggleNoviceCheck()
        ..finishNovice();
      expect(s.initialOf(Dim.legs), kNoviceLegCoreInitial);
      expect(s.initialOf(Dim.core), kNoviceLegCoreInitial);
      expect(s.initialOf(Dim.chest), kInitialPoints, reason: '其餘四維維持 10');
      expect(s.points[Dim.legs]!, greaterThanOrEqualTo(kNoviceLegCoreInitial));
    });

    test('完成即解鎖社群互動功能，且單調遞增', () {
      final s = AppState();
      expect(s.socialUnlocked, isFalse);
      s
        ..startNovice()
        ..selectNovice('n_squat')
        ..toggleNoviceCheck()
        ..finishNovice();
      expect(s.socialUnlocked, isTrue);
    });

    test('完成不發獎；領取是另一個 Command，且只領一次', () {
      final s = AppState();
      final exp = s.totalExp;
      final coins = s.coins;
      final ai = s.aiPermanent;
      s
        ..startNovice()
        ..selectNovice('n_squat')
        ..toggleNoviceCheck()
        ..finishNovice();
      expect(s.totalExp, exp, reason: '未領取者一直掛在新手任務清單頁');

      final r = s.claimNoviceReward()!;
      expect(r, (exp: kNoviceExp, coins: kNoviceCoin, ai: kNoviceAiCredits));
      expect(s.totalExp, exp + kNoviceExp);
      expect(s.coins, coins + kNoviceCoin);
      expect(s.aiPermanent, ai + kNoviceAiCredits,
          reason: 'AI 為永久點數，不進月度額度');

      expect(s.claimNoviceReward(), isNull);
      expect(s.totalExp, exp + kNoviceExp);
    });

    test('範本為單一動作、單一組，目標量由範本給定', () {
      expect(kNoviceTemplate.length, 3);
      expect(kNoviceTemplate.first.summary, contains('1 組'));
    });
  });

  group('新手任務進行頁', () {
    Future<void> open(WidgetTester t) async {
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
          of: find.byType(MoreScreen), matching: find.text('新手 / 回歸任務'));
      await t.scrollUntilVisible(entry, 120, scrollable: list);
      await t.pumpAndSettle();
      await t.tap(entry);
      await t.pumpAndSettle();
      await t.tap(find.text('開始新手任務'));
      await t.pumpAndSettle();
    }

    testWidgets('三個候選都列出，選一個才能勾，勾了才能完成', (t) async {
      await open(t);
      expect(find.byType(NoviceTaskScreen), findsOneWidget);
      for (final c in kNoviceTemplate) {
        expect(find.text(c.name), findsOneWidget);
      }
      expect(find.byType(AppCheckbox), findsNothing, reason: '沒選就沒有那一組');

      final btn = find.widgetWithText(AppButton, '完成這項任務');
      expect(t.widget<AppButton>(btn).onPressed, isNull);

      await t.tap(find.text('伏地挺身'));
      await t.pumpAndSettle();
      expect(find.byType(AppCheckbox), findsOneWidget);
      expect(t.widget<AppButton>(btn).onPressed, isNull, reason: '還沒勾');

      await t.tap(find.byType(AppCheckbox));
      await t.pumpAndSettle();
      expect(t.widget<AppButton>(btn).onPressed, isNotNull);
    });

    testWidgets('勾選後鎖住改選，取消勾選才放開', (t) async {
      await open(t);
      await t.tap(find.text('伏地挺身'));
      await t.pumpAndSettle();
      await t.tap(find.byType(AppCheckbox));
      await t.pumpAndSettle();

      await t.tap(find.text('棒式'));
      await t.pumpAndSettle();
      expect(find.textContaining('伏地挺身'), findsWidgets,
          reason: '勾的是「所選的那一項已完成」，還能改選就指向了另一件事');

      await t.tap(find.byType(AppCheckbox));
      await t.pumpAndSettle();
      await t.tap(find.text('棒式'));
      await t.pumpAndSettle();
      expect(find.textContaining('棒式　30 秒'), findsOneWidget);
    });

    testWidgets('完成後回到清單頁，獎勵在那裡等著領', (t) async {
      await open(t);
      await t.tap(find.text('徒手深蹲'));
      await t.pumpAndSettle();
      await t.tap(find.byType(AppCheckbox));
      await t.pumpAndSettle();
      await t.tap(find.text('完成這項任務'));
      await t.pumpAndSettle();

      // 引導收尾第一步接在完成之後，且擋不住你 —— 跳過即回到清單頁。
      expect(find.text('偏好訓練時段'), findsWidgets);
      await t.tap(find.text('稍後再選'));
      await t.pumpAndSettle();

      expect(find.text('新手任務已完成'), findsOneWidget);
      final claim = find.textContaining('領取獎勵');
      expect(claim, findsOneWidget);
      await t.tap(claim);
      await t.pumpAndSettle();
      expect(find.textContaining('AI 永久點數'), findsOneWidget);
    });
  });

  group('個人主頁', () {
    testWidgets('頁首給的是「你是誰、練成什麼樣子」，不是設定清單的封面', (t) async {
      t.view.physicalSize = const Size(393 * 3, 852 * 3);
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(const FitnessApp());
      await t.pumpAndSettle();
      await t.tap(find.text('我的').last);
      await t.pumpAndSettle();

      expect(find.text('貼文'), findsOneWidget);
      expect(find.text('粉絲'), findsOneWidget);
      expect(find.text('關注'), findsOneWidget);
      expect(find.text('連續訓練'), findsOneWidget);
      expect(find.text('累計訓練量'), findsOneWidget);
      expect(find.textContaining('階級 '), findsWidgets);
    });

    testWidgets('大頭像看得見 —— 底色不可等於頁面底色', (t) async {
      t.view.physicalSize = const Size(393 * 3, 852 * 3);
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(const FitnessApp());
      await t.pumpAndSettle();
      await t.tap(find.text('我的').last);
      await t.pumpAndSettle();

      final fill = t
          .widget<CircleAvatar>(find.byType(CircleAvatar).first)
          .backgroundColor!;
      // 88px 的圓若與頁面底色同色，畫面上只會剩一個浮著的字。
      expect(contrast(fill, C.bgPage), greaterThan(3.0));
      // 圓上的字一律交給 onFill 決定，不寫死。
      final letter = t.widget<Text>(find.descendant(
          of: find.byType(CircleAvatar).first, matching: find.byType(Text)));
      expect(letter.style!.color, C.onFill(fill));
      expect(contrast(letter.style!.color!, fill), greaterThan(4.5));
    });

    testWidgets('粉絲數點得進關注／粉絲清單', (t) async {
      t.view.physicalSize = const Size(393 * 3, 852 * 3);
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(const FitnessApp());
      await t.pumpAndSettle();
      await t.tap(find.text('我的').last);
      await t.pumpAndSettle();
      await t.tap(find.text('粉絲'));
      await t.pumpAndSettle();
      expect(find.textContaining('粉絲成就'), findsOneWidget);
    });
  });

  group('帳號刪除流程', () {
    setUp(platformConfig.reset);
    tearDown(platformConfig.reset);

    test('冷靜期為平台級可調參數，預設 30 天', () {
      expect(kDeletionCoolingDays, 30);
    });

    test('申請當下鎖住冷靜期長度 —— 管理員改參數不延長別人的期限', () {
      final s = AppState()..requestDeletion();
      final before = s.deletionDaysLeft;
      platformConfig.group('account').param('coolingDays').value = 90;
      expect(s.deletionDaysLeft, before);
    });

    test('待刪除的語意是帳號停用，不是登不進去；取消即回復正常', () {
      final s = AppState();
      expect(s.pendingDeletion, isFalse);
      s.requestDeletion();
      expect(s.pendingDeletion, isTrue);
      expect(s.deletionDaysLeft, kDeletionCoolingDays);
      s.cancelDeletion();
      expect(s.pendingDeletion, isFalse);
      expect(s.deletionDaysLeft, isNull);
    });

    test('冷靜期間計時照常，取消後不補償、不回捲', () {
      final s = AppState()..requestDeletion();
      final decays = s.decayLog.length;
      s.advanceDemoClock(const Duration(days: 20));
      expect(s.decayLog.length, greaterThan(decays),
          reason: '能力值退步不是懲罰，是量測');
      final after = s.decayLog.length;
      s.cancelDeletion();
      expect(s.decayLog.length, after, reason: '不回捲');
    });

    testWidgets('申請頁：勾了才給申請，且講明需時多久與哪些資料暫時保留', (t) async {
      t.view.physicalSize = const Size(393 * 3, 852 * 3);
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final s = AppState();
      await t.pumpWidget(AppScope(
        state: s,
        child: const MaterialApp(home: AccountDeleteScreen()),
      ));
      await t.pumpAndSettle();

      expect(find.text('刪除後有 $kDeletionCoolingDays 天冷靜期'), findsOneWidget);
      expect(find.textContaining('貼文、留言與私訊'), findsOneWidget,
          reason: '使用者產生、已分享給他人的內容也要刪');
      expect(find.text('會暫時保留的資料'), findsOneWidget);
      expect(find.textContaining('結案後一併清除'), findsOneWidget);

      final btn = find.widgetWithText(AppButton, '申請刪除帳號');
      expect(t.widget<AppButton>(btn).onPressed, isNull);

      await t.scrollUntilVisible(find.byType(AppCheckbox), 200);
      await t.pumpAndSettle();
      await t.tap(find.byType(AppCheckbox));
      await t.pumpAndSettle();
      expect(t.widget<AppButton>(btn).onPressed, isNotNull);

      await t.tap(btn);
      await t.pumpAndSettle();
      expect(find.text('確認申請刪除帳號？'), findsOneWidget);
      await t.tap(find.widgetWithText(AppButton, '申請刪除'));
      await t.pumpAndSettle();
      expect(s.pendingDeletion, isTrue);
      expect(find.text('帳號待刪除'), findsOneWidget);
    });

    testWidgets('待刪除時「我的」著陸頁掛出橫幅，不藏在設定裡', (t) async {
      t.view.physicalSize = const Size(393 * 3, 852 * 3);
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final s = AppState()..requestDeletion();
      await t.pumpWidget(AppScope(
        state: s,
        child: const MaterialApp(home: Scaffold(body: MoreScreen())),
      ));
      await t.pumpAndSettle();
      expect(find.textContaining('帳號待刪除'), findsOneWidget);
    });
  });
}
