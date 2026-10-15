// 「本週互動摘要」的四個數字（提問／回覆、任務指派／完成）要記對（使用者回報）。
//
// 原本是四個各自累加的整數，只有動手的那一台裝置會加：
//   · 任務指派 —— 指派時根本沒人加（永遠停在預設值）
//   · 學徒那台的「回覆」永遠是 0、教官那台的「提問」永遠是 0
//   · 換一台裝置、重新登入，數字跟實際發生的事對不起來
// 兩邊其實是同一段關係的同一週，要數的是同一批提問與任務。
// 現在由資料推導（提問的 at／answeredAt、任務的 assignedAt／doneAt），
// 這支測試用真的 Firestore 存取層（假資料庫）跑一次教官 ↔ 學徒的完整往返。

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/mentor_data.dart';
import 'package:fitness_app/data/mentor_data_firestore.dart';
import 'package:fitness_app/domain/clock.dart';
import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/state/app_state.dart';

CloudBond get _bond => CloudBond(
      id: 'T_A',
      mentorUid: 'T',
      apprenticeUid: 'A',
      mentorName: '教官',
      apprenticeName: '學徒',
      state: MentorBondState.active,
      bondedAt: DateTime(2026, 9, 1),
    );

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

({AppState t, AppState a, FakeFirebaseFirestore db}) _pair() {
  final db = FakeFirebaseFirestore();
  final t = AppState(demo: false)
    ..myUid = 'T'
    ..displayName = '教官'
    ..isInstructor = true
    ..instructorDutyVersion = kInstructorDutyVersion
    ..mentorSource = FirestoreMentor(uid: 'T', firestore: db);
  final a = AppState(demo: false)
    ..myUid = 'A'
    ..displayName = '學徒'
    ..mentorSource = FirestoreMentor(uid: 'A', firestore: db);
  t.applyCloudBonds([_bond]);
  a.applyCloudBonds([_bond]);
  a.confirmMentorDisclaimer();
  return (t: t, a: a, db: db);
}

void main() {
  setUp(() {
    // 吃真實時鐘：挪到正午，免得在換日時點或週界附近跑會跨週。
    resetAppClock();
    final n = appNow();
    appClockOffset += Duration(hours: 12 - n.hour, minutes: -n.minute);
  });
  tearDown(resetAppClock);

  test('教官指派一則任務 → 教官那邊的「任務指派」是 1（原本永遠不動）', () async {
    final p = _pair();
    final before = p.t.weeklyAssigned;
    expect(p.t.assignMentorTask('練腿', '三組', apprenticeUid: 'A'), isTrue);
    expect(p.t.weeklyAssigned, before + 1);
  });

  test('學徒那台讀回來之後，「任務指派」也是 1', () async {
    final p = _pair();
    p.t.assignMentorTask('練腿', '三組', apprenticeUid: 'A');
    await settle();

    expect(p.a.weeklyAssigned, 0, reason: '還沒讀回來');
    await p.a.loadMyApprenticeSide();
    expect(p.a.weeklyAssigned, 1, reason: '另一台裝置指派的，這台也要數到');
  });

  test('學徒完成 → 兩邊的「完成」都是 1', () async {
    final p = _pair();
    p.t.assignMentorTask('練腿', '三組', apprenticeUid: 'A');
    await settle();
    await p.a.loadMyApprenticeSide();

    expect(p.a.completeMentorTask(p.a.mentorTasks.single), isTrue);
    expect(p.a.weeklyCompleted, 1);
    await settle();

    await p.t.loadMentorSideOf('A');
    expect(p.t.weeklyCompleted, 1, reason: '教官那台要數到學徒在別台完成的');
    expect(p.t.weeklyAssigned, 1);
  });

  test('學徒提問 → 教官讀回來，兩邊的「提問」都是 1、「回覆」都是 0', () async {
    final p = _pair();
    expect(p.a.askQuestion('怎麼練'), isTrue);
    expect(p.a.weeklyQuestionCount, 1);
    await settle();

    await p.t.loadMentorSideOf('A');
    expect(p.t.weeklyQuestionCount, 1, reason: '原本教官那台的「提問」永遠是 0');
    expect(p.t.weeklyAnswerCount, 0);
  });

  test('教官回答 → 學徒讀回來，兩邊的「回覆」都是 1', () async {
    final p = _pair();
    p.a.askQuestion('怎麼練');
    await settle();
    await p.t.loadMentorSideOf('A');

    expect(p.t.answerQuestion(p.t.questions.single, '多喝水'), isTrue);
    expect(p.t.weeklyAnswerCount, 1);
    await settle();

    await p.a.loadMyApprenticeSide();
    expect(p.a.weeklyAnswerCount, 1, reason: '原本學徒那台的「回覆」永遠是 0');
    expect(p.a.weeklyQuestionCount, 1);
  });

  test('上週的不算本週', () async {
    final p = _pair();
    p.a.askQuestion('上週的問題');
    p.a.questions.single.answeredAt = p.a.now.subtract(const Duration(days: 9));
    // 把它的提問時間也改成上週。
    final old = p.a.questions.single;
    p.a.questions[0] = MentorQuestion(
      id: old.id,
      from: old.from,
      text: old.text,
      at: p.a.now.subtract(const Duration(days: 9)),
      answer: '舊答案',
      answeredAt: p.a.now.subtract(const Duration(days: 9)),
    );
    expect(p.a.weeklyQuestionCount, 0);
    expect(p.a.weeklyAnswerCount, 0);
  });

  test('舊任務（沒有指派時點）不算進任何一週，也不會讓畫面壞掉', () async {
    final p = _pair();
    // 模擬加這個欄位之前就存在的任務。
    await p.db
        .collection('mentor_bonds')
        .doc('T_A')
        .collection('tasks')
        .doc('old')
        .set({'title': '舊任務', 'detail': '', 'state': 'assigned', 'rewardCoins': 5});
    await p.a.loadMyApprenticeSide();
    expect(p.a.mentorTasks, hasLength(1));
    expect(p.a.weeklyAssigned, 0);
  });

  test('跨週之後歸零，不必靠排程', () async {
    final p = _pair();
    p.t.assignMentorTask('練腿', '三組', apprenticeUid: 'A');
    expect(p.t.weeklyAssigned, 1);

    addTearDown(resetAppClock);
    p.t.advanceDemoClock(const Duration(days: 8));
    expect(p.t.weeklyAssigned, 0);
  });

  test('指派與完成的時點經過 Firestore 來回後還在', () async {
    final db = FakeFirebaseFirestore();
    final src = FirestoreMentor(uid: 'T', firestore: db);
    final at = DateTime(2026, 10, 5, 9, 30);
    final done = DateTime(2026, 10, 6, 10);
    await src.putTask(
        'T_A',
        CloudMentorTask(
            id: 't1', title: 'x', detail: '', assignedAt: at, doneAt: done));

    final back = (await src.tasks('T_A')).single;
    expect(back.assignedAt, at);
    expect(back.doneAt, done);
  });
}
