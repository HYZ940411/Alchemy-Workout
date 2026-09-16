// 註冊流程的暱稱（`[QA-02h]`）。
//
// 上線驗收時全平台每個人都叫「你」—— 社群動態、團隊成員、私訊、排行榜
// 一律如此。原因是註冊問卷九題裡沒有這一欄，而顯示名稱早就是使用者
// Aggregate 的欄位（帳號刪除範圍與後台稽核表都有它），實作只好給預設值。
//
// 2026-09-16 補入為第 10 欄，事件風暴〈註冊流程〉已同步更新。

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/registration.dart';
import 'package:fitness_app/state/app_state.dart';

/// 填好的草稿。`equipment` 是 final 的集合，所以不能用串接寫。
SignUpDraft _full({String? nickname = '阿昶'}) {
  final d = SignUpDraft()
    ..nickname = nickname
    ..gender = '男'
    ..birthday = DateTime(1995, 5, 5)
    ..heightCm = 175
    ..weightKg = 70
    ..daysPerWeek = 3
    ..duration = '30–60 分鐘'
    ..commonGoal = '增肌'
    ..experience = '中階（6 個月–2 年）';
  d.equipment.add('健身房（全器材）');
  return d;
}

void main() {
  group('暱稱的值域', () {
    test('空字串與純空白都不算填了', () {
      expect(isValidNickname(''), isFalse);
      expect(isValidNickname('   '), isFalse);
      expect(isValidNickname('\n\t'), isFalse);
    });

    test('一個字就夠', () {
      expect(isValidNickname('昶'), isTrue);
    });

    test('上限 12 字，超過不收', () {
      expect(isValidNickname('一二三四五六七八九十十一'), isTrue);
      expect(isValidNickname('一二三四五六七八九十十一二'), isFalse);
    });

    test('前後空白不計入長度', () {
      expect(isValidNickname('  一二三四五六七八九十十一  '), isTrue);
    });

    test('表情符號算一個字，不是兩個', () {
      // length 數的是 UTF-16 碼元，一個表情符號會被算成 2 ——
      // 使用者打了 7 個字卻被擋下來，而且看不出為什麼。
      expect(isValidNickname('💪' * 12), isTrue);
    });
  });

  group('註冊流程', () {
    test('必填 —— 沒有暱稱就不算填完', () {
      expect(_full(nickname: null).complete, isFalse);
      expect(_full().complete, isTrue);
    });

    test('共 10 欄', () {
      expect(SignUpDraft.total, 10);
      expect(_full().filled, hasLength(10));
    });

    test('暱稱是第一欄 —— 空白的草稿從它開始續填', () {
      expect(SignUpDraft().resumeIndex, 0);
    });

    test('填了暱稱之後續填點才往後移', () {
      final d = SignUpDraft()..nickname = '阿昶';
      expect(d.resumeIndex, 1);
    });
  });

  group('落地成顯示名稱', () {
    AppState signedUpAs(String nickname) {
      final s = AppState();
      final d = _full(nickname: nickname);
      final mine = s.signUpDraft;
      mine.nickname = d.nickname;
      mine.gender = d.gender;
      mine.birthday = d.birthday;
      mine.heightCm = d.heightCm;
      mine.weightKg = d.weightKg;
      mine.daysPerWeek = d.daysPerWeek;
      mine.duration = d.duration;
      mine.commonGoal = d.commonGoal;
      mine.experience = d.experience;
      mine.equipment
        ..clear()
        ..addAll(d.equipment);
      s.completeSignUp();
      return s;
    }

    test('完成註冊後暱稱就是顯示名稱，不再是「你」', () {
      // 這一條是整件事的重點。少了它，改了問卷也只是多問一題而已。
      expect(signedUpAs('深蹲的阿昶').displayName, '深蹲的阿昶');
    });

    test('前後空白會被去掉 —— 不然社群列表會排不齊', () {
      expect(signedUpAs('  阿昶  ').displayName, '阿昶');
    });
  });
}
