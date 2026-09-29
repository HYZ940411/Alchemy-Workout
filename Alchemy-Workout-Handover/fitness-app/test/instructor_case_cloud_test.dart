// 教官申請的待審案件要真的離開申請人的裝置（[BE-20]）。
//
// ## 在此之前它從來沒有
//
// `submitExam()` 把案件 insert 進**申請人自己的** `AppState.instructorCases`。
// 那份清單沒有雲端來源、`firestore.rules` 裡沒有對應集合、也不進存檔 ——
// 申請人考完試，案件留在他自己的瀏覽器記憶體裡，
// **管理員在另一台裝置上永遠看不到**。
//
// 而後台那一頁看起來一直都正常，因為它列的是示範用的假案件。
// 使用者 2026-09-29 測「審核佇列的評分細則」回報教官分頁是空的 ——
// 線上版永遠不是示範模式，所以那一頁對每一個人、在任何時候都是空的。
//
// 與 [BE-13] 之前的檢舉同一個形狀：畫面做好了、流程走得通、
// 而資料沒有離開過本機。

import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/instructor_case_data.dart';
import 'package:fitness_app/data/instructor_case_data_firestore.dart';
import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/state/app_state.dart';

/// 一律失敗的來源，用來驗「送不上去要留下痕跡」。
class _Broken implements InstructorCaseSource {
  @override
  Future<void> file(CloudInstructorCase c) async => throw StateError('雲端壞了');
  @override
  Future<InstructorVerdict?> mine() async => throw StateError('雲端壞了');
  @override
  Future<List<CloudInstructorCase>> queue({int limit = 100}) async =>
      throw StateError('雲端壞了');
  @override
  Future<void> decide(String uid,
          {required bool passed, required String handlerName}) async =>
      throw StateError('雲端壞了');
}

void main() {
  late FakeFirebaseFirestore db;

  setUp(() => db = FakeFirebaseFirestore());

  /// 一個走完初審、可以直接作答的申請人。
  AppState applicant({String uid = 'u-applicant'}) => AppState()
    ..myUid = uid
    ..instructorStage = InstructorStage.screenPassed
    ..instructorCaseSource =
        FirestoreInstructorCases(uid: uid, firestore: db);

  group('送出測驗 → 案件真的上雲', () {
    test('申請人送出後，雲端有他那一筆', () async {
      final s = applicant();
      expect(
          s.submitExam(18, shortAnswers: [('題目一', '我的回答')]), isTrue);
      // 即發即忘，等它送完。
      await Future<void>.delayed(Duration.zero);

      final doc =
          await db.collection('instructor_cases').doc('u-applicant').get();
      expect(doc.exists, isTrue, reason: '在此之前這裡什麼都沒有');
      expect(doc.data()!['state'], 'pending');
      expect(doc.data()!['applicantUid'], 'u-applicant');
      // 簡答作答攤成物件陣列 —— Firestore 不支援陣列裡再放陣列。
      expect(doc.data()!['answers'], [
        {'q': '題目一', 'a': '我的回答'},
      ]);
    });

    test('重考不會在佇列裡留下兩筆同一個人的申請', () async {
      final s = applicant();
      s.submitExam(18, shortAnswers: [('題目一', '第一次')]);
      await Future<void>.delayed(Duration.zero);
      s.instructorStage = InstructorStage.screenPassed;
      s.lastExamAt = null;
      s.submitExam(19, shortAnswers: [('題目一', '第二次')]);
      await Future<void>.delayed(Duration.zero);

      final snap = await db.collection('instructor_cases').get();
      expect(snap.docs, hasLength(1), reason: '文件 ID 就是 uid，主鍵保證唯一');
      expect((snap.docs.first.data()['answers'] as List).first,
          {'q': '題目一', 'a': '第二次'});
    });

    test('送不上去要留下痕跡，不是無聲失敗', () async {
      final s = applicant()..instructorCaseSource = _Broken();
      s.submitExam(18, shortAnswers: [('題目一', '我的回答')]);
      await Future<void>.delayed(Duration.zero);
      expect(s.instructorCaseError, isNotNull,
          reason: '申請人以為送出了、管理員佇列裡沒有他 —— 兩邊都不會知道');
    });

    test('沒接雲端時照常運作 —— 既有測試與示範走這條', () {
      final s = AppState()..instructorStage = InstructorStage.screenPassed;
      expect(s.submitExam(18), isTrue);
      expect(s.instructorCaseError, isNull);
    });
  });

  group('管理員讀得到別人的申請', () {
    AppState boss() => AppState()
      ..myUid = 'u-admin'
      ..applyAdminClaim(true)
      ..instructorCaseSource =
          FirestoreInstructorCases(uid: 'u-admin', firestore: db);

    test('另一台裝置上的申請，管理員看得到', () async {
      // 申請人那一側。
      applicant().submitExam(18, shortAnswers: [('題目一', '我的回答')]);
      await Future<void>.delayed(Duration.zero);

      // 管理員那一側 —— 完全不同的 AppState。
      final a = boss();
      expect(a.instructorCases.any((c) => c.applicantUid == 'u-applicant'),
          isFalse, reason: '前提：本機沒有這一筆');

      await a.loadInstructorQueue();
      final got = a.instructorCases
          .firstWhere((c) => c.applicantUid == 'u-applicant');
      expect(got.applicant, isNotEmpty);
      expect(got.answers, [('題目一', '我的回答')],
          reason: '管理員看到的要與申請人送出的是同一份內容');
    });

    test('一般帳號不去讀佇列 —— 規則那一側本來就會拒絕', () async {
      applicant().submitExam(18, shortAnswers: [('題目一', '我的回答')]);
      await Future<void>.delayed(Duration.zero);

      final nobody = AppState()
        ..applyAdminClaim(false)
        ..instructorCaseSource =
            FirestoreInstructorCases(uid: 'u-x', firestore: db);
      await nobody.loadInstructorQueue();
      expect(nobody.instructorCases.any((c) => c.applicantUid == 'u-applicant'),
          isFalse);
    });

    test('讀取失敗時不清空佇列 —— 空佇列與讀不到長得一模一樣', () async {
      final a = boss();
      a.applyCloudInstructorCases([
        CloudInstructorCase(
          applicantUid: 'u-1',
          applicant: '某人',
          aiScores: const {'訓練完成率': 80},
          weighted: 80,
          concerns: const [],
          answers: const [('題目', '答案')],
          at: DateTime(2026, 9, 1),
        ),
      ]);
      final before = a.instructorCases.length;

      a.instructorCaseSource = _Broken();
      await a.loadInstructorQueue();
      expect(a.instructorCases.length, before);
    });
  });

  group('裁決要寫回雲端', () {
    test('判過的案子不會留在別人的待審佇列裡', () async {
      applicant().submitExam(18, shortAnswers: [('題目一', '我的回答')]);
      await Future<void>.delayed(Duration.zero);

      final a = AppState()
        ..myUid = 'u-admin'
        ..applyAdminClaim(true)
        ..instructorCaseSource =
            FirestoreInstructorCases(uid: 'u-admin', firestore: db);
      await a.loadInstructorQueue();
      final c = a.instructorCases
          .firstWhere((x) => x.applicantUid == 'u-applicant');

      a.decideInstructor(c, true);
      await Future<void>.delayed(Duration.zero);

      final doc =
          await db.collection('instructor_cases').doc('u-applicant').get();
      expect(doc.data()!['state'], 'passed',
          reason: '不寫回的話，下一位管理員會重審一次已經判過的案子');

      // 而且它不再出現在待審佇列裡。
      final again = await FirestoreInstructorCases(
              uid: 'u-admin', firestore: db)
          .queue();
      expect(again.any((x) => x.applicantUid == 'u-applicant'), isFalse);
    });
  });

  group('裁決要回得到申請人身上', () {
    // 使用者 2026-09-29 實測：B 通過測驗、管理員也核准了，
    // **重新整理之後沒看到自己成為教官**。
    //
    // 兩個缺口：`instructorStage` 不進存檔，而安全規則原本只讓管理員讀
    // 那份文件 —— 申請人連自己那一筆都讀不到。裁決寫進了雲端，
    // 然後停在那裡。

    /// 跑完一次「B 申請 → A 核准」，回傳 B 的 uid。
    Future<String> approvedApplicant() async {
      applicant().submitExam(18, shortAnswers: [('題目一', '我的回答')]);
      await Future<void>.delayed(Duration.zero);
      final a = AppState()
        ..myUid = 'u-admin'
        ..applyAdminClaim(true)
        ..instructorCaseSource =
            FirestoreInstructorCases(uid: 'u-admin', firestore: db);
      await a.loadInstructorQueue();
      a.decideInstructor(
          a.instructorCases.firstWhere((x) => x.applicantUid == 'u-applicant'),
          true);
      await Future<void>.delayed(Duration.zero);
      return 'u-applicant';
    }

    test('核准之後，申請人重新登入就是教官了', () async {
      await approvedApplicant();

      // **全新的 AppState** —— 模擬重新整理瀏覽器。
      final b = AppState()
        ..myUid = 'u-applicant'
        ..instructorCaseSource =
            FirestoreInstructorCases(uid: 'u-applicant', firestore: db);
      expect(b.isInstructor, isFalse, reason: '前提：本機什麼都沒留');

      await b.loadMyInstructorVerdict();
      expect(b.isInstructor, isTrue);
      expect(b.instructorStage, InstructorStage.approved);
    });

    test('駁回也要傳得回去，而且說得出是卡在哪一關', () async {
      applicant().submitExam(18, shortAnswers: [('題目一', '我的回答')]);
      await Future<void>.delayed(Duration.zero);
      final a = AppState()
        ..myUid = 'u-admin'
        ..applyAdminClaim(true)
        ..instructorCaseSource =
            FirestoreInstructorCases(uid: 'u-admin', firestore: db);
      await a.loadInstructorQueue();
      a.decideInstructor(
          a.instructorCases.firstWhere((x) => x.applicantUid == 'u-applicant'),
          false);
      await Future<void>.delayed(Duration.zero);

      final b = AppState()
        ..myUid = 'u-applicant'
        ..instructorCaseSource =
            FirestoreInstructorCases(uid: 'u-applicant', firestore: db);
      await b.loadMyInstructorVerdict();
      expect(b.isInstructor, isFalse);
      expect(b.instructorStage, InstructorStage.rejected);
      expect(b.instructorRejectStage, '管理員審核');
    });

    test('還沒判的時候，階段要補回「待人工審核」而不是「還沒申請」', () async {
      applicant().submitExam(18, shortAnswers: [('題目一', '我的回答')]);
      await Future<void>.delayed(Duration.zero);

      final b = AppState()
        ..myUid = 'u-applicant'
        ..instructorCaseSource =
            FirestoreInstructorCases(uid: 'u-applicant', firestore: db);
      await b.loadMyInstructorVerdict();
      expect(b.instructorStage, InstructorStage.pendingReview,
          reason: '他在等，畫面不該說他還沒申請');
      expect(b.isInstructor, isFalse);
    });

    test('沒申請過的人不受影響', () async {
      final c = AppState()
        ..myUid = 'u-nobody'
        ..instructorCaseSource =
            FirestoreInstructorCases(uid: 'u-nobody', firestore: db);
      await c.loadMyInstructorVerdict();
      expect(c.instructorStage, InstructorStage.notApplied);
      expect(c.isInstructor, isFalse);
    });

    test('讀不到的時候維持現狀 —— 不要把「不知道」畫成「沒申請」', () async {
      final b = AppState()
        ..myUid = 'u-applicant'
        ..instructorStage = InstructorStage.pendingReview
        ..instructorCaseSource = _Broken();
      await b.loadMyInstructorVerdict();
      expect(b.instructorStage, InstructorStage.pendingReview);
    });
  });

  group('安全規則有這個集合', () {
    test('firestore.rules 涵蓋 instructor_cases，且讀取限管理員', () {
      // 安全規則是改不掉的那一道，客戶端的程式碼改得掉
      // （同 photo_upload_test 的做法）。
      final rules = File('firestore.rules').readAsStringSync();
      expect(rules, contains('match /instructor_cases/'));
      // 申請人只寫得了自己那一筆，而且不能自己寫裁決結果。
      expect(rules, contains("request.resource.data.state == 'pending'"));
      // 申請人讀得到自己那一筆 —— 少了它，裁決永遠回不到他身上。
      expect(rules, contains('applicantUid == request.auth.uid'));
    });
  });
}
