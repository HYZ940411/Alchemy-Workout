// 每日任務「一開始就顯示完成」要不要發 +10（`[QA-10]`，使用者 2026-10-17 選 A：補發）。
//
// 任務重抽或自存檔還原時，今天早已發生的事讓任務直接是完成的（`reconcileDailyTasks`）。
// 以前那條路只補進度、不發分，使用者看到「完成」卻沒有 +10，團隊日常分數也跟著少。
// 現在補發，但**今天這個 Event 領過就不再領**（重抽、重複叫都不會多領）。

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/store.dart';
import 'package:fitness_app/data/team_data.dart';
import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/domain/models.dart';
import 'package:fitness_app/domain/platform_config.dart';
import 'package:fitness_app/state/app_state.dart';

/// 我有一支隊（日常 0 分），今天的每日任務是 [events] 加一項永遠完成不了的墊底任務
/// （全部完成會加碼 20 分，會把要量的 +10 混在一起）。
AppState _state(List<String> events, {bool filler = true}) {
  final s = AppState()
    ..displayName = '阿昶'
    ..myUid = 'u1';
  s.myTeam = Team(
    id: 't1',
    name: '健金術',
    isPublic: true,
    members: [
      TeamMember('阿昶', 20, TeamRole.leader, uid: 'u1'),
      const TeamMember('甲', 15, TeamRole.member, uid: 'u2'),
      const TeamMember('乙', 15, TeamRole.member, uid: 'u3'),
    ],
    contributions: {},
    lockedGroupSize: 3,
  );
  // 每月前兩天是重新分隊期，團隊分數不累加；那不是這份測試要量的東西。
  var guard = 0;
  while (inRegroupWindow(s.now) && guard++ < 40) {
    s.advanceDemoClock(const Duration(days: 1));
  }
  _setTasks(s, events, filler: filler);
  return s;
}

void _setTasks(AppState s, List<String> events, {bool filler = true}) {
  s.dailyTasks = [
    for (final e in events) DailyTask(name: e, sourceEvent: e, target: 1),
    if (filler)
      DailyTask(name: '墊底', sourceEvent: '永遠不會發生', target: 99),
  ];
}

int _team(AppState s) => s.myTeam!.dailyScore;

void main() {
  setUp(platformConfig.reset);
  tearDown(platformConfig.reset);

  test('今天早就簽到了，重抽出「簽到」任務：直接完成，且補發個人與團隊 +10', () {
    final s = _state(['永遠不會發生的別件事'], filler: false);
    s.checkIn(); // 當下沒有簽到任務，所以沒有任務分數
    final weekly = s.weeklyScore;
    expect(_team(s), 0);

    _setTasks(s, ['使用者已簽到']);
    s.reconcileDailyTasks();

    expect(s.dailyTasks.first.done, isTrue);
    expect(s.weeklyScore - weekly, 10, reason: '個人分數補發');
    expect(_team(s), 10, reason: '團隊日常分數跟著累加');
  });

  test('冪等：再叫幾次都不會多領', () {
    final s = _state(['永遠不會發生的別件事'], filler: false);
    s.checkIn();
    _setTasks(s, ['使用者已簽到']);
    s.reconcileDailyTasks();
    s.reconcileDailyTasks();
    s.awardDoneTasks();
    expect(_team(s), 10);
  });

  test('擋重複領：當下做完領過 +10，重抽出同一件事不再領', () {
    final s = _state(['使用者已簽到']);
    s.checkIn();
    expect(_team(s), 10);

    _setTasks(s, ['使用者已簽到']); // 日中重抽：全新的任務物件
    s.reconcileDailyTasks();
    expect(s.dailyTasks.first.done, isTrue, reason: '進度照樣補成完成');
    expect(_team(s), 10, reason: '但今天這件事已經領過，不能再領');
  });

  test('擋重複領（當下完成這條路）：領過之後重抽，同一件事再做完也不再領', () {
    final s = _state(['使用者已完成該組']);
    s.bumpTaskForTest('使用者已完成該組');
    expect(_team(s), 10);

    _setTasks(s, ['使用者已完成該組']); // 日中重抽：全新的任務、進度 0
    s.bumpTaskForTest('使用者已完成該組');
    expect(s.dailyTasks.first.done, isTrue);
    expect(_team(s), 10, reason: '今天這件事已經領過，當下做完也不能再領');
  });

  test('全部完成加碼也跟著補發', () {
    final s = _state(['永遠不會發生的別件事'], filler: false);
    s.checkIn();
    _setTasks(s, ['使用者已簽到'], filler: false); // 只有一項：完成即全部完成
    s.reconcileDailyTasks();
    expect(_team(s), 30, reason: '任務 10 ＋ 全部完成加碼 20');
  });

  test('award: false 只補進度不發分，之後 awardDoneTasks 才發', () {
    final s = _state(['永遠不會發生的別件事'], filler: false);
    s.checkIn();
    _setTasks(s, ['使用者已簽到']);
    s.reconcileDailyTasks(award: false);
    expect(s.dailyTasks.first.done, isTrue);
    expect(_team(s), 0);
    s.awardDoneTasks();
    expect(_team(s), 10);
  });

  group('存檔還原與隊伍載入的先後', () {
    /// 模擬重新開啟：存檔先還原，這時隊伍還沒載入（`myTeam` 是空的）。
    AppState reopen(AppState before) {
      final snap = jsonDecode(jsonEncode(before.toSnapshot()))
          as Map<String, dynamic>;
      final s = AppState()
        ..displayName = '阿昶'
        ..myUid = 'u1';
      expect(s.applySnapshot(snap), isTrue);
      s.myTeam = null;
      return s;
    }

    CloudTeam cloudTeam({Map<String, int> contributions = const {}}) =>
        CloudTeam(
          id: 't1',
          name: '健金術',
          members: {
            'u1': CloudMember(
                name: '阿昶',
                rank: 20,
                role: TeamRole.leader,
                joinedAt: DateTime(2026, 9, 1)),
          },
          peakSize: 3,
          contributions: contributions,
        );

    test('還原時補上去的完成，等隊伍載入後才發，團隊分數才不會漏', () {
      final before = _state(['永遠不會發生的別件事'], filler: false);
      before.checkIn();
      _setTasks(before, ['使用者已簽到']); // 存檔裡這項還是 0/1（舊版漏掉的情形）
      before.dailyTasks.first.progress = 0;

      final s = reopen(before);
      s.reconcileDailyTasks(award: false); // 載入時只補進度
      expect(s.dailyTasks.first.done, isTrue);

      s.applyCloudTeam(cloudTeam());
      expect(s.myTeam!.dailyScore, 10, reason: '隊伍載入後補發，連團隊一起算');
      // 雲端輪詢會一再套用隊伍；這時雲端已經收到那筆 +10（addScore），不能再多領。
      s.applyCloudTeam(cloudTeam(contributions: {'u1': 10}));
      expect(s.myTeam!.dailyScore, 10, reason: '不能多領');
    });

    test('真的走 hydrate：載入當下只補進度不發分，隊伍載入後才發', () async {
      final before = _state(['永遠不會發生的別件事'], filler: false);
      before.checkIn();
      _setTasks(before, ['使用者已簽到']);
      final store = MemoryStore();
      await store.save(before.toSnapshot());

      final s = AppState()
        ..displayName = '阿昶'
        ..myUid = 'u1';
      await s.hydrate(store);
      expect(s.dailyTasks.first.done, isTrue, reason: '載入時進度補成完成');
      expect(s.taskScoredEvents, isEmpty, reason: '但這時隊伍還沒載入，先不發分');

      s.myTeam = null;
      s.applyCloudTeam(cloudTeam());
      expect(s.myTeam!.dailyScore, 10);
    });

    test('存檔會記住領過的 Event：重開後不會再領一次', () {
      final before = _state(['使用者已簽到']);
      before.checkIn();
      expect(before.taskScoredEvents, contains('使用者已簽到'));

      final s = reopen(before);
      expect(s.taskScoredEvents, contains('使用者已簽到'));
      s.applyCloudTeam(cloudTeam());
      expect(s.myTeam!.dailyScore, 0, reason: '已經領過的，隊伍載入後不會又發');
    });

    test('領過的記錄不靠「任務現在是不是完成」：重抽掉之後重開，重抽回來仍不再領', () {
      final before = _state(['使用者已簽到']);
      before.checkIn();
      expect(_team(before), 10);
      _setTasks(before, ['別件事']); // 重抽：簽到任務不在了，存檔裡沒有任何已完成的簽到任務

      final s = reopen(before);
      s.applyCloudTeam(cloudTeam(contributions: {'u1': 10}));
      _setTasks(s, ['使用者已簽到']); // 又抽到簽到
      s.reconcileDailyTasks();
      expect(s.myTeam!.dailyScore, 10, reason: '今天簽到的分數領過了，記在存檔的 Event 名單裡');
    });

    test('舊存檔沒有這個欄位：已完成的任務當作領過，不會部署後全員再領一次', () {
      final before = _state(['使用者已簽到']);
      before.checkIn();
      final snap = jsonDecode(jsonEncode(before.toSnapshot()))
          as Map<String, dynamic>
        ..remove('taskScoredEvents')
        ..remove('taskScoredDay');
      final s = AppState()
        ..displayName = '阿昶'
        ..myUid = 'u1';
      s.applySnapshot(snap);
      s.myTeam = null;
      s.applyCloudTeam(cloudTeam());
      expect(s.myTeam!.dailyScore, 0);
    });
  });

  group('按讚任務看「今天按了幾則不同的貼文」，不看獎勵終身去重', () {
    List<Post> others(AppState s) =>
        s.posts.where((p) => !s.isMyPost(p)).toList();

    test('先按了 3 則（其中有以前領過獎勵的），之後才重抽出按讚任務：直接 3/3 並補發', () {
      final s = _state(['永遠不會發生的別件事'], filler: false);
      final posts = others(s);
      s.rewardedRequests.add('Like:${posts[0].id}'); // 更早以前按過
      for (final p in posts.take(3)) {
        s.toggleLike(p);
      }
      expect(_team(s), 0, reason: '當下沒有按讚任務，沒有任務分數');

      // 重抽：全新的「按讚 3 則」任務物件，進度 0。
      s.dailyTasks = [
        DailyTask(name: '按讚 3 則貼文', sourceEvent: '互動者已按讚貼文', target: 3),
        DailyTask(name: '墊底', sourceEvent: '永遠不會發生', target: 99),
      ];
      s.reconcileDailyTasks();
      expect(s.dailyTasks.first.progress, 3,
          reason: '今天按過 3 則不同的貼文（含一則以前領過獎勵的）→ 3/3');
      expect(_team(s), 10);
    });

    test('今天按過的貼文清單跟著存檔：重開後補進度還在', () {
      final before = _state(['永遠不會發生的別件事'], filler: false);
      for (final p in others(before).take(2)) {
        before.toggleLike(p);
      }
      final snap = jsonDecode(jsonEncode(before.toSnapshot()))
          as Map<String, dynamic>;
      final s = AppState();
      s.applySnapshot(snap);
      expect(s.likedPostsToday.length, 2);
    });

    test('換日清空', () {
      final s = _state(['永遠不會發生的別件事'], filler: false);
      s.toggleLike(others(s).first);
      expect(s.likedPostsToday, isNotEmpty);
      s.advanceDemoClock(const Duration(days: 1));
      expect(s.likedPostsToday, isEmpty);
    });
  });

  test('換日清空：隔天同一件事可以再領', () {
    final s = _state(['使用者已簽到']);
    s.checkIn();
    expect(_team(s), 10);
    s.advanceDemoClock(const Duration(days: 1));
    expect(s.taskScoredEvents, isEmpty);
  });
}
