// 拜師按鈕送出之後的狀態（使用者 2026-09-29 指出）。
//
// 原本送出後仍是主要樣式（亮色），而且**按得下去** ——
// 按下去跑的是 `acceptMentorApplication()`，也就是「對方已接受」。
// 那是**示範用的捷徑接在正式畫面上**：真使用者按一下，
// 師徒關係就單方面建立了，教官那側從頭到尾沒有同意過。
//
// 使用者指出的是顏色。查下去發現顏色只是表層。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/public_profile.dart';
import 'package:fitness_app/domain/ability.dart';
import 'package:fitness_app/screens/social/mentor_screen.dart';
import 'package:fitness_app/state/app_state.dart';
import 'package:fitness_app/widgets/common.dart';

void main() {
  Future<void> open(WidgetTester t, AppState s) async {
    await t.pumpWidget(AppScope(
      state: s,
      child: const MaterialApp(home: MentorScreen()),
    ));
    await t.pumpAndSettle();
  }

  /// 畫面上那顆拜師按鈕。
  ///
  /// **先捲到看得見為止。** 拜師清單在「我要成為教官」那一區下面，
  /// 不捲的話它根本沒被建出來 —— `find` 回報「沒有」，
  /// 而那與「真的沒有」長得一模一樣。
  Future<AppButton> buttonOf(WidgetTester t, String label) async {
    final target = find.widgetWithText(AppButton, label).first;
    await t.scrollUntilVisible(target, 200,
        scrollable: find.byType(Scrollable).first);
    await t.pumpAndSettle();
    return t.widget<AppButton>(target);
  }

  testWidgets('還沒申請 → 主要樣式、按得下去', (t) async {
    final s = AppState();
    await open(t, s);
    final b = await buttonOf(t, '申請師徒關係');
    expect(b.kind, BtnKind.primary);
    expect(b.onPressed, isNotNull);
  });

  testWidgets('已申請 → 次要樣式', (t) async {
    final s = AppState();
    s.applyMentor(s.instructors.first);
    await open(t, s);
    final b = await buttonOf(t, '已申請');
    expect(b.kind, BtnKind.secondary,
        reason: '送出之後它不再是這一頁的主要動作');
  });

  testWidgets('真帳號按「已申請」不會單方面建立師徒關係', (t) async {
    // 真帳號要先解鎖師徒（新手任務五件互動），否則整頁是鎖住的。
    final s = AppState(demo: false)..markMentorUnlocked();
    // **用 App 真正的路徑建教官清單**（公開檔案 → `_applyInstructor`），
    // 不要手捏一個 `Instructor` —— 手捏的很容易漏掉卡片會用到的欄位，
    // 那樣測到的是我捏的東西，不是這個畫面。
    s.applyPublicProfiles([
      PublicProfile(
        uid: 'u-b',
        displayName: 'B 教官',
        rank: 13,
        grade: 'B',
        ability: {for (final d in Dim.values) d: 30},
        followers: 0,
        isInstructor: true,
        reputation: 100,
        apprentices: 0,
        apprenticeCap: 5,
      ),
    ]);
    s.applyMentor(s.instructors.first);
    expect(s.myInstructor, isNull, reason: '前提：還沒有教官');

    await open(t, s);
    expect((await buttonOf(t, '已申請')).onPressed, isNull,
        reason: '按下去會跑「對方已接受」—— 那是示範捷徑，不該接在正式畫面上');
    expect(s.myInstructor, isNull);
  });

  testWidgets('示範模式保留那個捷徑 —— 沒有第二個人可以按接受', (t) async {
    final s = AppState();
    s.applyMentor(s.instructors.first);
    await open(t, s);
    expect((await buttonOf(t, '已申請')).onPressed, isNotNull,
        reason: '拿掉的話那條流程在示範裡走不完');
  });
}
