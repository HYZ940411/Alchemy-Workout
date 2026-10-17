// 解除師徒關係之後，拜師頁整頁被「我的教官」佔住（2026-10-17 使用者回報）。
//
// 使用者看到的：畫面停在「師徒關係已解除／提出恢復師徒關係」，教官清單與
// 「我要成為教官」都不見了，於是申請不了別的教官、也找不到成為教官的入口。
//
// 規格只擋「解除後 3 天內與別人建立師徒關係」。看清單、申請成為教官都不在其中，
// 是畫面把整頁換掉、連帶藏起來的。
//
// 原因：`MentorScreen` 只看 `myInstructor != null` 就畫「我的教官」，
// 不分「生效中」與「已解除、冷卻中」。
//
// 另外兩個一起處理的：
//   - 冷卻中按「申請」被擋，理由卻寫「要先解除與 X 的師徒關係」——
//     那段關係早就解除了。
//   - 測試用的「師徒解除冷卻」開關按下去不會讓已經卡住的畫面放開
//     （只改旗標，沒有重新判斷），重新整理又會把旗標清掉。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/mentor_data.dart';
import 'package:fitness_app/data/public_profile.dart';
import 'package:fitness_app/domain/ability.dart';
import 'package:fitness_app/domain/clock.dart';
import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/screens/social/mentor_screen.dart';
import 'package:fitness_app/state/app_state.dart';
import 'package:fitness_app/widgets/common.dart';

/// 剛解除、還在 3 天冷卻期內的學徒。我的教官是「前教官」，清單裡另有「B 教官」。
AppState _released({Duration ago = const Duration(hours: 5)}) {
  final s = AppState(demo: false)
    ..myUid = 'u-hyz'
    ..displayName = 'HYZ'
    ..markMentorUnlocked();
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
  s.applyCloudBonds([
    CloudBond(
      id: 'u-old_u-hyz',
      mentorUid: 'u-old',
      apprenticeUid: 'u-hyz',
      mentorName: '前教官',
      apprenticeName: 'HYZ',
      state: MentorBondState.released,
      bondedAt: s.now.subtract(const Duration(days: 30)),
      releasedAt: s.now.subtract(ago),
      releasedReason: MentorReleaseReason.byApprentice,
    ),
  ]);
  return s;
}

void main() {
  tearDown(resetAppClock);

  Future<void> open(WidgetTester t, AppState s) async {
    await t.pumpWidget(AppScope(
      state: s,
      child: const MaterialApp(home: Scaffold(body: MentorScreen())),
    ));
    await t.pumpAndSettle();
  }

  Future<Finder> seen(WidgetTester t, Finder f) async {
    await t.scrollUntilVisible(f, 200,
        scrollable: find.byType(Scrollable).first);
    await t.pumpAndSettle();
    return f;
  }

  test('前提：測試資料真的是「冷卻中的已解除」', () {
    final s = _released();
    expect(s.mentorReleased, isTrue);
    expect(s.mentorCooldownLeft, greaterThan(Duration.zero));
    expect(s.myInstructor?.name, '前教官');
  });

  group('已解除、冷卻中 —— 拜師頁', () {
    testWidgets('解除面板還在，恢復的入口沒丟', (t) async {
      await open(t, _released());
      expect(find.text('師徒關係已解除'), findsOneWidget);
      expect(find.widgetWithText(AppButton, '提出恢復師徒關係'), findsOneWidget);
    });

    testWidgets('教官清單還看得到', (t) async {
      await open(t, _released());
      expect(await seen(t, find.text('B 教官')), findsOneWidget);
    });

    testWidgets('「我要成為教官」還找得到，而且按得下去', (t) async {
      await open(t, _released());
      final f = await seen(t, find.widgetWithText(AppButton, '我要成為教官'));
      expect(t.widget<AppButton>(f).onPressed, isNotNull);
    });

    testWidgets('冷卻中申請別的教官：按鈕按不下去，並且說的是「冷卻中」', (t) async {
      await open(t, _released());
      final f = await seen(t, find.widgetWithText(AppButton, '冷卻中'));
      expect(t.widget<AppButton>(f).onPressed, isNull,
          reason: '規格：解除後 3 天內不得與其他對象建立師徒關係');
    });

    testWidgets('舊的問答與任務紀錄還看得到（入口在解除面板上）', (t) async {
      await open(t, _released());
      await t.tap(find.widgetWithText(AppButton, '看與 前教官 的舊紀錄'));
      await t.pumpAndSettle();
      expect(await seen(t, find.text('待完成的師徒任務')), findsOneWidget);
    });
  });

  testWidgets('生效中的師徒關係：仍然是「我的教官」那一頁，沒有教官清單', (t) async {
    final s = AppState(demo: false)
      ..myUid = 'u-hyz'
      ..displayName = 'HYZ'
      ..markMentorUnlocked();
    s.applyCloudBonds([
      CloudBond(
        id: 'u-old_u-hyz',
        mentorUid: 'u-old',
        apprenticeUid: 'u-hyz',
        mentorName: '前教官',
        apprenticeName: 'HYZ',
        state: MentorBondState.active,
        bondedAt: s.now.subtract(const Duration(days: 3)),
      ),
    ]);
    expect(s.myInstructor, isNotNull);
    expect(s.mentorReleased, isFalse);

    await open(t, s);
    expect(await seen(t, find.text('待完成的師徒任務')), findsOneWidget);
    expect(find.text('我要成為教官'), findsNothing);
  });

  group('冷卻中被擋的理由', () {
    test('說的是冷卻，不是「要先解除」（已經解除了）', () {
      final s = _released();
      final why = s.mentorApplyBlockedReason(s.instructors.first)!;
      expect(why, contains('冷卻'));
      expect(why, isNot(contains('要先解除')));
    });

    test('生效中被擋的理由維持原樣', () {
      final s = AppState(demo: false)
        ..myUid = 'u-hyz'
        ..displayName = 'HYZ';
      s.applyCloudBonds([
        CloudBond(
          id: 'u-old_u-hyz',
          mentorUid: 'u-old',
          apprenticeUid: 'u-hyz',
          mentorName: '前教官',
          apprenticeName: 'HYZ',
          state: MentorBondState.active,
          bondedAt: s.now.subtract(const Duration(days: 3)),
        ),
      ]);
      final other = Instructor(
        name: '別人',
        uid: 'u-x',
        rank: 40,
        reputation: 10,
        apprentices: 0,
        apprenticeCap: 5,
        ability: const {},
        specialties: const ['增肌'],
        avgRating: 4.5,
        ratingCount: 3,
      );
      expect(s.mentorApplyBlockedReason(other), contains('要先解除與 前教官'));
    });
  });

  group('測試用開關「師徒解除冷卻」', () {
    test('已經卡住的人，打開的當下就放開', () {
      final s = _released()..toggleDeveloperMode();
      expect(s.mentorReleased, isTrue, reason: '前提：卡住了');

      s.toggleDevSkipMentorCooldown();

      expect(s.myInstructor, isNull);
      expect(s.mentorReleased, isFalse);
    });

    test('開發者模式沒開 → 打開開關也不放開', () {
      final s = _released();
      s.toggleDevSkipMentorCooldown();
      expect(s.myInstructor, isNotNull);
    });

    test('關掉開關不會憑空多出教官', () {
      final s = _released()..toggleDeveloperMode();
      s.toggleDevSkipMentorCooldown();
      s.toggleDevSkipMentorCooldown();
      expect(s.myInstructor, isNull);
    });
  });
}
