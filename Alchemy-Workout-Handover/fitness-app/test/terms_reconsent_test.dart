// 條款改版後，既有使用者於下次登入時須重新同意（2026-09-24）。
//
// 規格三處都寫著這件事：
//   ·〈註冊流程〉「條款改版後，既有使用者於下次登入時須重新同意，
//     本 Event 再次發生並更新版本」
//   ·〈01_Command清單〉「同意服務條款（含條款改版後的重新同意）」
//   ·〈02_Aggregate定義〉「已同意條款版本 … 版本落後於現行條款者，
//     下次登入須重新同意」
//
// 但使用者 Aggregate **根本沒有那個欄位** —— 2026-09-18 條文由 v3.2 升為
// v4.0，沒有任何既有使用者被要求重新同意。條款本身寫明了這件事會發生，
// 所以那是一個對外承諾了、實際沒做的功能。
//
// **這一組規則擋在所有人的登入路上**，寫錯會讓全部使用者進不去 App，
// 所以除了「該擋的有擋」，也要釘「不該擋的不能擋」。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/registration.dart';
import 'package:fitness_app/screens/signup/terms_reconsent_screen.dart';
import 'package:fitness_app/state/app_state.dart';
import 'package:fitness_app/widgets/common.dart';

void main() {
  group('要不要重新同意', () {
    test('版本落後就要', () {
      final s = AppState()..agreedTermsVersion = 'v3.2';
      expect(s.termsReconsentNeeded, isTrue);
    });

    test('版本相同就不要', () {
      final s = AppState()..agreedTermsVersion = kTermsVersion;
      expect(s.termsReconsentNeeded, isFalse);
    });

    test('查無版本＝沒同意過，也要', () {
      // 這個欄位 2026-09-24 才加，在那之前的存檔一律沒有這一項 ——
      // 而他們實際同意的是 v3.2。當成「已同意現行版」等於替他們按了同意鍵。
      final s = AppState()..agreedTermsVersion = null;
      expect(s.termsReconsentNeeded, isTrue);
    });

    test('還沒註冊完的人不擋 —— 他本來就會在註冊流程裡遇到條款頁', () {
      final s = AppState()
        ..signUpCompleted = false
        ..agreedTermsVersion = null;
      expect(s.termsReconsentNeeded, isFalse, reason: '擋兩次等於多一道');
    });

    test('示範用身分預設就是已同意 —— 直接 AppState() 不該跳條款', () {
      expect(AppState().termsReconsentNeeded, isFalse);
    });
  });

  group('同意之後', () {
    test('記下現行版本，下次登入不再要求', () {
      final s = AppState()..agreedTermsVersion = 'v3.2';
      s.agreeTerms();
      expect(s.agreedTermsVersion, kTermsVersion);
      expect(s.termsReconsentNeeded, isFalse);
    });

    test('註冊完成時一併記下 —— 否則他下次登入又被要求一次', () {
      final s = AppState()..agreedTermsVersion = null;
      // `completeSignUp()` 開頭是 `if (!draft.complete) return;`，
      // 十項要全填畢才進得去。
      s.signUpDraft
        ..nickname = '阿昶'
        ..gender = '男'
        ..birthday = DateTime(1995, 5, 5)
        ..heightCm = 175
        ..weightKg = 70
        ..daysPerWeek = 3
        ..duration = '30–60 分鐘'
        ..commonGoal = '增肌'
        ..experience = '半年以下'
        ..equipment
        ..equipment.clear();
      s.signUpDraft.equipment.add('健身房');
      expect(s.signUpDraft.complete, isTrue);

      s.completeSignUp();
      expect(s.agreedTermsVersion, kTermsVersion);
      expect(s.termsReconsentNeeded, isFalse);
    });
  });

  group('存檔', () {
    test('同意的版本存得下、讀得回', () {
      final a = AppState()..agreedTermsVersion = 'v3.2';
      final b = AppState()..applySnapshot(a.toSnapshot());
      expect(b.agreedTermsVersion, 'v3.2');
      expect(b.termsReconsentNeeded, isTrue);
    });

    test('舊存檔沒有這個欄位時讀成空值，不是沿用預設', () {
      final s = AppState();
      final old = Map<String, dynamic>.from(s.toSnapshot())
        ..remove('agreedTermsVersion');
      final b = AppState()..applySnapshot(old);
      expect(b.agreedTermsVersion, isNull);
      expect(b.termsReconsentNeeded, isTrue, reason: '舊使用者同意的是舊版本');
    });
  });

  group('版本號只有一個來源', () {
    test('註冊草稿用的就是 kTermsVersion', () {
      // 兩個地方各寫一個版本號的話，改條文時只改到一個，
      // 整套「改版要重新同意」就會安靜地不觸發。
      expect(SignUpDraft().termsVersion, kTermsVersion);
    });
  });

  group('兩個入口都要有這道閘門', () {
    test('TermsGate 在兩處都用得到', () {
      // `main.dart` 有分支：沒接 Firebase 走 `FirstRunGate`，
      // 接了走 `AuthGate._SignedInHome`。2026-09-24 第一版只改了前者 ——
      // **於是真正在線上跑的那條路徑完全沒有這道閘門**，使用者登入後
      // 看不到條款頁。這條測試釘的是「兩邊都指向同一個 widget」。
      final main = File('lib/main.dart').readAsStringSync();
      final gate = File('lib/screens/auth_gate.dart').readAsStringSync();
      expect(main, contains('TermsGate()'),
          reason: 'FirstRunGate 那條路要經過條款閘門');
      expect(gate, contains('TermsGate()'),
          reason: 'AuthGate 那條路也要 —— 那才是線上實際走的');
      // 兩邊都不該再各自寫一份判斷。
      expect(main.contains('termsReconsentNeeded'), isFalse,
          reason: '判斷只該在 TermsGate 裡一份');
      expect(gate.contains('termsReconsentNeeded'), isFalse);
    });
  });

  group('畫面', () {
    testWidgets('同意鍵要先勾選才按得下去', (t) async {
      final s = AppState()..agreedTermsVersion = 'v3.2';
      var agreed = false;
      await t.pumpWidget(AppScope(
        state: s,
        child: MaterialApp(
          home: TermsReconsentScreen(onAgreed: () => agreed = true),
        ),
      ));
      await t.pumpAndSettle();

      final button = t.widget<AppButton>(find.byType(AppButton));
      expect(button.onPressed, isNull, reason: '沒勾就按不下去');
      expect(agreed, isFalse);
    });

    testWidgets('沒有「不同意」—— 規格沒寫拒絕的後果', (t) async {
      final s = AppState()..agreedTermsVersion = 'v3.2';
      await t.pumpWidget(AppScope(
        state: s,
        child: MaterialApp(
          home: TermsReconsentScreen(onAgreed: () {}),
        ),
      ));
      await t.pumpAndSettle();

      // 三份規格文件都沒提既有使用者拒絕了要怎麼辦（登出？轉唯讀？）。
      // 這裡只實作規格寫到的部分，不替它補一個沒有的分支。
      expect(find.text('不同意'), findsNothing);
      expect(find.text('拒絕'), findsNothing);
    });

    testWidgets('講得出為什麼跳出來，並說明先前同意的版本', (t) async {
      final s = AppState()..agreedTermsVersion = 'v3.2';
      await t.pumpWidget(AppScope(
        state: s,
        child: MaterialApp(
          home: TermsReconsentScreen(onAgreed: () {}),
        ),
      ));
      await t.pumpAndSettle();

      // 不說的話，使用者以為自己被登出了、或是 App 壞了。
      expect(find.textContaining('條款內容有更新'), findsOneWidget);
      expect(find.textContaining('v3.2'), findsOneWidget);
    });
  });
}
