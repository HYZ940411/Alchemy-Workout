// 教官測驗題庫上雲（2026-10-15，使用者要求補的缺功能；答案可見度取裁決 A）。
//
// 在此之前題庫是打包在 App 裡的，後台新增／移除題目只改記憶體，重新整理就回原樣，
// 而且改題目要重新發版。現在寫進雲端，並拆成兩份文件：
//   · exam_questions：題目、選項、選擇題正解 —— 登入者讀得到（考生手機要批改）
//   · exam_notes：出題理由、評分細則、追問範例 —— 只有管理員

import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/platform_data.dart';
import 'package:fitness_app/data/platform_data_firestore.dart';
import 'package:fitness_app/domain/platform_config.dart';
import 'package:fitness_app/domain/task_pool.dart';
import 'package:fitness_app/mock/mock_extra.dart';
import 'package:fitness_app/state/app_state.dart';

ExamQuestion _newMc(String id) => ExamQuestion(
      id: id,
      type: ExamQuestionType.multipleChoice,
      text: '新增的選擇題 $id',
      options: ['甲', '乙', '丙'],
      answerIndex: 2,
      rationale: '測試出題理由',
      mustPass: true,
    );

ExamQuestion _newSa(String id) => ExamQuestion(
      id: id,
      type: ExamQuestionType.shortAnswer,
      text: '新增的簡答題 $id',
      rationale: '測簡答',
      rubricPass: '要提到轉介',
      rubricFail: '給醫療建議',
      followUp: '如果對方說不想看醫生呢？',
    );

void main() {
  setUp(platformConfig.reset);
  tearDown(platformConfig.reset);

  late FakeFirebaseFirestore db;
  late AppState admin;

  setUp(() {
    db = FakeFirebaseFirestore();
    admin = AppState()
      ..applyAdminClaim(true)
      ..platformSource = FirestorePlatformData(firestore: db);
  });

  Future<AppState> userLoads() async => AppState(demo: false)
    ..applyPlatformData(await FirestorePlatformData(firestore: db).load());

  group('文件形狀：拆成兩份', () {
    test('題目那份沒有任何說明性欄位；說明那份才有', () {
      final q = _newSa('x1');
      final pub = examQuestionToMap(q);
      final notes = examNotesToMap(q);
      for (final k in ['rationale', 'rubricPass', 'rubricFail', 'followUp']) {
        expect(pub.containsKey(k), isFalse, reason: '$k 不能出現在登入者讀得到的文件上');
        expect(notes.containsKey(k), isTrue);
      }
      expect(pub['text'], q.text);
    });

    test('兩份合回來一模一樣', () {
      final q = _newMc('x2');
      final back = examQuestionFromDocs(
          q.id, examQuestionToMap(q), examNotesToMap(q));
      expect(back.text, q.text);
      expect(back.options, q.options);
      expect(back.answerIndex, 2);
      expect(back.mustPass, isTrue);
      expect(back.rationale, '測試出題理由');
    });

    test('讀不到說明文件（非管理員）：題目照常，說明性欄位留空', () {
      final q = _newSa('x3');
      final back = examQuestionFromDocs(q.id, examQuestionToMap(q), null);
      expect(back.text, q.text);
      expect(back.rubricPass, isEmpty);
      expect(back.followUp, isEmpty);
    });
  });

  group('載入：內建當底，雲端蓋上去', () {
    test('雲端沒有題目 → 就是內建題庫', () async {
      final loaded = await FirestorePlatformData(firestore: db).load();
      expect(loaded.examQuestions.map((q) => q.id),
          buildExamBank().map((q) => q.id));
    });

    test('後台新增並送上雲 → 另一個人載入看得到，題目與正解都在', () async {
      final q = _newMc('cloud-1');
      expect(admin.addExamQuestion(q), isNull);
      expect(await admin.pushExamQuestion(q), isNull);

      final user = await userLoads();
      final got = user.examBank.firstWhere((x) => x.id == 'cloud-1');
      expect(got.text, q.text);
      expect(got.options, ['甲', '乙', '丙']);
      expect(got.answerIndex, 2);
      expect(user.examBank.length, buildExamBank().length + 1,
          reason: '內建的都還在');
    });

    test('管理員載入：說明性欄位也合回來', () async {
      final q = _newSa('cloud-2');
      admin.addExamQuestion(q);
      await admin.pushExamQuestion(q);

      final again = await userLoads();
      final got = again.examBank.firstWhere((x) => x.id == 'cloud-2');
      expect(got.rubricPass, '要提到轉介');
      expect(got.followUp, '如果對方說不想看醫生呢？');
    });

    test('說明文件「讀取失敗」（非管理員被規則擋下）：題目照載，不退回內建', () async {
      final q = _newMc('cloud-5');
      admin.addExamQuestion(q);
      await admin.pushExamQuestion(q);

      final bank = await FirestorePlatformData.loadExamBank(
        questions: () => db.collection('exam_questions').get(),
        notes: () => throw StateError('permission-denied'),
        bundle: buildExamBank(),
      );
      expect(bank.any((x) => x.id == 'cloud-5'), isTrue,
          reason: '說明讀不到不能把雲端的題目一起丟掉');
    });

    test('題目整類讀不到：退回內建題庫', () async {
      final bank = await FirestorePlatformData.loadExamBank(
        questions: () => throw StateError('offline'),
        notes: () => db.collection('exam_notes').get(),
        bundle: buildExamBank(),
      );
      expect(bank.map((x) => x.id), buildExamBank().map((x) => x.id));
    });

    test('說明文件讀不到（模擬非管理員）：題目照載，不受影響', () async {
      final q = _newSa('cloud-3');
      admin.addExamQuestion(q);
      await admin.pushExamQuestion(q);
      await db.collection('exam_notes').doc('cloud-3').delete();

      final user = await userLoads();
      final got = user.examBank.firstWhere((x) => x.id == 'cloud-3');
      expect(got.text, q.text);
      expect(got.rubricPass, isEmpty);
    });
  });

  group('移除', () {
    test('移除內建題目：寫墓碑，重新載入不會回來；其他內建題都還在', () async {
      final target = admin.examBank.first;
      expect(admin.removeExamQuestion(target), isNull);
      expect(await admin.pushExamRemoval(target), isNull);

      final user = await userLoads();
      expect(user.examBank.any((x) => x.id == target.id), isFalse);
      expect(user.examBank.length, buildExamBank().length - 1);
    });

    test('移除雲端獨有的題目：同樣不會回來，說明文件也被清掉', () async {
      final q = _newMc('cloud-4');
      admin.addExamQuestion(q);
      await admin.pushExamQuestion(q);
      admin.removeExamQuestion(q);
      expect(await admin.pushExamRemoval(q), isNull);

      final user = await userLoads();
      expect(user.examBank.any((x) => x.id == 'cloud-4'), isFalse);
      expect((await db.collection('exam_notes').doc('cloud-4').get()).exists,
          isFalse);
    });

    test('移除到題庫不足：重新載入後後台還是講得出來', () async {
      final mc = admin.examBank
          .where((q) => q.type == ExamQuestionType.multipleChoice)
          .toList();
      final need = platformConfig.i('exam', 'mcCount');
      for (final q in mc.take(mc.length - need + 1)) {
        admin.removeExamQuestion(q);
        await admin.pushExamRemoval(q);
      }
      final user = await userLoads();
      expect(user.examBankWarning, isNotNull);
    });
  });

  group('守衛', () {
    test('空題目、選項不足都不送', () async {
      final empty = ExamQuestion(
          id: 'e', type: ExamQuestionType.shortAnswer, text: '   ');
      expect(admin.addExamQuestion(empty), contains('不得為空'));
      final few = ExamQuestion(
          id: 'f',
          type: ExamQuestionType.multipleChoice,
          text: '題',
          options: ['只有一個']);
      expect(admin.addExamQuestion(few), contains('兩個選項'));
    });

    test('沒有管理員標記：說寫不上雲，雲端什麼都沒有', () async {
      final nobody = AppState()
        ..platformSource = FirestorePlatformData(firestore: db);
      final msg = await nobody.pushExamQuestion(_newMc('n1'));
      expect(msg, isNotNull);
      expect((await db.collection('exam_questions').get()).docs, isEmpty);
    });
  });

  test('安全規則：題目登入者可讀、說明只有管理員、寫入只有管理員', () {
    final rules = File('firestore.rules').readAsStringSync();
    String block(String name) {
      final i = rules.indexOf('match /$name/{document=**}');
      expect(i, isNot(-1), reason: '規則裡沒有 $name');
      return rules.substring(i, rules.indexOf('\n    }\n', i));
    }

    final q = block('exam_questions');
    expect(q, contains('allow read: if request.auth != null'));
    expect(q, contains('allow write: if isAdmin()'));

    final n = block('exam_notes');
    expect(n, contains('allow read, write: if isAdmin()'));
    expect(n, isNot(contains('request.auth != null')),
        reason: '說明文件不能開給一般登入者');
  });
}
