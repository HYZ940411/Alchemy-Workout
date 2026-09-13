// 師徒關係上雲（[BE-11] 批次 6，BE-11 的最後一批）。
//
// 這批要顧兩個規格上的不變條件，兩者壞掉都不會報錯、只會產生
// 說不通的狀態：
//   一、同一學徒同時至多一筆生效中
//   二、關係解除時，未完成的任務一律轉為已作廢
// 第二條若沒做，學徒會留著一個「還在指派中」但已經沒有教官的任務。

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/mentor_data.dart';
import 'package:fitness_app/data/mentor_data_firestore.dart';
import 'package:fitness_app/domain/community.dart';

void main() {
  late FakeFirebaseFirestore db;

  final bonded = DateTime(2026, 9, 1);

  setUp(() => db = FakeFirebaseFirestore());

  FirestoreMentor as(String uid) =>
      FirestoreMentor(uid: uid, firestore: db);

  CloudBond bond({
    String mentor = 'm',
    String apprentice = 'a',
  }) =>
      CloudBond(
        id: '${mentor}_$apprentice',
        mentorUid: mentor,
        apprenticeUid: apprentice,
        mentorName: '教官',
        apprenticeName: '學徒',
        bondedAt: bonded,
      );

  group('建立關係', () {
    test('建立之後雙方都查得到', () async {
      await as('m').bond(bond());

      expect(await as('m').bonds(), hasLength(1));
      expect(await as('a').bonds(), hasLength(1));
    });

    test('不相干的人查不到', () async {
      await as('m').bond(bond());
      expect(await as('z').bonds(), isEmpty);
    });

    test('同一學徒同時至多一筆生效中', () async {
      // 不變條件。呼叫端有好幾條路徑會走到建立關係，
      // 每一條都記得檢查是不可能的，所以檢查放在實作裡。
      await as('m').bond(bond(mentor: 'm', apprentice: 'a'));
      await as('m2').bond(bond(mentor: 'm2', apprentice: 'a'));

      final all = await db.collection('mentor_bonds').get();
      expect(all.docs, hasLength(1), reason: '第二位教官不該收得到同一個學徒');
    });

    test('解除之後同一學徒可以拜新的教官', () async {
      await as('m').bond(bond(mentor: 'm', apprentice: 'a'));
      await as('m').release(
          'm_a', MentorReleaseReason.byApprentice, DateTime(2026, 9, 10));
      await as('m2').bond(bond(mentor: 'm2', apprentice: 'a'));

      final all = await db.collection('mentor_bonds').get();
      expect(all.docs, hasLength(2));
    });
  });

  group('解除與恢復', () {
    test('解除之後狀態為已解除，文件還在', () async {
      await as('m').bond(bond());
      await as('m').release(
          'm_a', MentorReleaseReason.byInstructor, DateTime(2026, 9, 10));

      final b = (await as('m').bonds()).first;
      expect(b.state, MentorBondState.released);
      expect(b.releasedReason, MentorReleaseReason.byInstructor);
    });

    test('未完成的任務隨解除一併作廢', () async {
      // 不做的話，學徒會留著一個「還在指派中」但已經沒有教官的任務。
      await as('m').bond(bond());
      await as('m').putTask(
          'm_a',
          const CloudMentorTask(
              id: 't1', title: '深蹲 3 組', detail: '', ));
      await as('m').release(
          'm_a', MentorReleaseReason.byApprentice, DateTime(2026, 9, 10));

      final t = (await as('m').tasks('m_a')).first;
      expect(t.state, MentorTaskState.voided);
    });

    test('已完成的任務不受解除影響', () async {
      await as('m').bond(bond());
      await as('m').putTask(
          'm_a',
          const CloudMentorTask(
            id: 't1',
            title: '深蹲 3 組',
            detail: '',
            state: MentorTaskState.done,
          ));
      await as('m').release(
          'm_a', MentorReleaseReason.byApprentice, DateTime(2026, 9, 10));

      expect((await as('m').tasks('m_a')).first.state, MentorTaskState.done);
    });

    test('三天內可以恢復，而且是同一筆轉回去', () async {
      await as('m').bond(bond());
      await as('m').release(
          'm_a', MentorReleaseReason.byApprentice, DateTime(2026, 9, 10));
      await as('m').recover('m_a', DateTime(2026, 9, 12));

      final all = await db.collection('mentor_bonds').get();
      expect(all.docs, hasLength(1), reason: '恢復不該新建一筆');
      expect((await as('m').bonds()).first.state, MentorBondState.active);
    });

    test('超過三天就不能恢復', () async {
      await as('m').bond(bond());
      await as('m').release(
          'm_a', MentorReleaseReason.byApprentice, DateTime(2026, 9, 10));
      await as('m').recover('m_a', DateTime(2026, 9, 20));

      expect((await as('m').bonds()).first.state, MentorBondState.released);
    });

    test('生效中的關係呼叫恢復不會有事', () async {
      await as('m').bond(bond());
      await as('m').recover('m_a', DateTime(2026, 9, 5));
      expect((await as('m').bonds()).first.state, MentorBondState.active);
    });
  });

  group('任務', () {
    test('指派之後學徒看得到', () async {
      await as('m').bond(bond());
      await as('m').putTask('m_a',
          const CloudMentorTask(id: 't1', title: '深蹲 3 組', detail: '每組 8 下'));

      final t = (await as('a').tasks('m_a')).first;
      expect(t.title, '深蹲 3 組');
      expect(t.state, MentorTaskState.assigned);
    });

    test('評分寫得進去', () async {
      await as('m').bond(bond());
      await as('m').putTask(
          'm_a',
          const CloudMentorTask(
            id: 't1',
            title: '深蹲 3 組',
            detail: '',
            state: MentorTaskState.done,
            rating: 5,
          ));

      expect((await as('m').tasks('m_a')).first.rating, 5);
    });

    test('沒評分時是空值，不是零', () async {
      // 零分與「還沒評分」是兩件事 —— 混在一起的話聲望會被扣。
      await as('m').bond(bond());
      await as('m').putTask('m_a',
          const CloudMentorTask(id: 't1', title: '深蹲', detail: ''));

      expect((await as('m').tasks('m_a')).first.rating, isNull);
    });
  });

  group('問答', () {
    test('學徒提問，教官看得到', () async {
      await as('m').bond(bond());
      await as('a').ask(
          'm_a',
          CloudQuestion(
              id: 'q1',
              fromUid: 'a',
              text: '深蹲膝蓋會痛怎麼辦？',
              at: DateTime(2026, 9, 5)));

      final q = (await as('m').questions('m_a')).first;
      expect(q.text, '深蹲膝蓋會痛怎麼辦？');
      expect(q.fromUid, 'a');
      expect(q.answered, isFalse);
    });

    test('回答之後雙方都看得到', () async {
      await as('m').bond(bond());
      await as('a').ask('m_a',
          CloudQuestion(id: 'q1', fromUid: 'a', text: '問題', at: DateTime(2026, 9, 5)));
      await as('m').answer('m_a', 'q1', '先檢查腳掌方向', DateTime(2026, 9, 6));

      final q = (await as('a').questions('m_a')).first;
      expect(q.answer, '先檢查腳掌方向');
      expect(q.answered, isTrue);
    });

    test('依提問時間排序', () async {
      await as('m').bond(bond());
      await as('a').ask('m_a',
          CloudQuestion(id: 'q1', fromUid: 'a', text: '先問的', at: DateTime(2026, 9, 5)));
      await as('a').ask('m_a',
          CloudQuestion(id: 'q2', fromUid: 'a', text: '後問的', at: DateTime(2026, 9, 6)));

      expect([for (final q in await as('m').questions('m_a')) q.text],
          ['先問的', '後問的']);
    });
  });

  group('申請', () {
    MentorRequest req({
      String id = 'r1',
      String from = 'a',
      String to = 'm',
      bool fromMentor = false,
    }) =>
        MentorRequest(
          id: id,
          fromUid: from,
          toUid: to,
          fromName: '學徒',
          fromRank: 20,
          fromMentor: fromMentor,
          at: DateTime(2026, 9, 1),
          expiresAt: DateTime(2026, 9, 8),
        );

    test('收件者看得到申請', () async {
      await as('a').sendRequest(req());
      expect(await as('m').requestsFor('m'), hasLength(1));
    });

    test('不相干的人看不到', () async {
      await as('a').sendRequest(req());
      expect(await as('z').requestsFor('z'), isEmpty);
    });

    test('兩個方向共用同一個結構', () async {
      // 依〈師徒申請 Aggregate〉，學徒申請與教官邀請是同一個 Aggregate
      // 的兩個方向，不是兩件事。
      await as('a').sendRequest(req(id: 'r1', from: 'a', to: 'm'));
      await as('m2')
          .sendRequest(req(id: 'r2', from: 'm2', to: 'a', fromMentor: true));

      expect((await as('m').requestsFor('m')).first.fromMentor, isFalse);
      expect((await as('a').requestsFor('a')).first.fromMentor, isTrue);
    });

    test('處理完就消失', () async {
      await as('a').sendRequest(req());
      await as('m').dropRequest('r1');
      expect(await as('m').requestsFor('m'), isEmpty);
    });
  });
}
