// 「綜合能力等級對外可見」關掉時，別人不能看到綜合等級（第二批第 3 項，真人實測 V3）。
//
// 兩個開關各自獨立：只關綜合等級，六維仍公開。但檢視端的 `gradeOf()` 原本看到六維
// 就自己用六維算一個綜合等級出來，無視檔案上 `grade` 是空的。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/public_profile.dart';
import 'package:fitness_app/domain/ability.dart';
import 'package:fitness_app/domain/social.dart';
import 'package:fitness_app/screens/social/find_people_screen.dart';
import 'package:fitness_app/state/app_state.dart';

const _pts = {
  Dim.chest: 486,
  Dim.back: 452,
  Dim.legs: 318,
  Dim.shoulders: 274,
  Dim.arms: 305,
  Dim.core: 190,
};

AppState _viewerOf({
  required bool abilityPublic,
  required bool overallGradePublic,
  bool isInstructor = false,
}) {
  final s = AppState(demo: false)..myUid = 'viewer';
  s.applyPublicProfiles([
    PublicProfile.of(
      uid: 'u-a',
      displayName: '阿甲',
      rank: 40,
      points: _pts,
      abilityPublic: abilityPublic,
      overallGradePublic: overallGradePublic,
      isInstructor: isInstructor,
    ),
  ]);
  return s;
}

void main() {
  test('只關綜合等級：看得到六維，看不到綜合等級', () {
    final s = _viewerOf(abilityPublic: true, overallGradePublic: false);
    expect(s.abilityOf('阿甲', uid: 'u-a'), isNotNull);
    expect(s.gradeOf('阿甲', uid: 'u-a'), isNull,
        reason: '不能因為看得到六維就自己算一個');
  });

  test('只關六維：看不到六維，看得到綜合等級', () {
    final s = _viewerOf(abilityPublic: false, overallGradePublic: true);
    expect(s.abilityOf('阿甲', uid: 'u-a'), isNull);
    expect(s.gradeOf('阿甲', uid: 'u-a'), overallGrade(_pts));
  });

  test('兩個都開：都看得到，且綜合等級與六維算出來的一致', () {
    final s = _viewerOf(abilityPublic: true, overallGradePublic: true);
    expect(s.gradeOf('阿甲', uid: 'u-a'), overallGrade(_pts));
  });

  test('兩個都關：都看不到', () {
    final s = _viewerOf(abilityPublic: false, overallGradePublic: false);
    expect(s.abilityOf('阿甲', uid: 'u-a'), isNull);
    expect(s.gradeOf('阿甲', uid: 'u-a'), isNull);
  });

  test('教官：兩個開關都失效，照樣看得到', () {
    final s = _viewerOf(
        abilityPublic: false, overallGradePublic: false, isInstructor: true);
    expect(s.gradeOf('阿甲', uid: 'u-a'), overallGrade(_pts));
    expect(s.abilityOf('阿甲', uid: 'u-a'), isNotNull);
  });

  test('自己看自己：不受自己的開關影響', () {
    final s = AppState(demo: false)
      ..myUid = 'me'
      ..displayName = '我';
    s.setFlag(overall: false, ability: false);
    expect(s.gradeOf('我', uid: 'me'), overallGrade(s.points));
  });

  group('清單上也不能印出隱藏的綜合等級（真人實測 V3 的第二個洞）', () {
    test('對方沒公開綜合等級：併進來的人，綜合等級是空值而不是 E', () {
      final s = _viewerOf(abilityPublic: true, overallGradePublic: false);
      final u = s.socialUsers.firstWhere((x) => x.name == '阿甲');
      expect(u.grade, isNull, reason: '原本墊一個 E，找人與關注清單照樣印「綜合 E」');
    });

    test('清單副標題：空值整段不印，有值才印', () {
      expect(gradeSubtitle(null), '');
      expect(gradeSubtitle('B+'), '　·　綜合 B+');
    });

    testWidgets('找人清單：隱藏綜合等級的人不出現「綜合」兩個字', (t) async {
      final s = _viewerOf(abilityPublic: true, overallGradePublic: false);
      await t.pumpWidget(AppScope(
        state: s,
        child: const MaterialApp(home: FindPeopleScreen()),
      ));
      await t.pumpAndSettle();

      expect(find.textContaining('阿甲'), findsWidgets);
      expect(find.textContaining('綜合'), findsNothing);
    });

    testWidgets('找人清單：有公開的人照樣印出綜合等級', (t) async {
      final s = _viewerOf(abilityPublic: true, overallGradePublic: true);
      await t.pumpWidget(AppScope(
        state: s,
        child: const MaterialApp(home: FindPeopleScreen()),
      ));
      await t.pumpAndSettle();

      expect(find.textContaining('綜合 ${overallGrade(_pts)}'), findsOneWidget);
    });
  });
}
