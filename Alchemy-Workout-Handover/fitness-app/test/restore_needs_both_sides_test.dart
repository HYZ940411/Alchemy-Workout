// 恢復需雙方同意，而教官那一側本來整個不存在。
//
// 〈師徒互動流程〉的 `[決策]`：
//
//   · 恢復需雙方同意，不採單方面恢復
//   · 解除為單方面、恢復需雙方同意，兩者刻意不對稱，
//     避免一方反覆解除又拉回
//   · Actor：使用者（**教官與學徒任一方皆可提出**）
//   · Precondition：教官的名額佔用數未達帶徒上限，方可恢復
//
// 2026-09-30 實測前的實作：
//
//   · `applyCloudBonds` 教官側對非生效中的關係直接 `removeWhere`
//     —— 學徒從名單上消失，教官連關係被解除了都看不到
//   · 整套解除／恢復畫面只掛在學徒那一頁上
//   · `mentorRestorePending` 是**本機布林值**，一個字都不上雲
//     —— 同一個人先按「提出」再按「同意」就恢復了
//   · 恢復時沒有檢查帶徒上限

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/mentor_data.dart';
import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/state/app_state.dart';

const _mentorUid = 'u-教官';
const _appUid = 'u-學徒';
const _bondId = '${_mentorUid}_$_appUid';

class _Mentor implements MentorSource {
  final List<(String bond, String? by)> restoreCalls = [];
  final List<String> recovered = [];
  final List<String> released = [];

  @override
  Future<void> proposeRestore(String bondId, String byUid) async =>
      restoreCalls.add((bondId, byUid));
  @override
  Future<void> dropRestore(String bondId) async =>
      restoreCalls.add((bondId, null));
  @override
  Future<void> recover(String bondId, DateTime now) async =>
      recovered.add(bondId);
  @override
  Future<void> release(
          String bondId, MentorReleaseReason reason, DateTime at) async =>
      released.add(bondId);

  @override
  Future<List<CloudBond>> bonds() async => const [];
  @override
  Future<void> bond(CloudBond b) async {}
  @override
  Future<List<CloudMentorTask>> tasks(String bondId) async => const [];
  @override
  Future<void> putTask(String bondId, CloudMentorTask t) async {}
  @override
  Future<void> rateWeek(String bondId, String week, int stars) async {}
  @override
  Future<List<CloudQuestion>> questions(String bondId) async => const [];
  @override
  Future<void> ask(String bondId, CloudQuestion q) async {}
  @override
  Future<void> answer(
      String bondId, String questionId, String text, DateTime at) async {}
  @override
  Future<List<MentorRequest>> requestsFor(String uid) async => const [];
  @override
  Future<List<MentorRequest>> sentRequests() async => const [];
  @override
  Future<void> sendRequest(MentorRequest r) async {}
  @override
  Future<void> dropRequest(String requestId) async {}
  @override
  Stream<void> watchMentor() => const Stream.empty();
}

CloudBond _bond({
  MentorBondState state = MentorBondState.active,
  DateTime? releasedAt,
  String? proposedBy,
}) =>
    CloudBond(
      id: _bondId,
      mentorUid: _mentorUid,
      apprenticeUid: _appUid,
      mentorName: '老王',
      apprenticeName: '小明',
      state: state,
      bondedAt: DateTime(2026, 9, 1),
      releasedAt: releasedAt,
      releasedReason: MentorReleaseReason.byApprentice,
      restoreProposedBy: proposedBy,
    );

({AppState s, _Mentor src}) _instructor() {
  final src = _Mentor();
  final s = AppState(demo: false)
    ..myUid = _mentorUid
    ..isInstructor = true
    ..instructorDutyVersion = kInstructorDutyVersion
    ..peakReputation = 300 // 帶徒上限拉高，名額不是這幾條的變因
    ..mentorSource = src;
  return (s: s, src: src);
}

void main() {
  group('教官看得到已解除的關係', () {
    test('解除之後，學徒不再消失 —— 進「已解除」那一欄', () {
      final m = _instructor();
      m.s.applyCloudBonds([_bond()]);
      expect(m.s.apprentices, hasLength(1), reason: '前提：本來在名單上');

      m.s.applyCloudBonds([
        _bond(state: MentorBondState.released, releasedAt: m.s.now),
      ]);

      expect(m.s.apprentices, isEmpty, reason: '已解除就不算生效中的學徒');
      expect(m.s.releasedApprentices.map((b) => b.apprenticeUid), [_appUid],
          reason: '在此之前這裡什麼都沒有 —— 學徒就此從教官眼前消失');
      expect(m.s.releasedApprentices.single.apprenticeName, '小明');
    });

    test('轉回生效中就不再留在「已解除」那一欄', () {
      final m = _instructor();
      m.s.applyCloudBonds([
        _bond(state: MentorBondState.released, releasedAt: m.s.now),
      ]);
      m.s.applyCloudBonds([_bond()]);
      expect(m.s.releasedApprentices, isEmpty);
      expect(m.s.apprentices, hasLength(1));
    });

    test('教官也解除得了 —— 解除是單方面的', () {
      final m = _instructor();
      m.s.applyCloudBonds([_bond()]);
      m.s.mentorTasks.add(MentorTask(
          id: 'mt-1', title: '沒做完', detail: '', apprenticeUid: _appUid));

      expect(
          m.s.releaseApprentice(_appUid, MentorReleaseReason.byInstructor),
          isTrue);

      expect(m.s.apprentices, isEmpty);
      expect(m.s.releasedApprentices, hasLength(1));
      expect(m.s.mentorTasks.single.state, MentorTaskState.voided,
          reason: '未完成的任務作廢 —— 與學徒那一側同一條規則');
      expect(m.src.released, [_bondId], reason: '要寫上雲，否則對方不知道');
    });
  });

  group('恢復需雙方同意', () {
    test('教官提出之後，自己同意不了', () {
      final m = _instructor();
      m.s.applyCloudBonds([
        _bond(state: MentorBondState.released, releasedAt: m.s.now),
      ]);

      expect(m.s.proposeRestoreFor(_appUid), isTrue);
      expect(m.src.restoreCalls, [(_bondId, _mentorUid)],
          reason: '提議要上雲，否則「雙方同意」無從成立');

      expect(m.s.acceptRestoreFor(_appUid), isFalse,
          reason: '提出的是我 —— 這就是單方面恢復');
      expect(m.s.apprentices, isEmpty);
      expect(m.src.recovered, isEmpty);
    });

    test('對方提出的，教官才同意得了', () {
      final m = _instructor();
      m.s.applyCloudBonds([
        _bond(
            state: MentorBondState.released,
            releasedAt: m.s.now,
            proposedBy: _appUid),
      ]);

      expect(m.s.acceptRestoreFor(_appUid), isTrue);
      expect(m.s.apprentices.map((a) => a.uid), [_appUid],
          reason: '恢復之後學徒要回到名單上');
      expect(m.s.releasedApprentices, isEmpty);
      expect(m.src.recovered, [_bondId]);
    });

    test('拒絕之後提議失效，還能再提', () {
      final m = _instructor();
      m.s.applyCloudBonds([
        _bond(
            state: MentorBondState.released,
            releasedAt: m.s.now,
            proposedBy: _appUid),
      ]);

      expect(m.s.rejectRestoreFor(_appUid), isTrue);
      expect(m.src.restoreCalls.last, (_bondId, null));
      expect(m.s.releasedBondOf(_appUid)!.restoreProposedBy, isNull);
      expect(m.s.proposeRestoreFor(_appUid), isTrue,
          reason: '失效的是那筆提議，不是整段關係');
    });

    test('已經有人提出了就不重複提 —— 否則會蓋掉對方那筆', () {
      final m = _instructor();
      m.s.applyCloudBonds([
        _bond(
            state: MentorBondState.released,
            releasedAt: m.s.now,
            proposedBy: _appUid),
      ]);
      expect(m.s.proposeRestoreFor(_appUid), isFalse);
      expect(m.s.releasedBondOf(_appUid)!.restoreProposedBy, _appUid);
    });
  });

  group('恢復的兩個 Precondition', () {
    test('超過 3 天就不能恢復', () {
      final m = _instructor();
      m.s.applyCloudBonds([
        _bond(
          state: MentorBondState.released,
          releasedAt: m.s.now.subtract(kMentorReleaseCooldown +
              const Duration(hours: 1)),
          proposedBy: _appUid,
        ),
      ]);
      final b = m.s.releasedBondOf(_appUid)!;
      expect(m.s.restoreBlockedReasonOf(b), contains('3 天'));
      expect(m.s.acceptRestoreFor(_appUid), isFalse);
    });

    test('帶徒名額已滿就不能恢復 —— 規格 108 行', () {
      final m = _instructor();
      // 名額佔滿：`peakReputation` 決定上限，這裡把上限壓到 2 再收滿。
      m.s.peakReputation = 0;
      m.s.applyCloudBonds([
        _bond(
            state: MentorBondState.released,
            releasedAt: m.s.now,
            proposedBy: _appUid),
        for (var i = 0; i < m.s.apprenticeCap; i++)
          CloudBond(
            id: '${_mentorUid}_u-別人$i',
            mentorUid: _mentorUid,
            apprenticeUid: 'u-別人$i',
            mentorName: '老王',
            apprenticeName: '別人$i',
            bondedAt: DateTime(2026, 9, 1),
          ),
      ]);
      expect(m.s.apprentices.length, m.s.apprenticeCap, reason: '前提：名額滿了');

      final b = m.s.releasedBondOf(_appUid)!;
      expect(m.s.restoreBlockedReasonOf(b), contains('名額已滿'));
      expect(m.s.acceptRestoreFor(_appUid), isFalse,
          reason: '超收會讓帶徒上限形同虛設');
    });
  });
}
