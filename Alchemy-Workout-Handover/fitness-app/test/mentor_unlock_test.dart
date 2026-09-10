// 師徒功能解鎖的五項進度，必須與畫面上其他地方講的同一件事一致。
//
// 個人頁寫「關注 3」、師徒解鎖清單寫「關注 尚未做過」—— 同一件事兩個答案。
// 原因是歷史計數從 0 起算，而這個帳號一開始就關注著三個人。

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/state/app_state.dart';

void main() {
  test('不變條件：曾經關注過的次數不少於現在關注中的人數', () {
    final s = AppState();
    expect(s.followTotal, greaterThanOrEqualTo(s.following.length),
        reason: '關注中的人比「曾經關注過」還多，是不可能的');
  });

  test('一開始就關注著三個人，解鎖清單就不能寫「尚未做過」', () {
    final s = AppState();
    expect(s.following, isNotEmpty, reason: '前提：假資料確實有關注中的人');
    expect(s.mentorUnlockProgress['關注'], greaterThan(0));
  });

  test('取消關注不扣歷史計數', () {
    final s = AppState();
    final before = s.followTotal;
    final who = s.following.first;
    s.toggleFollow(who);
    expect(s.following.contains(who), isFalse);
    expect(s.followTotal, before, reason: '解鎖條件以歷史行為計數，行為刪除不影響計數');
  });

  test('關注新的人會加計數', () {
    final s = AppState();
    final before = s.followTotal;
    s.toggleFollow('全新的人');
    expect(s.followTotal, before + 1);
  });

  test('五項都做過就解鎖', () {
    final s = AppState();
    expect(s.mentorUnlockProgress.values.every((v) => v > 0), isTrue,
        reason: '假資料五項都有紀錄');
    expect(s.mentorUnlocked, isTrue);
  });

  test('新帳號五項全零，且不繼承解鎖', () {
    final s = AppState();
    s.resetToNewAccount();
    expect(s.followTotal, 0);
    expect(s.following, isEmpty);
    expect(s.mentorUnlockProgress['關注'], 0);
  });

  test('存檔存的是歷史計數本身，不是關注人數', () {
    final s = AppState();
    s.toggleFollow('甲');
    s.toggleFollow('乙');
    final total = s.followTotal;
    s.toggleFollow('甲'); // 取消
    final snap = s.toSnapshot();

    final back = AppState();
    back.applySnapshot(snap);
    expect(back.followTotal, total, reason: '取消過的那一次仍算數');
    expect(back.followTotal, greaterThan(back.following.length));
  });
}
