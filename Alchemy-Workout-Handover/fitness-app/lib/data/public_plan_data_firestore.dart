import 'package:cloud_firestore/cloud_firestore.dart';

import 'public_plan_data.dart';

/// Firestore 上的公開課表審核。
///
/// ```
/// public_plans/{planId}
///   ownerUid, ownerName, state, plan{…}, appliedAt, rejectReason, handlerName, judgedAt
/// ```
class FirestorePublicPlans implements PublicPlanSource {
  /// 這份來源服務哪一個帳號（查「我送過審的」用）。
  final String uid;
  final FirebaseFirestore _db;

  FirestorePublicPlans({required this.uid, FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('public_plans');

  @override
  Future<void> submitPlan(CloudPublicPlan p) => _col.doc(p.id).set({
        'ownerUid': p.ownerUid,
        'ownerName': p.ownerName,
        'state': PublicPlanReview.pending.name,
        'plan': p.plan,
        'appliedAt': Timestamp.fromDate(p.appliedAt),
        // 重新送審要把上一輪的裁決痕跡清掉。
        'rejectReason': null,
        'handlerName': null,
      });

  @override
  Future<List<CloudPublicPlan>> pendingPlans({int limit = 100}) =>
      _read(_col
          .where('state', isEqualTo: PublicPlanReview.pending.name)
          .limit(limit)
          .get());

  @override
  Future<void> judgePlan(String id,
          {required bool approved,
          String? reason,
          required String handlerName}) =>
      _col.doc(id).update({
        'state': (approved ? PublicPlanReview.approved : PublicPlanReview.rejected)
            .name,
        'rejectReason': approved ? null : reason,
        'handlerName': handlerName,
        'judgedAt': FieldValue.serverTimestamp(),
      });

  @override
  Future<List<CloudPublicPlan>> myPlans() =>
      _read(_col.where('ownerUid', isEqualTo: uid).get());

  @override
  Future<List<CloudPublicPlan>> approvedPlans({int limit = 100}) =>
      _read(_col
          .where('state', isEqualTo: PublicPlanReview.approved.name)
          .limit(limit)
          .get());

  @override
  Future<void> withdrawPlan(String id) =>
      _col.doc(id).update({'state': PublicPlanReview.withdrawn.name});

  Future<List<CloudPublicPlan>> _read(
      Future<QuerySnapshot<Map<String, dynamic>>> q) async {
    final snap = await q;
    final out = <CloudPublicPlan>[];
    for (final d in snap.docs) {
      final p = _planOf(d.id, d.data());
      if (p != null) out.add(p);
    }
    // 由舊到新 —— 佇列要先處理等最久的那一筆。
    out.sort((a, b) => a.appliedAt.compareTo(b.appliedAt));
    return out;
  }

  CloudPublicPlan? _planOf(String id, Map<String, dynamic> j) {
    final owner = j['ownerUid'];
    final name = j['ownerName'];
    final plan = j['plan'];
    final at = j['appliedAt'];
    if (owner is! String || name is! String || plan is! Map || at is! Timestamp) {
      return null;
    }
    return CloudPublicPlan(
      id: id,
      ownerUid: owner,
      ownerName: name,
      plan: Map<String, dynamic>.from(plan),
      appliedAt: at.toDate(),
      state: PublicPlanReview.values.firstWhere(
        (s) => s.name == j['state'],
        orElse: () => PublicPlanReview.pending,
      ),
      rejectReason: j['rejectReason'] as String?,
      handlerName: j['handlerName'] as String?,
    );
  }
}
