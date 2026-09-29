// 一個數字只能服務一個主體。
//
// 今天已經抓到兩個這種形狀：學徒給教官的評分加到了評分者自己的聲望上；
// 我買的東西與後台的訂單是兩份沒接起來的清單。這支釘住第三個，
// 並把同型的其餘候選一併驗過。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/screens/social/mentor_screen.dart';
import 'package:fitness_app/domain/social.dart';

import 'package:fitness_app/domain/ability.dart';
import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/domain/inbound.dart';
import 'package:fitness_app/state/app_state.dart';

void main() {
  group('教官的帶徒名額', () {
    // **2026-09-29 使用者裁決：待回應的申請不再佔名額。**
    //
    // 原模型是「已建立的關係數 ＋ 申請中的申請數」。它讓一位申請人被
    // 別人尚未被回應的申請擋在門外，而那些申請可能全部會被拒絕。
    // 現在的模型：名額佔用數 ＝ **已建立的師徒關係數**。
    // 超收由教官接受當下的 Precondition 擋下（同團隊那一套）。
    //
    // [Instructor.apprentices] 只是那位教官與**別人**的關係數。

    test('送出申請不佔名額 —— 對方還沒答應', () {
      final s = AppState()..myInstructor = null;
      final i = s.instructors.firstWhere((x) => x.apprentices < x.apprenticeCap);
      final before = s.apprenticeCountOf(i);
      expect(s.applyMentor(i), isTrue);
      expect(s.apprenticeCountOf(i), before,
          reason: '數字要等關係真的建立才動');
    });

    test('拜師成功後，他的帶徒人數要真的多一個', () {
      final s = AppState()..myInstructor = null;
      final i = s.instructors.firstWhere((x) => x.apprentices < x.apprenticeCap);
      final before = s.apprenticeCountOf(i);
      s.applyMentor(i);
      s.acceptMentorApplication(i);
      expect(s.apprenticeCountOf(i), before + 1,
          reason: '我已經是他的學徒了，畫面上不該還寫著原本的數字');
      expect(s.myInstructor?.name, i.name);
    });

    test('接受不會把申請與關係重複算成兩格', () {
      final s = AppState()..myInstructor = null;
      final i = s.instructors.firstWhere((x) => x.apprentices < x.apprenticeCap);
      final before = s.apprenticeCountOf(i);
      s.applyMentor(i);
      s.acceptMentorApplication(i);
      expect(s.apprenticeCountOf(i), before + 1, reason: '同一個人只佔一格');
    });

    test('拒絕與逾期都釋放名額', () {
      for (final verdict in [RequestVerdict.rejected, RequestVerdict.expired]) {
        final s = AppState()..myInstructor = null;
        final i =
            s.instructors.firstWhere((x) => x.apprentices < x.apprenticeCap);
        final before = s.apprenticeCountOf(i);
        s.applyMentor(i);
        s.resolveMentorApplication(i.name, verdict);
        expect(s.apprenticeCountOf(i), before,
            reason: '三個終止狀態皆釋放所佔用的帶徒名額（$verdict）');
      }
    });

    test('本來就滿的教官申請不了', () {
      final s = AppState()..myInstructor = null;
      final full =
          s.instructors.firstWhere((x) => x.apprentices >= x.apprenticeCap);
      expect(s.apprenticeCountOf(full), greaterThanOrEqualTo(full.apprenticeCap));
      expect(s.mentorApplyBlockedReason(full), contains('名額已滿'));
      expect(s.applyMentor(full), isFalse);
    });

    test('送出申請之後，看到的是「等對方回應」', () {
      final s = AppState()..myInstructor = null;
      // 只差一格就滿。申請不再佔名額，所以送出之後那一格仍是空的。
      final i = Instructor(
        name: '快滿了的教官',
        rank: 40,
        reputation: 100,
        apprentices: 3,
        apprenticeCap: 4,
        ability: const {},
        specialties: const ['增肌'],
        avgRating: 4.5,
        ratingCount: 10,
      );
      s.instructors.insert(0, i);
      expect(s.mentorApplyBlockedReason(i), isNull);
      expect(s.applyMentor(i), isTrue);
      expect(s.apprenticeCountOf(i), i.apprenticeCap - 1,
          reason: '申請不佔名額，最後那一格還在');
      expect(s.mentorApplyBlockedReason(i), contains('等對方回應'),
          reason: '已經送出的人該看到的是「等回應」，不是「再送一次」');
    });

    test('別人把名額佔滿時才說滿了', () {
      final s = AppState()..myInstructor = null;
      final i = Instructor(
        name: '滿編的教官',
        rank: 40,
        reputation: 100,
        apprentices: 4,
        apprenticeCap: 4,
        ability: const {},
        specialties: const ['增肌'],
        avgRating: 4.5,
        ratingCount: 10,
      );
      s.instructors.insert(0, i);
      expect(s.mentorApplyBlockedReason(i), contains('名額已滿'));
      expect(s.applyMentor(i), isFalse);
    });

    test('拜師成功之後，推導值才動 —— 而那個儲存欄位永遠不該被我改動', () {
      final s = AppState()..myInstructor = null;
      final i = s.instructors.firstWhere((x) => x.apprentices < x.apprenticeCap);
      final stored = i.apprentices;

      s.applyMentor(i);
      expect(s.apprenticeCountOf(i), stored, reason: '只是申請，還沒成立');

      s.acceptMentorApplication(i);
      expect(i.apprentices, stored,
          reason: '那個欄位是「他與別人的關係數」，本來就不該被我改動');
      expect(s.apprenticeCountOf(i), stored + 1,
          reason: '會動的是推導值 —— 兩者分開，主體才不會混在一起');
    });
  });

  group('畫面上的帶徒人數', () {
    // 擋人的判定裡，推導值與那個假資料欄位其實證明等價 ——
    // 要讓推導值超過而儲存值沒超過，得是「我已經是他的學徒」，
    // 但那會被上一個條件（一次只能有一位教官）先擋掉。
    // **會被看見的差別在畫面上**：拜師成功後那行數字有沒有跟著動。
    // **2026-09-29 使用者裁決：申請不再佔名額，標籤改為「學徒 N / M」。**
    //
    // 原本送出申請當下數字就 +1，而對方還沒答應 —— 那行字在說一件
    // 不是事實的事。現在它要等關係真的建立才動。
    testWidgets('送出申請時數字不動，拜師成功才動', (t) async {
      t.view.physicalSize = const Size(393 * 3, 852 * 3);
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);

      final s = AppState()..myInstructor = null;
      final i = s.instructors.firstWhere((x) => x.apprentices < x.apprenticeCap);
      final before = '學徒 ${i.apprentices} / ${i.apprenticeCap}';
      final after = '學徒 ${i.apprentices + 1} / ${i.apprenticeCap}';

      await t.pumpWidget(AppScope(
        state: s,
        child: const MaterialApp(home: MentorScreen()),
      ));
      await t.pumpAndSettle();
      expect(find.text(before), findsWidgets, reason: '前提：這行字要真的畫得出來');

      // 只送出申請 —— 數字不該動。
      s.applyMentor(i);
      await t.pumpAndSettle();
      expect(find.text(before), findsWidgets,
          reason: '對方還沒答應，這行字不該說他多了一位學徒');
      expect(find.text(after), findsNothing);
    });
  });

  group('同型的其餘候選，逐一驗過', () {
    test('違規次數依主體分流 —— 別人的不算到我頭上', () {
      final s = AppState();
      expect(s.violationsOf(s.displayName), s.myViolations);
      final before = s.myViolations;
      expect(s.violationsOf('某個路人'), 0);
      expect(s.myViolations, before);
    });

    test('團隊分數 ＝ 各成員貢獻的加總，結構上成立', () {
      final s = AppState();
      final t = s.myTeam!;
      expect(t.dailyScore,
          t.contributions.values.fold<int>(0, (a, b) => a + b));
    });

    test('限時任務：全平台完成與記在本隊帳上是兩件事', () {
      final s = AppState();
      final t = s.myTeam!;
      // 兩邊都是 `personKey`，所以直接比鍵。
      final mine = {for (final m in t.members) personKey(m.name, m.uid)};
      final outsider =
          s.timedTask.completedBy.where((k) => !mine.contains(k)).toList();
      expect(t.timedCredited.every(s.timedTask.completedBy.contains), isTrue,
          reason: '記在本隊帳上的，必定也完成了');
      expect(outsider.every((k) => !t.timedCredited.contains(k)), isTrue,
          reason: '別隊的人完成了，不該記在我隊帳上');
    });

    test('AI 月度額度與永久點數不互相汙染', () {
      final s = AppState();
      s.aiMonthly = 5;
      s.aiPermanent = 7;
      s.advanceDemoClock(const Duration(days: 40)); // 跨月觸發重置
      expect(s.aiPermanent, 7, reason: '永久點數不重置、不過期');
    });
  });

  group('女性使用者的評分', () {
    // DOTS 係數依性別分兩組多項式。女性那一組先前沒有任何測試碰過 ——
    // 一半使用者的評分是完全沒驗過的程式碼。
    test('兩性的係數不同', () {
      final m = dotsCoefficient(bodyweightKg: 65, isMale: true);
      final f = dotsCoefficient(bodyweightKg: 65, isMale: false);
      expect(m, greaterThan(0));
      expect(f, greaterThan(0));
      expect(f, isNot(m), reason: '走錯分支的話兩者會一樣');
    });

    test('同樣的重量，女性得到的分數較高', () {
      int score(bool isMale) => measuredScore(
            weightKg: 40,
            reps: 8,
            relativeIntensity: 1.0,
            bodyweightKg: 60,
            isMale: isMale,
          );
      expect(score(false), greaterThan(score(true)),
          reason: 'DOTS 的用意就是讓不同體型與性別可比');
    });

    test('體重被夾在 40–200 之間，極端值不會炸', () {
      for (final bw in [20.0, 40.0, 200.0, 500.0]) {
        for (final male in [true, false]) {
          final c = dotsCoefficient(bodyweightKg: bw, isMale: male);
          expect(c, greaterThan(0), reason: 'bw=$bw male=$male');
          expect(c.isFinite, isTrue);
        }
      }
    });
  });
}
