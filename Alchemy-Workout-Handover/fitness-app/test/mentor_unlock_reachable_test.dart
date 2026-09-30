// 師徒功能的五個解鎖條件**每一個都要有路走得到**（2026-09-28）。
//
// 雙人實測 T1：B「無法解鎖師徒功能，就算發文了無法解鎖發文任務，
// 但也找不到分享的部分」。
//
// 查出來：`publishPost()` 有加金幣、有推每日任務，**卻從來沒有呼叫
// `_grantInteraction('Post')`** —— `interactionTotals['發文']` 沒有任何
// 增加的路徑。
//
// 以前看不出來，是因為示範種子給了 18。1F 把那組種子從真帳號清掉之後，
// **師徒功能對所有真實使用者變成永遠解不開**。
//
// 這是「拿掉假資料才發現那條路從來沒接上」的第四次
//（前三次：替換動作、上次訓練日期、優化建議標記）。

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/domain/platform_config.dart';
import 'package:fitness_app/domain/rewards.dart';
import 'package:fitness_app/mock/mock_data.dart';
import 'package:fitness_app/state/app_state.dart';

void main() {
  setUp(platformConfig.reset);
  tearDown(platformConfig.reset);

  /// 一個真實的新帳號 —— 沒有示範種子。
  AppState fresh() => AppState()..resetToNewAccount();

  test('新帳號五項全是 0', () {
    final s = fresh();
    expect(s.mentorUnlockProgress.values.every((v) => v == 0), isTrue);
    expect(s.mentorUnlocked, isFalse);
  });

  test('發文會讓「發文」那一項變成 1', () {
    final s = fresh();
    expect(s.mentorUnlockProgress['發文'], 0);
    s.publishPost('今天練完了', PostVisibility.public);
    expect(s.mentorUnlockProgress['發文'], 1,
        reason: '這一項在此之前沒有任何增加的路徑');
  });

  test('五項各做一次就解鎖 —— 每一項都走得到', () {
    final s = fresh();

    // ① 發文
    s.publishPost('第一篇', PostVisibility.public);
    // ② 按讚（別人的貼文）
    final other = s.posts.firstWhere((p) => !s.isMyPost(p));
    s.toggleLike(other);
    // ③ 留言
    s.addComment(other, '加油');
    // ④ 關注
    s.toggleFollow(s.socialUsers.first.name);
    // ⑤ 分享訓練成果（**結算頁那條，不是貼文詳情頁那顆**）
    s.startWorkout(s.platformPlans.firstWhere((p) => p.id == 'p_push'));
    s.completeCurrentSet();
    final r = s.finishWorkout(EndKind.completed);
    s.shareWorkout(r, '今天很順');

    final progress = s.mentorUnlockProgress;
    for (final e in progress.entries) {
      expect(e.value, greaterThan(0), reason: '「${e.key}」走不到 —— $progress');
    }
    expect(s.mentorUnlocked, isTrue);
  });

  // 解鎖清單上的每一項，都要對得上 `kInteractionKinds` 加上「關注」。
  // 少一項或多一項，畫面上的清單就會與實際判定不符。
  test('清單的項目就是判定的項目', () {
    final s = fresh();
    expect(
      s.mentorUnlockProgress.keys.toSet(),
      {'關注', ...kInteractionKinds},
    );
  });
}
