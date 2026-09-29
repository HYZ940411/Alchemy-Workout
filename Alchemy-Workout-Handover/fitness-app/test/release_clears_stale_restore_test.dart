// 再解除一次，不該跳出上一輪的恢復請求。
//
// 使用者 2026-09-30 實測：「教官那邊再次解除師徒關係，會直接跳出
// 學員想要恢復的請求。」
//
// 一次解除開啟的是一個**新的 3 天窗口**。上一個窗口裡沒被回應的提議
// 不該跨過來 —— 否則教官一按下解除，畫面立刻說「對方提出了恢復，
// 等你回應」，而對方根本還沒做任何事。
//
// **這一支打在 Firestore 那一層。** 先前同型的測試用的是本機假物件，
// 而真正漏掉那一筆欄位的是 `FirestoreMentor.release()` ——
// 假物件各寫各的，驗不到它。

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/mentor_data.dart';
import 'package:fitness_app/data/mentor_data_firestore.dart';
import 'package:fitness_app/domain/community.dart';

const _mentorUid = 'u-教官';
const _appUid = 'u-學徒';
const _bondId = '${_mentorUid}_$_appUid';

Future<({FirestoreMentor src, FakeFirebaseFirestore db})> _bonded() async {
  final db = FakeFirebaseFirestore();
  final src = FirestoreMentor(uid: _mentorUid, firestore: db);
  await src.bond(CloudBond(
    id: _bondId,
    mentorUid: _mentorUid,
    apprenticeUid: _appUid,
    mentorName: '老王',
    apprenticeName: '小明',
    bondedAt: DateTime(2026, 9, 1),
  ));
  return (src: src, db: db);
}

Future<Map<String, dynamic>> _doc(FakeFirebaseFirestore db) async =>
    (await db.collection('mentor_bonds').doc(_bondId).get()).data()!;

void main() {
  test('前提：提出恢復會寫進關係文件', () async {
    final b = await _bonded();
    await b.src.release(_bondId, MentorReleaseReason.byInstructor, DateTime.now());
    await b.src.proposeRestore(_bondId, _appUid);

    expect((await _doc(b.db))['restoreProposedBy'], _appUid);
  });

  test('解除會清掉上一輪的恢復提議', () async {
    final b = await _bonded();
    final t0 = DateTime.now();

    // 第一輪：解除 → 學徒提出恢復 → 教官同意。
    await b.src.release(_bondId, MentorReleaseReason.byInstructor, t0);
    await b.src.proposeRestore(_bondId, _appUid);
    await b.src.recover(_bondId, t0);
    expect((await _doc(b.db))['restoreProposedBy'], isNull,
        reason: '恢復本身就該清掉提議');

    // 第二輪：再解除一次。
    await b.src.proposeRestore(_bondId, _appUid); // 殘留的舊提議
    await b.src.release(_bondId, MentorReleaseReason.byInstructor, t0);

    expect((await _doc(b.db))['restoreProposedBy'], isNull,
        reason: '教官一按下解除就看到「對方提出了恢復」—— 那是上一輪的');
  });

  test('解除後讀回來的 CloudBond 也不帶舊提議', () async {
    final b = await _bonded();
    final t0 = DateTime.now();
    await b.src.release(_bondId, MentorReleaseReason.byInstructor, t0);
    await b.src.proposeRestore(_bondId, _appUid);
    await b.src.release(_bondId, MentorReleaseReason.byInstructor, t0);

    final bond = (await b.src.bonds()).single;
    expect(bond.state, MentorBondState.released);
    expect(bond.restoreProposedBy, isNull);
  });

  test('拒絕會清掉提議，但關係仍是已解除', () async {
    final b = await _bonded();
    final t0 = DateTime.now();
    await b.src.release(_bondId, MentorReleaseReason.byInstructor, t0);
    await b.src.proposeRestore(_bondId, _appUid);
    await b.src.dropRestore(_bondId);

    final bond = (await b.src.bonds()).single;
    expect(bond.restoreProposedBy, isNull);
    expect(bond.state, MentorBondState.released,
        reason: '失效的是那筆提議，不是整段關係');
  });


  group('恢復不了的時候要用丟的，不可以靜靜成功', () {
    // 原本 `recover()` 的守衛失敗時是 `return;` —— 交易正常結束，
    // 呼叫端的 `_write()` 於是記成「成功」，而雲端一個字都沒變。
    //
    // 使用者 2026-09-30 實測：教官按同意、畫面說「師徒關係已恢復」、
    // 學徒重載還是已解除。**一個什麼都沒做的成功**，
    // 而那正是當晚查了一整輪的同一個形狀。

    // **訊息要帶著判斷不成立的那個值。**
    //
    // 在 Web 上，從 `runTransaction` 內部丟出去的例外會被 JS interop
    // 包起來、訊息整個不見（使用者 2026-09-30 拿到的是
    // 「Dart exception thrown from converted Future…」，零線索）。
    // 所以判斷留在交易裡、丟在交易外面 —— 這幾條驗的是丟出來的內容。
    Matcher saying(String fragment) => throwsA(isA<StateError>()
        .having((e) => e.message, '訊息', contains(fragment)));

    test('關係根本不是已解除', () async {
      final b = await _bonded();
      await expectLater(
          b.src.recover(_bondId, DateTime.now()), saying('不是已解除'));
    });

    test('訊息帶著那個值，不是只說「失敗」', () async {
      final b = await _bonded();
      await expectLater(
          b.src.recover(_bondId, DateTime.now()), saying('state=active'));
    });

    test('超過 3 天', () async {
      final b = await _bonded();
      final t0 = DateTime(2026, 9, 1);
      await b.src.release(_bondId, MentorReleaseReason.byInstructor, t0);
      await expectLater(
        b.src.recover(_bondId, t0.add(kMentorReleaseCooldown +
            const Duration(hours: 1))),
        saying('已超過 3 天'),
      );
      final bond = (await b.src.bonds()).single;
      expect(bond.state, MentorBondState.released, reason: '沒被改到');
    });

    test('關係文件不存在', () async {
      final db = FakeFirebaseFirestore();
      final src = FirestoreMentor(uid: _mentorUid, firestore: db);
      await expectLater(
          src.recover('沒有這一筆', DateTime.now()), saying('不存在'));
    });

    test('該成功的時候照樣成功', () async {
      final b = await _bonded();
      final t0 = DateTime.now();
      await b.src.release(_bondId, MentorReleaseReason.byInstructor, t0);
      await b.src.recover(_bondId, t0);
      final bond = (await b.src.bonds()).single;
      expect(bond.state, MentorBondState.active);
      expect(bond.releasedAt, isNull);
    });
  });
}
