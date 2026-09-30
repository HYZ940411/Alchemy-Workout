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
import 'package:fitness_app/domain/clock.dart';
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

/// 學徒那一台，關係已解除但還在挽回窗口內。
AppState _releasedApprentice() {
  final s = AppState()
    ..myUid = _appUid
    ..confirmMentorDisclaimer();
  s.myInstructor = s.instructors.first;
  s.releaseMentor(MentorReleaseReason.byInstructor);
  return s;
}

void main() {
  // `advanceDemoClock` 動的是**全域**偏移量，不歸零會累積到後面每一條。
  tearDown(resetAppClock);

  group('已解除期間不能再互動', () {
    // 教官那一側已經看不到這個人了（他不在 `apprentices` 裡），
    // 而學徒這邊原本照樣問得了 —— 問了沒有人收得到。
    // 未完成的任務本來就都作廢了，提問自然也是。

    test('前提：關係確實處於已解除', () {
      final s = _releasedApprentice();
      expect(s.mentorReleased, isTrue);
      expect(s.canRestoreMentor, isTrue, reason: '還在 3 天窗口內');
    });

    test('提問送不出去，而且說得出為什麼', () {
      final s = _releasedApprentice();
      final before = s.questions.length;
      expect(s.askQuestion('那我現在該練什麼'), isFalse);
      expect(s.questions, hasLength(before));
      expect(s.askBlockedReason, contains('已解除'));
    });

    test('任務也標記不了完成', () {
      final s = _releasedApprentice();
      final t = MentorTask(id: 'mt-1', title: '練腿', detail: '');
      s.mentorTasks.add(t);
      expect(s.completeMentorTask(t), isFalse);
      expect(s.completeBlockedReason, contains('已解除'));
      expect(t.state, MentorTaskState.assigned);
    });

    test('恢復之後就能繼續 —— 擋的是期間，不是永久', () {
      final s = _releasedApprentice();
      s.mentorRestoreProposedBy = 'u-對方';
      expect(s.acceptRestore(), isTrue);
      expect(s.mentorReleased, isFalse);
      expect(s.askQuestion('那我現在該練什麼'), isTrue);
    });
  });

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

  group('恢復不了的時候，說得出原因', () {
    // 那幾顆按鈕是 2026-09-30 深夜寫的，而且重蹈了當晚查了一整輪的
    // 那個覆轍：**不管做了沒都跳「師徒關係已恢復」**。
    // 於是使用者按下去、畫面說恢復了、雲端什麼也沒變，而重載之後
    // 解除那一塊還在 —— 又分不出是沒生效還是沒同步。

    test('可以恢復的時候，理由是空的', () {
      final s = _releasedApprentice();
      s.mentorRestoreProposedBy = 'u-對方';
      expect(s.myRestoreBlockedReason, isNull);
      expect(s.acceptRestore(), isTrue);
    });

    test('超過 3 天：理由說得出來，而且真的做不到', () {
      final s = _releasedApprentice();
      s.mentorRestoreProposedBy = 'u-對方';
      s.advanceDemoClock(kMentorReleaseCooldown + const Duration(hours: 1));
      expect(s.myRestoreBlockedReason, contains('3 天'));
      expect(s.acceptRestore(), isFalse);
    });

    test('教官名額已滿：理由說得出來，而且真的做不到', () {
      final s = _releasedApprentice();
      final old = s.myInstructor!;
      // `apprentices` 是唯讀的 —— 換一個滿編的教官物件。
      s.myInstructor = Instructor(
        name: old.name,
        uid: old.uid,
        rank: old.rank,
        reputation: old.reputation,
        apprentices: old.apprenticeCap,
        apprenticeCap: old.apprenticeCap,
        ability: old.ability,
        specialties: old.specialties,
        avgRating: old.avgRating,
        ratingCount: old.ratingCount,
      );
      s.mentorRestoreProposedBy = 'u-對方';
      expect(s.myRestoreBlockedReason, contains('名額已滿'));
      expect(s.acceptRestore(), isFalse);
    });

    test('教官側：理由與做得到與否一致', () {
      final m = _instructor();
      m.s.applyCloudBonds([
        _bond(
            state: MentorBondState.released,
            releasedAt: m.s.now,
            proposedBy: _appUid),
      ]);
      final b = m.s.releasedBondOf(_appUid)!;
      expect(m.s.restoreBlockedReasonOf(b), isNull);
      expect(m.s.acceptRestoreFor(_appUid), isTrue);
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

  group('再解除一次，不該跳出上一輪的恢復請求', () {
    // 真正會漏掉那一筆欄位的是 `FirestoreMentor.release()` ——
    // 本機假物件各寫各的，驗不到它。
    // **打在 Firestore 那一層的在 `release_clears_stale_restore_test`。**
    // 這裡只留本機那一半：解除當下自己也要清乾淨。

    test('學徒側：解除會清掉提議', () {
      final s = _releasedApprentice();
      s.mentorRestoreProposedBy = 'u-對方';
      s.acceptRestore();
      expect(s.mentorReleased, isFalse);

      s.releaseMentor(MentorReleaseReason.byApprentice);
      expect(s.mentorRestoreProposedBy, isNull,
          reason: '解除當下就該清 —— 否則要等雲端讀回來才會正確');
      expect(s.mentorRestorePending, isFalse);
    });

    test('教官側：解除之後那一筆不帶提議', () {
      final m = _instructor();
      m.s.applyCloudBonds([_bond()]);
      m.s.releaseApprentice(_appUid, MentorReleaseReason.byInstructor);
      expect(m.s.releasedApprentices, hasLength(1));
      expect(m.s.releasedBondOf(_appUid)!.restoreProposedBy, isNull);
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
