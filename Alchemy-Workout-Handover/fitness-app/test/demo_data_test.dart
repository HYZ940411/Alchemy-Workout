// 示範資料的開關（`[QA-02a]`–`[QA-02e]`）。
//
// App 一直是「打開就看得到內容」的 —— 假貼文、假隊伍、假通知、
// 假訓練歷史都寫死在 `mock/` 裡。那在沒有後端的時候是對的：
// 不然整個社群、師徒、團隊的畫面都是空的，做給人看也看不出在做什麼。
//
// 接上 Firestore 之後就不對了。真使用者看到的是假貼文混在真貼文裡，
// 分不出哪一則是真的；而且那些「別人」在雲端根本不存在，
// 點進去關注、私訊、邀請入隊全是死路。
//
// 判準沿用專案裡既有的那一個：`FitnessApp.auth == null` ＝ 沒接後端。
// 所以 [AppState.demo] 預設 true，既有的一千多個測試一行都不必改。

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/exercise_stats.dart';
import 'package:fitness_app/mock/mock_extra.dart';
import 'package:fitness_app/state/app_state.dart';

void main() {
  group('demo 開關', () {
    test('預設是開的 —— 既有測試看到的世界不變', () {
      final s = AppState();
      expect(s.posts, isNotEmpty);
      expect(s.publicTeams, isNotEmpty);
      expect(s.history, isNotEmpty);
    });

    test('關掉之後，「別人」與「我的過去」全都不存在', () {
      final s = AppState(demo: false);

      // 甲、別人的東西
      expect(s.posts, isEmpty, reason: '[QA-02a] 假貼文');
      expect(s.publicTeams, isEmpty, reason: '[QA-02b] 假隊伍');
      expect(s.socialUsers, isEmpty);
      expect(s.instructors, isEmpty);
      expect(s.conversations, isEmpty);
      expect(s.followers, isEmpty);
      expect(s.blockedUsers, isEmpty);
      expect(s.apprentices, isEmpty);
      expect(s.mentorTasks, isEmpty);
      expect(s.questions, isEmpty);

      // 乙、我的過去
      expect(s.notifications, isEmpty, reason: '[QA-02d] 假通知');
      expect(s.history, isEmpty);
      expect(s.checkInRecords, isEmpty);
      expect(s.orders, isEmpty);
      expect(s.creditHistory, isEmpty);
      expect(s.mailbox, isEmpty);
    });

    test('關掉示範資料不會把 App 弄壞 —— 建構子的排程照樣跑得完', () {
      // AppState() 的建構子會跑退步檢查、連續訓練檢查、成就同步…
      // 那些都在讀上面那些集合。空集合走不過的話，真使用者一開 App 就爆。
      expect(() => AppState(demo: false), returnsNormally);
    });

    test('這個開關只管集合，純量由 resetToNewAccount() 歸零', () {
      // 階級 45、經驗 1700、連續訓練 12 天這些寫死的數字**不在**這個
      // 開關的管轄範圍。真使用者走的是 hydrate() → 讀不到存檔 →
      // resetToNewAccount()，那條路已經把它們一次歸位。
      // 這裡把分工釘下來，免得日後有人以為 demo:false 就等於新帳號。
      final s = AppState(demo: false);
      expect(s.trainingStreakDays, 12, reason: '純量不歸這個開關管');

      s.resetToNewAccount();
      expect(s.trainingStreakDays, 0);
      expect(s.totalExp, 0);
      expect(s.coins, 0);
    });
  });

  group('動作趨勢由訓練紀錄推導（[QA-02c]）', () {
    test('沒練過的動作沒有統計', () {
      final s = AppState(demo: false);
      expect(s.exerciseStats['bench'], isNull);
    });

    test('練過幾場就是幾次 —— 不是做過幾組', () {
      // 這條是整組裡最要緊的：原本那張寫死的表宣稱臥推「累積 41 次」，
      // 不管使用者練了什麼都一樣。數字要跟著訓練紀錄走。
      final s = AppState(demo: false);
      s.history.addAll([
        HistoryEntry(DateTime(2026, 9, 1), '推日', 0, 40, 0, [
          HistoryExercise('臥推', [(60, 8), (60, 8), (62.5, 6)],
              id: 'bench'),
        ]),
        HistoryEntry(DateTime(2026, 9, 5), '推日', 0, 40, 0, [
          HistoryExercise('臥推', [(65, 5)], id: 'bench'),
        ]),
      ]);

      final stat = s.exerciseStats['bench']!;
      expect(stat.count, 2, reason: '兩場，不是四組');
    });

    test('一場只佔折線圖一個點，取當場最重的那一組', () {
      // 逐組全畫的話，熱身組會把曲線壓成鋸齒，看不出長期有沒有進步。
      final s = AppState(demo: false);
      s.history.add(
        HistoryEntry(DateTime(2026, 9, 1), '推日', 0, 40, 0, [
          HistoryExercise('臥推', [(40, 12), (60, 8), (50, 10)],
              id: 'bench'),
        ]),
      );

      final stat = s.exerciseStats['bench']!;
      expect(stat.trend, hasLength(1));
      expect(stat.trend.first.weight, 60);
      expect(stat.trend.first.reps, 8);
    });

    test('同重量取次數多的那一組', () {
      final s = AppState(demo: false);
      s.history.add(
        HistoryEntry(DateTime(2026, 9, 1), '推日', 0, 40, 0, [
          HistoryExercise('臥推', [(60, 6), (60, 9)], id: 'bench'),
        ]),
      );
      expect(s.exerciseStats['bench']!.trend.first.reps, 9);
    });

    test('折線圖依時序排列，舊在前', () {
      // 訓練紀錄的順序不保證 —— 雲端回填與補登都可能亂序。
      final s = AppState(demo: false);
      s.history.addAll([
        HistoryEntry(DateTime(2026, 9, 20), '推日', 0, 40, 0, [
          HistoryExercise('臥推', [(70, 5)], id: 'bench'),
        ]),
        HistoryEntry(DateTime(2026, 9, 3), '推日', 0, 40, 0, [
          HistoryExercise('臥推', [(60, 8)], id: 'bench'),
        ]),
      ]);

      final t = s.exerciseStats['bench']!.trend;
      expect([for (final p in t) p.date], ['09/03', '09/20']);
    });

    test('沒有動作 ID 的紀錄不計入 —— 用名稱比對會在改名時對不上', () {
      final s = AppState(demo: false);
      s.history.add(
        HistoryEntry(DateTime(2026, 9, 1), '推日', 0, 40, 0, [
          const HistoryExercise('某個舊動作', []),
        ]),
      );
      expect(s.exerciseStats, isEmpty);
    });

    test('示範資料下的趨勢也是推導出來的，不再是寫死的那張表', () {
      // 假的訓練歷史與假的統計表本來是兩份各自捏造的數字，彼此對不起來。
      final s = AppState();
      final trained = <String>{
        for (final h in s.history)
          for (final e in h.exercises)
            if (e.id != null) e.id!,
      };
      expect(s.exerciseStats.keys.toSet(), trained);
    });
  });

  group('statsFrom 本身', () {
    test('空的訓練紀錄給空的統計，不是錯誤', () {
      expect(statsFrom(const []), isEmpty);
    });

    test('沒有任何一組的動作不計入 —— 那場等於沒練到它', () {
      expect(
        statsFrom([(date: DateTime(2026, 9, 1), id: 'bench', sets: [])]),
        isEmpty,
      );
    });
  });
}
