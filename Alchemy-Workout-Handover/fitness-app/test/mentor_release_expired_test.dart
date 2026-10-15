// 解除師徒關係、冷卻期過了，學徒卻永遠卡住（2026-10-15 使用者回報：
// HYZ 與 123 解除之後，冷卻時間已過，HYZ 申請不了別的教官，也無法重新申請 123）。
//
// 原因有三個：
//   1. `finalizeMentorRelease()`（冷卻期滿 → 教官欄位清空）**全專案沒有任何呼叫端**，
//      只有一條測試在叫它。
//   2. 雲端那筆關係解除之後仍留在 Firestore，`applyCloudBonds()` 每次載入都把它
//      重新讀成「我的教官」，連冷卻期有沒有過都不看。
//   3. `mentorApplyBlockedReason()` 只看 `myInstructor != null`，不看這段關係是不是
//      早就結束了。

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/mentor_data.dart';
import 'package:fitness_app/domain/clock.dart';
import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/domain/inbound.dart';
import 'package:fitness_app/state/app_state.dart';

Instructor _ins(String name, {String? uid}) => Instructor(
      name: name,
      rank: 40,
      uid: uid,
      reputation: 10,
      apprentices: 0,
      apprenticeCap: 5,
      ability: const {},
      specialties: const ['增肌'],
      avgRating: 4.5,
      ratingCount: 3,
    );

CloudBond _released(AppState s, Duration ago) => CloudBond(
      id: 'u-123_u-hyz',
      mentorUid: 'u-123',
      apprenticeUid: 'u-hyz',
      mentorName: '123',
      apprenticeName: 'HYZ',
      state: MentorBondState.released,
      bondedAt: s.now.subtract(const Duration(days: 30)),
      releasedAt: s.now.subtract(ago),
      releasedReason: MentorReleaseReason.byApprentice,
    );

AppState _hyz() => AppState(demo: false)
  ..myUid = 'u-hyz'
  ..displayName = 'HYZ';

void main() {
  // 時鐘偏移是全域的，挪過就要還原（否則會拖累後面的測試檔）。
  tearDown(resetAppClock);

  group('重新載入：雲端那筆已解除的關係', () {
    test('冷卻期過了 → 不再是我的教官，可以申請別人', () {
      final s = _hyz();
      s.applyCloudBonds([_released(s, const Duration(days: 5))]);

      expect(s.myInstructor, isNull);
      expect(s.mentorReleased, isFalse);
      expect(s.mentorApplyBlockedReason(_ins('別的教官', uid: 'u-x')), isNull);
    });

    test('冷卻期過了 → 也可以重新申請同一位教官', () {
      final s = _hyz();
      s.applyCloudBonds([_released(s, const Duration(days: 5))]);

      expect(s.mentorApplyBlockedReason(_ins('123', uid: 'u-123')), isNull);
    });

    test('舊的已結束關係排在前面，新的生效中關係仍要讀到', () {
      // 雲端那筆舊文件不會被刪。HYZ 之後拜了別人，兩筆都讀得到，
      // 順序不保證 —— 讀到舊的就停下來的話，新教官永遠看不到。
      final s = _hyz();
      s.applyCloudBonds([
        _released(s, const Duration(days: 5)),
        CloudBond(
          id: 'u-456_u-hyz',
          mentorUid: 'u-456',
          apprenticeUid: 'u-hyz',
          mentorName: '456',
          apprenticeName: 'HYZ',
          state: MentorBondState.active,
          bondedAt: s.now.subtract(const Duration(days: 1)),
        ),
      ]);

      expect(s.myInstructor?.name, '456');
      expect(s.mentorReleased, isFalse);
    });

    test('冷卻期內 → 仍保留，才有得恢復（不能矯枉過正）', () {
      final s = _hyz();
      s.applyCloudBonds([_released(s, const Duration(days: 1))]);

      expect(s.myInstructor?.name, '123');
      expect(s.mentorReleased, isTrue);
      expect(s.canRestoreMentor, isTrue);
    });
  });

  group('同一個連線期間：冷卻期在中途過完', () {
    AppState released() {
      final s = _hyz();
      s.applyCloudBonds([
        CloudBond(
          id: 'u-123_u-hyz',
          mentorUid: 'u-123',
          apprenticeUid: 'u-hyz',
          mentorName: '123',
          apprenticeName: 'HYZ',
          state: MentorBondState.active,
          bondedAt: s.now.subtract(const Duration(days: 30)),
        )
      ]);
      s.releaseMentor(MentorReleaseReason.byApprentice);
      return s;
    }

    test('時間一到，申請的守衛就放行，不必等任何排程', () {
      final s = released();
      expect(s.mentorApplyBlockedReason(_ins('別人', uid: 'u-x')), isNotNull,
          reason: '前提：冷卻期內仍被擋住');

      // 直接挪時鐘、不跑 advanceDemoClock 的收尾 —— 守衛本身要放行。
      s.demoClockOffset += kMentorReleaseCooldown + const Duration(hours: 1);
      expect(s.myInstructor, isNotNull, reason: '前提：收尾還沒跑');
      expect(s.mentorApplyBlockedReason(_ins('別人', uid: 'u-x')), isNull);
    });

    test('申請成功並順手把舊的關係收掉', () {
      final s = released();
      s.demoClockOffset += kMentorReleaseCooldown + const Duration(hours: 1);

      expect(s.applyMentor(_ins('別人', uid: 'u-x')), isTrue);
      expect(s.myInstructor, isNull, reason: '舊的那段已經結束');
      expect(s.mentorReleasedAt, isNull);
    });

    test('冷卻期內即使對方被我封鎖，也不會被提早收尾', () {
      final s = released();
      s.blockUser('123', uid: 'u-123');
      s.finalizeMentorRelease();
      expect(s.myInstructor, isNotNull);
    });

    test('下一次同步時收尾：冷卻期內讀到的、現在已經過了 → 教官欄位清空', () {
      final s = _hyz();
      final bond = _released(s, const Duration(days: 1));
      s.applyCloudBonds([bond]);
      expect(s.myInstructor, isNotNull, reason: '前提：冷卻期內仍保留');

      s.demoClockOffset += const Duration(days: 3);
      s.applyCloudBonds([bond]);
      expect(s.myInstructor, isNull);
      expect(s.mentorReleasedAt, isNull);
    });
  });

  test('教官側：被解除過的學徒重新申請、我接受 → 不再同時掛在已解除', () {
    final s = AppState(demo: false)
      ..myUid = 'u-123'
      ..displayName = '123'
      ..isInstructor = true
      ..instructorDutyVersion = kInstructorDutyVersion;
    s.releasedApprentices.add(ReleasedBond(
      apprenticeUid: 'u-hyz',
      apprenticeName: 'HYZ',
      releasedAt: s.now.subtract(const Duration(days: 5)),
    ));
    final r = InboundRequest(
      id: 'aa-1',
      kind: InboundKind.apprenticeApply,
      from: 'HYZ',
      fromUid: 'u-hyz',
      fromRank: 20,
      subject: 'HYZ',
      sentAt: s.now,
    );
    s.receiveInbound(r);
    expect(s.acceptInbound(r), isTrue);

    expect(s.apprentices.map((a) => a.uid), ['u-hyz']);
    expect(s.releasedApprentices, isEmpty);
  });
}
