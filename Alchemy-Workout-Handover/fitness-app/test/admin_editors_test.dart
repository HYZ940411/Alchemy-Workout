import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/admin.dart';
import 'package:fitness_app/domain/platform_config.dart';
import 'package:fitness_app/domain/task_pool.dart';
import 'package:fitness_app/state/app_state.dart';

TaskPoolItem item(String id, {TaskAudience a = TaskAudience.personal}) =>
    TaskPoolItem(id: id, name: id, sourceEvent: 'e', target: 1, audience: a);

void main() {
  setUp(platformConfig.reset);
  tearDown(platformConfig.reset);

  group('任務池同時承載限時任務', () {
    test('以適用對象區分，不是兩份清單', () {
      final s = AppState();
      final personal = s.taskPool
          .where((t) => t.audience == TaskAudience.personal)
          .length;
      final team = teamItems(s.taskPool).length;
      expect(personal, greaterThan(0));
      expect(team, greaterThan(0));
      expect(personal + team, s.taskPool.length);
    });

    test('每日抽取只抽個人項，不會抽到團隊項', () {
      // 團隊項刻意佔多數：若過濾沒做，抽 3 項必定混進團隊項。
      final pool = [
        item('p1'),
        item('t1', a: TaskAudience.team),
        item('t2', a: TaskAudience.team),
        item('t3', a: TaskAudience.team),
        item('t4', a: TaskAudience.team),
      ];
      final drawn = drawDaily(pool, 3);
      expect(drawn.map((t) => t.id), ['p1']);
    });

    test('項目數少於抽取數量時抽出全部', () {
      final pool = [item('p1'), item('p2')];
      expect(drawDaily(pool, 5).length, 2);
    });

    test('抽取不去重 —— 兩次抽出的內容可以一樣', () {
      final pool = [item('p1'), item('p2'), item('p3')];
      expect(drawDaily(pool, 3).map((t) => t.id).toSet(),
          drawDaily(pool, 3).map((t) => t.id).toSet());
    });
  });

  group('設定每日任務池', () {
    test('新增／修改／移除都會寫進變更紀錄', () {
      final s = AppState();
      final n = platformConfig.log.length;
      final it = item('新項目');
      expect(s.addTaskPoolItem(it), isNull);
      expect(s.updateTaskPoolItem(it, target: 5), isNull);
      expect(it.target, 5);
      expect(s.removeTaskPoolItem(it), isNull);
      expect(platformConfig.log.length, n + 3);
    });

    test('名稱空白與目標小於 1 都擋下來', () {
      final s = AppState();
      expect(s.addTaskPoolItem(TaskPoolItem(
          id: 'x', name: '  ', sourceEvent: 'e', target: 1)), isNotNull);
      expect(s.addTaskPoolItem(TaskPoolItem(
          id: 'y', name: 'ok', sourceEvent: 'e', target: 0)), isNotNull);
    });

    test('抽取數量至少為 1', () {
      final g = platformConfig.group('taskPool');
      expect(g.invariant!({'drawCount': 0}), isNotNull);
      expect(g.invariant!({'drawCount': 1}), isNull);
    });

    test('調整池子不改動當日已指派的任務 —— 要重抽才會換', () {
      final s = AppState();
      final before = s.dailyTasks.map((t) => t.name).toList();
      s.addTaskPoolItem(item('新加的'));
      expect(s.dailyTasks.map((t) => t.name).toList(), before);
      s.redrawDailyTasks();
      expect(s.dailyTasks.length, kDailyDrawCount);
    });

    test('沒有平台設定權限就改不了', () {
      final s = AppState();
      s.admin = s.admins.firstWhere((a) => !a.can(AdminScope.platformConfig),
          orElse: () => s.admin);
      if (!s.canConfigure) {
        expect(s.addTaskPoolItem(item('z')), contains('權限不足'));
      }
    });
  });

  group('設定限時任務', () {
    test('只能從團隊項目指派', () {
      final s = AppState();
      final personal =
          s.taskPool.firstWhere((t) => t.audience == TaskAudience.personal);
      expect(s.assignTimedTaskFrom(personal), contains('適用對象'));

      final team = teamItems(s.taskPool).first;
      expect(s.assignTimedTaskFrom(team), isNull);
      expect(s.timedTask.title, team.name);
    });

    test('改指派不清掉今天已完成的紀錄', () {
      final s = AppState()..completeTimedTask();
      expect(s.timedTask.doneBy(s.displayName), isTrue);
      s.assignTimedTaskFrom(teamItems(s.taskPool).last);
      expect(s.timedTask.doneBy(s.displayName), isTrue);
    });
  });

  group('設定教官測驗題庫', () {
    test('題庫抽不出考卷時後台要講', () {
      // 2026-09-25：示範題庫已補足到規格的 20＋3，所以預設不再缺題。
      // 改成把題數調高來製造不足 —— 驗的是「不足時會不會講」，
      // 而題庫夠不夠是另一回事（見 `exam_paper_test` 的「示範題庫符合規格」）。
      final s = AppState();
      expect(s.examBankWarning, isNull, reason: '前提：預設題庫是夠的');

      platformConfig.group('exam').param('mcCount').value = 999;
      expect(s.examBankWarning, isNotNull);

      platformConfig.group('exam').param('mcCount').value = 2;
      platformConfig.group('exam').param('saCount').value = 2;
      expect(s.examBankWarning, isNull);
    });

    test('選擇題至少要有兩個選項', () {
      final s = AppState();
      expect(
        s.addExamQuestion(ExamQuestion(
          id: 'q',
          type: ExamQuestionType.multipleChoice,
          text: '只有一個選項',
          options: ['A'],
        )),
        isNotNull,
      );
    });

    test('簡答題沒有選項也加得進去', () {
      final s = AppState();
      final n = s.examBank.length;
      expect(
        s.addExamQuestion(ExamQuestion(
          id: 'q',
          type: ExamQuestionType.shortAnswer,
          text: '請說明你的課表安排邏輯。',
        )),
        isNull,
      );
      expect(s.examBank.length, n + 1);
    });

    test('題目內容不得為空', () {
      final s = AppState();
      expect(
        s.addExamQuestion(ExamQuestion(
            id: 'q', type: ExamQuestionType.shortAnswer, text: '   ')),
        isNotNull,
      );
    });

    test('移除題目會寫進變更紀錄', () {
      final s = AppState();
      final n = platformConfig.log.length;
      s.removeExamQuestion(s.examBank.first);
      expect(platformConfig.log.length, n + 1);
    });
  });
}
