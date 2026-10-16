// 公開課表審核上雲（2026-10-15，使用者要求補的缺功能）。
//
// 在此之前審核只發生在記憶體裡：管理員的待審清單來自他自己手上的課表，
// 其他使用者送審的課表根本沒有上雲，管理員收不到；申請人也永遠等不到結果。
// 這支測試用真的 Firestore 存取層（假資料庫）跑「送審 → 裁決 → 申請人與全站讀回」的完整往返。

import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/public_plan_data.dart';
import 'package:fitness_app/data/public_plan_data_firestore.dart';
import 'package:fitness_app/domain/custom_plan.dart';
import 'package:fitness_app/domain/models.dart';
import 'package:fitness_app/state/app_state.dart';

class _Boom implements PublicPlanSource {
  @override
  dynamic noSuchMethod(Invocation i) =>
      Future<void>.error(StateError('permission-denied'));
}

/// 讀取一律失敗的來源。**要逐個方法寫**：`noSuchMethod` 回的 `Future<void>`
/// 不是 `Future<List<…>>`，型別轉換先炸，測到的就不是「丟出去」了。
class _BoomRead implements PublicPlanSource {
  Future<T> _fail<T>() => Future<T>.error(StateError('permission-denied'));
  @override
  Future<List<CloudPublicPlan>> myPlans() => _fail();
  @override
  Future<List<CloudPublicPlan>> approvedPlans({int limit = 100}) => _fail();
  @override
  Future<List<CloudPublicPlan>> pendingPlans({int limit = 100}) => _fail();
  @override
  Future<void> submitPlan(CloudPublicPlan p) => _fail();
  @override
  Future<void> judgePlan(String id,
          {required bool approved,
          String? reason,
          required String handlerName}) =>
      _fail();
  @override
  Future<void> withdrawPlan(String id) => _fail();
}

void main() {
  late FakeFirebaseFirestore db;

  AppState user(String uid, String name) => AppState(demo: false)
    ..myUid = uid
    ..displayName = name
    ..publicPlanSource = FirestorePublicPlans(uid: uid, firestore: db);

  AppState adminUser() => user('uAdmin', '管理員')..applyAdminClaim(true);

  setUp(() => db = FakeFirebaseFirestore());

  List<PlanExercise> exs(AppState s) => [
        PlanExercise(
            exercise: s.platformExercises.firstWhere(
                (e) => e.type == ExerciseType.strength && !e.isBodyweight),
            planned: const [PlannedSet(40, 8), PlannedSet(40, 8)]),
      ];

  /// 擁有者建一份課表並送審。
  CustomPlan submitted(AppState owner, {String name = '我的推日'}) {
    owner.addPlan(name, exs(owner));
    final p = owner.customPlans.last;
    owner.publishPlan(p);
    owner.applyPublic(p);
    return p;
  }

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

  test('送審：雲端出現一份待審文件，帶著擁有者與課表內容', () async {
    final owner = user('uO', '小明');
    final p = submitted(owner);
    await settle();

    final doc = await db.collection('public_plans').doc(p.id).get();
    expect(doc.exists, isTrue);
    expect(doc.data()!['state'], 'pending');
    expect(doc.data()!['ownerUid'], 'uO');
    expect(doc.data()!['ownerName'], '小明');
    expect((doc.data()!['plan']['exercises'] as List), hasLength(1));
  });

  test('管理員讀得到別人送審的課表（原本收不到）', () async {
    final owner = user('uO', '小明');
    final p = submitted(owner);
    await settle();

    final admin = adminUser();
    expect(admin.pendingPublicPlans, isEmpty, reason: '前提：他自己手上沒有');
    await admin.loadPublicPlanQueue();

    final got = admin.pendingPublicPlans.single;
    expect(got.id, p.id);
    expect(got.isMine, isFalse);
    expect(got.author, '小明');
    expect(got.totalSets, 2);
    expect(got.state, CustomPlanState.pendingPublic);
  });

  test('通過：申請人讀回「已公開」，全站其他人讀得到並可選用', () async {
    final owner = user('uO', '小明');
    final p = submitted(owner);
    await settle();

    final admin = adminUser();
    await admin.loadPublicPlanQueue();
    admin.approvePublicPlan(admin.pendingPublicPlans.single);
    await settle();

    await owner.loadMyPublicPlans();
    expect(p.state, CustomPlanState.public, reason: '原本申請人永遠等不到結果');

    final viewer = user('uV', '路人');
    await viewer.loadPublicPlans();
    final seen = viewer.customPlans.single;
    expect(seen.state, CustomPlanState.public);
    expect(seen.isMine, isFalse);
    expect(viewer.selectableCustomPlans, contains(seen));
  });

  test('退回：申請人讀回退回與理由；其他人看不到', () async {
    final owner = user('uO', '小明');
    final p = submitted(owner);
    await settle();

    final admin = adminUser();
    await admin.loadPublicPlanQueue();
    admin.rejectPublicPlan(admin.pendingPublicPlans.single, '動作說明不足');
    await settle();

    await owner.loadMyPublicPlans();
    expect(p.state, CustomPlanState.rejected);
    expect(p.rejectReason, '動作說明不足');

    final viewer = user('uV', '路人');
    await viewer.loadPublicPlans();
    expect(viewer.customPlans, isEmpty);
  });

  test('退回後修改再送審：又回到待審', () async {
    final owner = user('uO', '小明');
    final p = submitted(owner);
    await settle();
    final admin = adminUser();
    await admin.loadPublicPlanQueue();
    admin.rejectPublicPlan(admin.pendingPublicPlans.single, '不夠');
    await settle();
    await owner.loadMyPublicPlans();

    owner.resumePublished(p);
    owner.applyPublic(p);
    await settle();

    final again = adminUser();
    await again.loadPublicPlanQueue();
    expect(again.pendingPublicPlans, hasLength(1));
    expect(
        (await db.collection('public_plans').doc(p.id).get()).data()!['rejectReason'],
        isNull,
        reason: '重新送審要清掉上一輪的退回理由');
  });

  test('修改已公開的課表：重新審核，審核期間其他人暫時看不到', () async {
    final owner = user('uO', '小明');
    final p = submitted(owner);
    await settle();
    final admin = adminUser();
    await admin.loadPublicPlanQueue();
    admin.approvePublicPlan(admin.pendingPublicPlans.single);
    await settle();
    await owner.loadMyPublicPlans();
    expect(p.state, CustomPlanState.public);

    owner.editPlan(p, name: '改過的名字', exercises: exs(owner));
    await settle();
    expect(p.state, CustomPlanState.pendingPublic);

    final viewer = user('uV', '路人');
    await viewer.loadPublicPlans();
    expect(viewer.customPlans, isEmpty);
  });

  test('下架：其他人再也看不到', () async {
    final owner = user('uO', '小明');
    final p = submitted(owner);
    await settle();
    final admin = adminUser();
    await admin.loadPublicPlanQueue();
    admin.approvePublicPlan(admin.pendingPublicPlans.single);
    await settle();
    await owner.loadMyPublicPlans();

    owner.takeDownPlan(p);
    await settle();

    final viewer = user('uV', '路人');
    await viewer.loadPublicPlans();
    expect(viewer.customPlans, isEmpty);
  });

  test('刪掉送審中的課表：雲端那份一併下架，管理員佇列不再有它', () async {
    final owner = user('uO', '小明');
    final p = submitted(owner);
    await settle();

    owner.deletePlan(p);
    await settle();

    final admin = adminUser();
    await admin.loadPublicPlanQueue();
    expect(admin.pendingPublicPlans, isEmpty);
  });

  test('別的管理員已經裁決的，重新讀佇列之後不再留在我的清單裡', () async {
    final owner = user('uO', '小明');
    submitted(owner);
    await settle();
    final a1 = adminUser();
    await a1.loadPublicPlanQueue();
    expect(a1.pendingPublicPlans, hasLength(1));

    final a2 = adminUser();
    await a2.loadPublicPlanQueue();
    a2.approvePublicPlan(a2.pendingPublicPlans.single);
    await settle();

    await a1.loadPublicPlanQueue();
    expect(a1.pendingPublicPlans, isEmpty);
  });

  test('一般帳號讀不了待審佇列', () async {
    final owner = user('uO', '小明');
    submitted(owner);
    await settle();

    final nobody = user('uN', '一般人');
    await nobody.loadPublicPlanQueue();
    expect(nobody.pendingPublicPlans, isEmpty);
  });

  test('管理員自己送審的課表不會在佇列裡重複出現', () async {
    final admin = adminUser();
    submitted(admin, name: '管理員的課表');
    await settle();

    await admin.loadPublicPlanQueue();
    expect(admin.pendingPublicPlans, hasLength(1), reason: '只有他自己手上那一份');
  });

  test('別人的公開課表不進我的存檔', () async {
    final owner = user('uO', '小明');
    submitted(owner);
    await settle();
    final admin = adminUser();
    await admin.loadPublicPlanQueue();
    admin.approvePublicPlan(admin.pendingPublicPlans.single);
    await settle();

    final viewer = user('uV', '路人');
    await viewer.loadPublicPlans();
    expect(viewer.customPlans, hasLength(1));
    expect(viewer.toSnapshot()['customPlans'], isEmpty,
        reason: '存檔只放「我的」，別人的每次登入從雲端重讀');
  });

  test('寫不上雲要看得見', () async {
    final owner = AppState(demo: false)
      ..myUid = 'uO'
      ..displayName = '小明'
      ..publicPlanSource = _Boom();
    submitted(owner);
    await settle();

    expect(owner.cloudWriteReport['公開課表送審'], startsWith('失敗'));
  });

  test('同步報告講得出雲端實際讀到什麼（三個數字對不上就是問題所在）', () async {
    final owner = user('uO', '小明');
    submitted(owner);
    await settle();
    final admin = adminUser();
    await admin.loadPublicPlanQueue();
    admin.approvePublicPlan(admin.pendingPublicPlans.single);
    await settle();

    // 申請人自己看：雲端那份是「已通過」。
    final mine = await owner.loadMyPublicPlans();
    expect(mine, contains('我送審過 1 份'));
    expect(mine, contains('已通過 1'));
    expect(mine, contains('審核中 0'));

    // 別人看：讀到 1 份，是別人的，畫面上 1 份。
    final viewer = user('uV', '路人');
    expect(await viewer.loadPublicPlans(),
        '雲端讀到已通過 1 份，其中別人的 1 份，畫面上 1 份');

    // 作者自己讀全站：那一份是自己的，不算「別人的」。
    expect(await owner.loadPublicPlans(),
        '雲端讀到已通過 1 份，其中別人的 0 份，畫面上 0 份');
  });

  test('沒有任何人公開：報告寫 0，而不是失敗', () async {
    final viewer = user('uV', '路人');
    expect(await viewer.loadPublicPlans(),
        '雲端讀到已通過 0 份，其中別人的 0 份，畫面上 0 份');
  });

  test('讀不到要丟出去（讓同步報告寫「失敗」），不能假裝讀到 0 份；現有的課表不動', () async {
    // 原本三個讀取函式都吞掉錯誤：規則擋掉了，同步報告照寫「0 份」，
    // 與「真的沒有人公開」長得一模一樣（2026-10-16 實測：通過的課表別人看不到，查不出為什麼）。
    final viewer = AppState(demo: false)
      ..myUid = 'uV'
      ..publicPlanSource = _BoomRead();
    viewer.customPlans.add(CustomPlan(
        id: 'keep', name: '已讀到的', author: '別人', isMine: false,
        exercises: const [], myUses: 0, state: CustomPlanState.public));

    await expectLater(viewer.loadPublicPlans(), throwsA(isA<StateError>()));
    await expectLater(viewer.loadMyPublicPlans(), throwsA(isA<StateError>()));
    expect(viewer.customPlans.map((p) => p.id), contains('keep'),
        reason: '讀不到不該把已經讀到的清掉');

    final admin = AppState(demo: false)
      ..myUid = 'uA'
      ..publicPlanSource = _BoomRead()
      ..applyAdminClaim(true);
    await expectLater(admin.loadPublicPlanQueue(), throwsA(isA<StateError>()));
  });

  test('安全規則：通過的人人可讀；擁有者只能寫成待審或下架；裁決只有管理員；不硬刪', () {
    final rules = File('firestore.rules').readAsStringSync();
    final i = rules.indexOf('match /public_plans/{planId}');
    expect(i, isNot(-1), reason: '規則裡沒有 public_plans');
    final block = rules.substring(i, rules.indexOf('\n    }\n', i));

    expect(block, contains("resource.data.state == 'approved'"));
    expect(block, contains('resource.data.ownerUid == request.auth.uid'));
    expect(block, contains('isAdmin()'));
    expect(block, contains("request.resource.data.state == 'pending'"),
        reason: '建立時一律是待審');
    expect(block, contains("request.resource.data.state in ['pending', 'withdrawn']"),
        reason: '擁有者不能自己寫成通過或退回');
    expect(block, contains('allow delete: if false'));
  });
}
