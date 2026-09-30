import 'dart:async';
// 外部 AI 的邊界（`[BE-08]`）。
//
// 規格把 LLM 放在軟體邊界**之外**，只規範呼叫時點、扣點、失敗退點與
// 「AI 僅產出建議、不套用」。那四件事在接上外部 API 之前就已經做好了，
// 所以這個檔案測的是**邊界本身**：送出去的形狀、收回來的還原、
// 以及失敗時有沒有走既有的退點流程。
//
// **不接外部 API 時行為必須與接上之前一模一樣** —— 那是既有一千多條
// 測試的前提，這裡第一組就釘住它。

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fitness_app/data/ai_suggestion.dart';
import 'package:fitness_app/data/ai_suggestion_http.dart';
import 'package:fitness_app/domain/ability.dart';
import 'package:fitness_app/domain/ai_adjust.dart';
import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/domain/models.dart';
import 'package:fitness_app/state/app_state.dart';

/// 回傳預先寫好的東西，或是擲出例外。
class _FakeSource implements AiSuggestionSource {
  /// 這幾份假件都不測自動優化 —— **擲例外而不是回空值**：
  /// 回空值會讓「沒被呼叫到」與「回了個空的」長得一樣。
  @override
  Future<RemoteAutoAdjust> suggestAuto({
    required List<PlanExercise> exercises,
    AdjustContext? context,
    Map<String, List<Exercise>> candidates = const {},
  }) =>
      throw UnimplementedError('這個假件不支援自動優化');

  final Map<String, dynamic>? reply;
  final bool throws;
  Map<String, dynamic>? sent;

  /// 意圖分類要回什麼。空值代表「判不出來」（合法結果）。
  final AdjustIntent? classifyAs;

  /// 分類這一支要不要擲例外 —— 驗「AI 掛掉時退回端內規則」。
  final bool classifyThrows;

  /// 擲出去的訊息。用來分辨「額度用完」與「忙線」。
  final String throwMessage;

  String? classified;

  _FakeSource({
    this.reply,
    this.throws = false,
    this.classifyAs,
    this.classifyThrows = false,
    this.throwMessage = '分類逾時',
  });

  @override
  Future<RemoteIntent> classify(String say) async {
    classified = say;
    if (classifyThrows) throw Exception(throwMessage);
    return RemoteIntent(classifyAs);
  }

  @override
  Future<RemoteSuggestion> suggest({
    required List<PlanExercise> exercises,
    required AdjustIntent intent,
    int onlyFrom = 0,
    String? note,
    AdjustContext? context,
    Map<String, List<Exercise>> candidates = const {},
  }) async {
    sent = {
      'intent': intent.name,
      'note': ?note,
      ...encodePlan(exercises, onlyFrom, context: context),
    };
    if (throws) throw Exception('逾時');
    final data = reply!;
    return RemoteSuggestion(
      originOf(data),
      decodeSuggestion(data, exercises, intent, onlyFrom),
      error: errorOf(data),
    );
  }
}

List<PlanExercise> _plan() => [
      PlanExercise(
        exercise: const Exercise(
            id: 'e1', name: '槓鈴臥推', dim: Dim.chest,
            relativeIntensity: 1.0, equipment: '槓鈴'),
        planned: const [PlannedSet(60, 8), PlannedSet(60, 8)],
      ),
      PlanExercise(
        exercise: const Exercise(
            id: 'e2', name: '徒手深蹲', dim: Dim.legs,
            relativeIntensity: 0.6, isBodyweight: true),
        planned: const [PlannedSet(0, 12)],
      ),
    ];

void main() {
  group('送出去的形狀', () {
    test('只送動作名稱與逐組目標 —— 不送使用者是誰', () {
      final got = encodePlan(_plan(), 0);
      expect(got, {
        'exercises': [
          {
            'name': '槓鈴臥推',
            'sets': [
              {'weight': 60.0, 'reps': 8},
              {'weight': 60.0, 'reps': 8},
            ],
          },
          {
            'name': '徒手深蹲',
            'sets': [
              {'weight': 0.0, 'reps': 12},
            ],
          },
        ],
      });
      // 這是刻意的：調整建議用不到身分與身體資料，送了只是擴大外洩面。
      expect(got.toString(), isNot(contains('uid')));
      expect(got.toString(), isNot(contains('bodyweight')));
    });

    test('onlyFrom 之前的動作不送上去', () {
      final got = encodePlan(_plan(), 1);
      expect((got['exercises'] as List).length, 1);
      expect((got['exercises'] as List).first['name'], '徒手深蹲');
    });
  });

  group('收回來的還原', () {
    test('索引要加回 onlyFrom —— 否則會套到已經練完的動作上', () {
      final plan = _plan();
      // 伺服器收到的是切片，所以它回的 index 0 指的是原始課表的 1。
      final s = decodeSuggestion({
        'changes': [
          {
            'index': 0,
            'name': '徒手深蹲',
            'after': [
              {'weight': 0, 'reps': 15},
            ],
          },
        ],
      }, plan, AdjustIntent.easier, 1);

      expect(s.changes.single.exerciseIndex, 1);
      expect(s.changes.single.exerciseName, '徒手深蹲');
      expect(s.changes.single.after.single.targetReps, 15);
    });

    test('名稱對不上就丟掉 —— 這是伺服器之外的第二道', () {
      final s = decodeSuggestion({
        'changes': [
          {
            'index': 0,
            'name': '這個動作不在課表裡',
            'after': [
              {'weight': 50, 'reps': 10},
            ],
          },
        ],
      }, _plan(), AdjustIntent.easier, 0);
      expect(s.changes, isEmpty);
    });

    test('索引超出範圍就丟掉', () {
      final s = decodeSuggestion({
        'changes': [
          {
            'index': 99,
            'name': '槓鈴臥推',
            'after': [
              {'weight': 50, 'reps': 10},
            ],
          },
        ],
      }, _plan(), AdjustIntent.easier, 0);
      expect(s.changes, isEmpty);
    });

    test('before 取的是課表現值，不是伺服器說的', () {
      final s = decodeSuggestion({
        'changes': [
          {
            'index': 0,
            'name': '槓鈴臥推',
            'after': [
              {'weight': 55, 'reps': 10},
            ],
          },
        ],
      }, _plan(), AdjustIntent.easier, 0);
      expect(s.changes.single.before.first.targetWeight, 60);
    });

    test('模型給的理由會被帶回來', () {
      final s = decodeSuggestion({
        'changes': [
          {
            'index': 0,
            'name': '槓鈴臥推',
            'after': [
              {'weight': 55, 'reps': 10},
            ],
            'reason': '你上次 60 公斤第三組只完成 6 下。',
          },
        ],
      }, _plan(), AdjustIntent.easier, 0);
      expect(s.changes.single.reason, '你上次 60 公斤第三組只完成 6 下。');
      expect(s.changes.single.detail, contains('你上次 60 公斤'));
    });

    test('沒有理由或理由是空白時回空值 —— 不在畫面上留一行空的', () {
      for (final r in [null, '', '   ', 42]) {
        final s = decodeSuggestion({
          'changes': [
            {
              'index': 0,
              'name': '槓鈴臥推',
              'after': [
                {'weight': 55, 'reps': 10},
              ],
              'reason': r,
            },
          ],
        }, _plan(), AdjustIntent.easier, 0);
        expect(s.changes.single.reason, isNull, reason: 'reason=$r');
        expect(s.changes.single.detail, s.changes.single.summary);
      }
    });

    test('伺服器回報的失敗原因會被帶回來', () {
      expect(errorOf({'error': 'gemini 404: 模型不存在'}), 'gemini 404: 模型不存在');
      expect(errorOf(const {}), isNull);
      expect(errorOf({'error': '   '}), isNull, reason: '空白不算原因');
      expect(errorOf({'error': 42}), isNull);
    });

    test('分得出是模型產的還是規則產的', () {
      expect(originOf({'source': 'gemini'}), SuggestionOrigin.gemini);
      expect(originOf({'source': 'rule'}), SuggestionOrigin.rule);
      expect(originOf(const {}), SuggestionOrigin.rule, reason: '認不出來就當規則');
    });
  });

  // 2026-09-27 使用者裁決 B：**一律先給 AI 判斷方向**，
  // 端內的關鍵字比對只當 AI 掛掉時的備援。
  //
  // 保守的原則沒有變：模型也被要求「只在明確指向唯一方向時才回答，
  // 否則回 null」。交給模型是為了聽懂更多說法，不是為了無論如何給個答案。
  group('意圖分類：AI 先判，端內規則當備援', () {
    Future<AppState> ask(AiSuggestionSource? source, String say) async {
      final s = AppState()..aiSource = source;
      s.startWorkout(s.platformPlans.firstWhere((p) => p.exercises.isNotEmpty));
      s.aiRequest(AiSource.beforeTraining, '今天狀況不太好');
      await s.aiConfirmDemand(AiSource.beforeTraining, say);
      return s;
    }

    test('AI 判得出來就用 AI 的答案 —— 即使端內規則認不出來', () async {
      final fake = _FakeSource(classifyAs: AdjustIntent.trim);
      // 「我想多練上胸」端內一定認不出來（不在四個方向裡）。
      // 這裡只是要驗「AI 說什麼就是什麼」。
      final s = await ask(fake, '我等一下要趕去接小孩');
      expect(fake.classified, '我等一下要趕去接小孩', reason: '原話要送上去');
      expect(s.aiIntent[AiSource.beforeTraining], AdjustIntent.trim);
      expect(s.intentDecidedBy, 'AI');
    });

    test('AI 判不出來就再問一次 —— 不退回端內規則硬猜', () async {
      final fake = _FakeSource(classifyAs: null);
      final s = await ask(fake, '早安');
      expect(s.aiIntent[AiSource.beforeTraining], isNull);
      expect(s.aiStage[AiSource.beforeTraining], AiStage.clarifying);
      expect(s.intentDecidedBy, contains('判不出來'));
    });

    test('**AI 掛掉時退回端內規則，而且記下來**', () async {
      final fake = _FakeSource(classifyThrows: true);
      final s = await ask(fake, '今天太重了');
      expect(s.aiIntent[AiSource.beforeTraining], AdjustIntent.easier,
          reason: '端內規則接得住這一句');
      expect(s.intentDecidedBy, contains('AI 失敗'),
          reason: '靜默退回在這個專案咬過五次 —— 至少要記下來');
    });

    test('沒接 AI 時就是端內規則，與接上之前一樣', () async {
      final s = await ask(null, '今天太重了');
      expect(s.aiIntent[AiSource.beforeTraining], AdjustIntent.easier);
      expect(s.intentDecidedBy, '端內規則');
    });

    // 使用者回報「分析時間也非常久，得不到答案」。有一半不是真的那麼久，
    // 是**完全沒有跡象**：整段跑完才 notifyListeners()，於是按下送出之後
    // 連他自己打的那句話都不會出現，畫面靜止一秒多（失敗時二十秒）。
    test('請 AI 判讀期間畫面有跡象，而且使用者那句話先出現', () async {
      final gate = Completer<RemoteIntent>();
      final fake = _SlowSource(gate.future);
      final s = AppState()..aiSource = fake;
      s.startWorkout(s.platformPlans.firstWhere((p) => p.exercises.isNotEmpty));
      s.aiRequest(AiSource.beforeTraining, '今天狀況不太好');

      var notified = 0;
      s.addListener(() => notified++);

      final done = s.aiConfirmDemand(AiSource.beforeTraining, '我要趕去接小孩');
      await Future<void>.delayed(Duration.zero);

      expect(s.aiClassifying[AiSource.beforeTraining], isTrue,
          reason: '判讀中要標記起來，畫面才顯示得出「判讀你的需求…」');
      expect(notified, greaterThan(0), reason: '等網路之前就要先更新畫面');
      expect(
        s.aiConversations[AiSource.beforeTraining]!.last.text,
        '我要趕去接小孩',
        reason: '使用者那句話要先出現，不是等 AI 回來才一起冒出來',
      );

      gate.complete(const RemoteIntent(AdjustIntent.trim));
      await done;
      expect(s.aiClassifying[AiSource.beforeTraining], isFalse);
      expect(s.aiIntent[AiSource.beforeTraining], AdjustIntent.trim);
    });

    test('AI 失敗時也要把判讀中的標記收掉 —— 不能卡在轉圈', () async {
      final fake = _FakeSource(classifyThrows: true);
      final s = await ask(fake, '今天太重了');
      expect(s.aiClassifying[AiSource.beforeTraining], isFalse);
    });

    // 2026-09-27 使用者實測：Gemini 回 503「模型忙線」，而畫面上顯示的是
    // 「目前只能往這 4 個方向調」—— 使用者只會以為是自己講錯話，
    // 不會知道系統剛剛壞了一下。兩件事要講不同的話。
    test('AI 掛掉且端內也認不出來 → 說「AI 暫時忙不過來」', () async {
      final s = await ask(_FakeSource(classifyThrows: true), '早安');
      final said = s.aiConversations[AiSource.beforeTraining]!.last.text;
      expect(said, contains('忙不過來'));
      expect(said, contains('未扣點'));
      expect(s.aiUnavailable, isTrue);
    });

    test('AI 好好的、只是這句話不在四個方向裡 → 說「目前只能往這 4 個方向調」',
        () async {
      final s = await ask(_FakeSource(classifyAs: null), '我想多練上胸');
      final said = s.aiConversations[AiSource.beforeTraining]!.last.text;
      expect(said, contains('4 個方向'));
      expect(said, isNot(contains('忙不過來')),
          reason: 'AI 沒壞，不要把自己的限制說成故障');
      expect(s.aiUnavailable, isFalse);
    });

    test('AI 掛掉但端內接得住 → 照常產建議，不提故障', () async {
      final s = await ask(_FakeSource(classifyThrows: true), '今天太重了');
      expect(s.aiIntent[AiSource.beforeTraining], AdjustIntent.easier);
      expect(s.aiStage[AiSource.beforeTraining], AiStage.analyzing);
    });

    test('上一輪掛過，這一輪好了 —— 旗標要歸零', () async {
      final s = AppState()..aiSource = _FakeSource(classifyThrows: true);
      s.startWorkout(s.platformPlans.firstWhere((p) => p.exercises.isNotEmpty));
      s.aiRequest(AiSource.beforeTraining, '今天狀況不太好');
      await s.aiConfirmDemand(AiSource.beforeTraining, '早安');
      expect(s.aiUnavailable, isTrue);

      s.aiSource = _FakeSource(classifyAs: null);
      await s.aiConfirmDemand(AiSource.beforeTraining, '我想多練上胸');
      expect(s.aiUnavailable, isFalse, reason: '不可以一直沿用上一輪的狀態');
    });

    // 使用者實測拿到兩種失敗：
    //   429 "You exceeded your current quota"  —— 額度用完
    //   503 "This model is currently experiencing high demand" —— 忙線
    // 它們對使用者的意義完全不同：忙線等一下再試就好，
    // 額度用完是今天不必再試了。說同一句話，他會一直重試一件不會成功的事。
    group('額度用完與忙線要講不同的話', () {
      test('429 → 說「今天的 AI 額度已用完」', () async {
        final s = await ask(
            _FakeSource(classifyThrows: true, throwMessage: '429 quota'), '早安');
        final said = s.aiConversations[AiSource.beforeTraining]!.last.text;
        expect(said, contains('額度已用完'));
        expect(said, isNot(contains('忙不過來')));
        expect(s.aiQuotaExhausted, isTrue);
      });

      test('503 → 說「AI 暫時忙不過來」', () async {
        final s = await ask(
            _FakeSource(classifyThrows: true, throwMessage: '503 high demand'),
            '早安');
        final said = s.aiConversations[AiSource.beforeTraining]!.last.text;
        expect(said, contains('忙不過來'));
        expect(said, isNot(contains('額度')));
        expect(s.aiQuotaExhausted, isFalse);
      });

      test('上一輪額度用完，這一輪好了 —— 旗標要歸零', () async {
        final s = AppState()
          ..aiSource =
              _FakeSource(classifyThrows: true, throwMessage: '429 quota');
        s.startWorkout(
            s.platformPlans.firstWhere((p) => p.exercises.isNotEmpty));
        s.aiRequest(AiSource.beforeTraining, '今天狀況不太好');
        await s.aiConfirmDemand(AiSource.beforeTraining, '早安');
        expect(s.aiQuotaExhausted, isTrue);

        s.aiSource = _FakeSource(classifyAs: AdjustIntent.trim);
        await s.aiConfirmDemand(AiSource.beforeTraining, '我要趕時間');
        expect(s.aiQuotaExhausted, isFalse);
      });

      test('看得出哪些訊息在講額度', () {
        expect(AppState.looksLikeQuota('gemini 429: quota exceeded'), isTrue);
        expect(AppState.looksLikeQuota('You exceeded your current quota'),
            isTrue);
        expect(AppState.looksLikeQuota('503 high demand'), isFalse);
        expect(AppState.looksLikeQuota('404 not found'), isFalse);
      });
    });

    test('直接點四顆方向鍵不問模型 —— 那已經是答案了', () async {
      final fake = _FakeSource(classifyAs: AdjustIntent.harder);
      final s = await ask(fake, adjustIntentNames[AdjustIntent.trim]!);
      expect(fake.classified, isNull, reason: '根本不該呼叫模型');
      expect(s.aiIntent[AiSource.beforeTraining], AdjustIntent.trim);
      expect(s.intentDecidedBy, '選項');
    });
  });

  group('接上 AppState', () {
    /// 照 `ai_adjust_test.dart` 的建法：開一場訓練，走到「等建議」那一步。
    Future<AppState> upToAnalyzing(AiSuggestionSource? source) async {
      final s = AppState()..aiSource = source;
      s.startWorkout(s.platformPlans.firstWhere((p) => p.exercises.isNotEmpty));
      s.aiRequest(AiSource.beforeTraining, '今天狀況不太好');
      await s.aiConfirmDemand(AiSource.beforeTraining, '整體降強度');
      return s;
    }

    test('不注入就走端內規則 —— 既有測試的前提', () async {
      final s = await upToAnalyzing(null);
      await s.aiProduceSuggestionAsync(AiSource.beforeTraining);
      expect(s.aiStage[AiSource.beforeTraining], AiStage.proposed);
      expect(s.aiLastOrigin, isNull, reason: '沒接外部 API 就沒有來源可言');
      expect(s.aiSuggestion[AiSource.beforeTraining], isNotNull);
    });

    test('注入之後，送出去的是使用者眼前那份課表', () async {
      final fake = _FakeSource(reply: const {'source': 'gemini', 'changes': []});
      final s = await upToAnalyzing(fake);
      final names = s.session!.exercises.map((e) => e.exercise.name).toList();

      await s.aiProduceSuggestionAsync(AiSource.beforeTraining);

      expect(fake.sent!['intent'], 'easier');
      final sent = (fake.sent!['exercises'] as List)
          .map((e) => (e as Map)['name']).toList();
      expect(sent, names, reason: '送的必須是他眼前這一份，不是別的課表');
    });

    test('開啟畫面就直接追問，不必先打一句話', () {
      final s = AppState();
      s.startWorkout(s.platformPlans.firstWhere((p) => p.exercises.isNotEmpty));

      s.aiOpen(AiSource.beforeTraining);

      expect(s.aiStage[AiSource.beforeTraining], AiStage.clarifying);
      final turns = s.aiConversations[AiSource.beforeTraining]!;
      expect(turns.length, 1, reason: '只有 AI 那一句，沒有假造的使用者發言');
      expect(turns.single.role, AiTurnRole.ai);
      expect(turns.single.text, contains('要怎麼調'));
      expect(turns.single.text, contains('替換做不了的動作'));
    });

    test('對話已經開始就不重複問', () {
      final s = AppState();
      s.startWorkout(s.platformPlans.firstWhere((p) => p.exercises.isNotEmpty));
      s.aiOpen(AiSource.beforeTraining);
      final n = s.aiConversations[AiSource.beforeTraining]!.length;

      s.aiOpen(AiSource.beforeTraining);

      expect(s.aiConversations[AiSource.beforeTraining]!.length, n);
    });

    test('沒有假造的使用者發言就不會被當成補充說明', () async {
      final fake = _FakeSource(reply: const {'source': 'gemini', 'changes': []});
      final s = AppState()..aiSource = fake;
      s.startWorkout(s.platformPlans.firstWhere((p) => p.exercises.isNotEmpty));
      s.aiOpen(AiSource.beforeTraining);
      await s.aiConfirmDemand(AiSource.beforeTraining, '整體降強度');

      await s.aiProduceSuggestionAsync(AiSource.beforeTraining);
      expect(fake.sent!.containsKey('note'), isFalse);
    });

    test('看不出意圖時不猜、不扣點、不產建議', () async {
      // 使用者打「早安」也換來一份降強度的課表並被扣一點 —— 他從頭到尾
      // 沒要求調整強度。猜錯的代價不是保守與否，是做了他沒要求的事還收了錢。
      final fake = _FakeSource(reply: const {'source': 'gemini', 'changes': []});
      final s = AppState()..aiSource = fake;
      s.startWorkout(s.platformPlans.firstWhere((p) => p.exercises.isNotEmpty));
      final before = s.aiTotal;
      s.aiRequest(AiSource.beforeTraining, '早安');
      await s.aiConfirmDemand(AiSource.beforeTraining, '我早餐吃蘑菇麵');

      expect(s.aiStage[AiSource.beforeTraining], AiStage.clarifying,
          reason: '停在追問，不往下走');
      expect(s.aiIntent[AiSource.beforeTraining], isNull);
      expect(s.aiTotal, before, reason: '未扣點');
      expect(fake.sent, isNull, reason: '根本不該呼叫模型');
      // 2026-09-27 改了措辭：不說「我看不出你想往哪個方向調」——
      // 使用者打「我想多練上胸」時，系統看得懂，只是不支援。
      // 而方向的個數由值域算，不寫死（原本寫「三個」卻列了四個）。
      final said = s.aiConversations[AiSource.beforeTraining]!.last.text;
      expect(said, contains('${AdjustIntent.values.length} 個方向'));
      for (final i in AdjustIntent.values) {
        expect(said, contains(adjustIntentNames[i]!), reason: '要列出每一個方向');
      }
      expect(said, contains('未扣點'));
    });

    test('再問一次答得出來就繼續', () async {
      final fake = _FakeSource(reply: const {'source': 'gemini', 'changes': []});
      final s = AppState()..aiSource = fake;
      s.startWorkout(s.platformPlans.firstWhere((p) => p.exercises.isNotEmpty));
      s.aiRequest(AiSource.beforeTraining, '早安');
      await s.aiConfirmDemand(AiSource.beforeTraining, '我早餐吃蘑菇麵');
      await s.aiConfirmDemand(AiSource.beforeTraining, '減少組數');

      expect(s.aiStage[AiSource.beforeTraining], AiStage.analyzing);
      expect(s.aiIntent[AiSource.beforeTraining], AdjustIntent.trim);
    });

    test('parseIntent：三個方向都要有寬鬆比對', () {
      // easier 原本是預設值，所以一條寬鬆比對都沒有。改掉預設之後
      // 若不補上，「想降強度」這種最自然的說法反而認不出來。
      expect(AppState.parseIntent('整體降強度'), AdjustIntent.easier);
      expect(AppState.parseIntent('今天肩膀緊，想降強度'), AdjustIntent.easier);
      expect(AppState.parseIntent('今天很累'), AdjustIntent.easier);
      expect(AppState.parseIntent('想加重一點'), AdjustIntent.harder);
      expect(AppState.parseIntent('減少組數'), AdjustIntent.trim);
      expect(AppState.parseIntent('組數少一點'), AdjustIntent.trim);
      // 「換掉臥推」在補上 swap 之前是認不出來的 —— 那時系統做不到，
      // 現在做得到了。
      expect(AppState.parseIntent('換掉臥推'), AdjustIntent.swap);
      expect(AppState.parseIntent('這個器材不在我這'), AdjustIntent.swap);
    });

    test('parseIntent：曖昧與無關的一律回空值', () {
      expect(AppState.parseIntent('早安'), isNull);
      expect(AppState.parseIntent('我早餐吃蘑菇麵'), isNull);
      expect(AppState.parseIntent(''), isNull);
      // 「太難了」是想降強度，舊版的 `難` 會判成升強度 —— 剛好相反。
      expect(AppState.parseIntent('太難了'), isNull);
      // 「減強度」講的不是組數，舊版的 `減` 會判成減組數。
      expect(AppState.parseIntent('減強度'), isNull);
    });

    test('歷來成績會送給模型 —— 這是它勝過規則的唯一憑據', () async {
      final fake = _FakeSource(reply: const {'source': 'gemini', 'changes': []});
      final s = AppState()..aiSource = fake;
      s.startWorkout(s.platformPlans.firstWhere((p) => p.exercises.isNotEmpty));
      s.aiRequest(AiSource.beforeTraining, '今天狀況不太好');
      await s.aiConfirmDemand(AiSource.beforeTraining, '整體降強度');

      await s.aiProduceSuggestionAsync(AiSource.beforeTraining);

      final ctx = fake.sent!['context'] as Map<String, dynamic>;
      expect(ctx['bodyweightKg'], s.bodyweightKg);
      expect(ctx['isMale'], s.isMale);
      expect(ctx['experience'], s.experience);
      expect(ctx['goal'], s.commonGoal);
      expect(ctx['equipment'], isNotEmpty);
      expect(ctx.containsKey('recent'), isTrue);
    });

    test('脈絡裡沒有身分 —— 暱稱與 uid 一律不送', () async {
      final fake = _FakeSource(reply: const {'source': 'gemini', 'changes': []});
      final s = AppState()..aiSource = fake;
      s.myUid = 'uid-12345';
      s.startWorkout(s.platformPlans.firstWhere((p) => p.exercises.isNotEmpty));
      s.aiRequest(AiSource.beforeTraining, '今天狀況不太好');
      await s.aiConfirmDemand(AiSource.beforeTraining, '整體降強度');

      await s.aiProduceSuggestionAsync(AiSource.beforeTraining);

      final body = fake.sent.toString();
      expect(body, isNot(contains('uid-12345')));
      expect(body, isNot(contains(s.displayName)));
    });

    test('使用者原本那幾句話會送給模型 —— 不再被丟掉', () async {
      final fake = _FakeSource(reply: const {'source': 'gemini', 'changes': []});
      final s = AppState()..aiSource = fake;
      s.startWorkout(s.platformPlans.firstWhere((p) => p.exercises.isNotEmpty));
      s.aiRequest(AiSource.duringTraining, '幫我保留一個動作就好');
      await s.aiConfirmDemand(AiSource.duringTraining, '減少組數');

      await s.aiProduceSuggestionAsync(AiSource.duringTraining);

      expect(fake.sent!['note'], '幫我保留一個動作就好');
      expect(fake.sent!['intent'], 'trim', reason: '意圖仍然只有三選一');
    });

    test('只回答三選一時不送 note —— 那已經表達成 intent 了', () async {
      final fake = _FakeSource(reply: const {'source': 'gemini', 'changes': []});
      final s = AppState()..aiSource = fake;
      s.startWorkout(s.platformPlans.firstWhere((p) => p.exercises.isNotEmpty));
      s.aiRequest(AiSource.duringTraining, '整體降強度');
      await s.aiConfirmDemand(AiSource.duringTraining, '整體降強度');

      await s.aiProduceSuggestionAsync(AiSource.duringTraining);
      expect(fake.sent!.containsKey('note'), isFalse);
    });

    test('補充過長時截斷 —— 不讓使用者決定 prompt 有多長', () async {
      final fake = _FakeSource(reply: const {'source': 'gemini', 'changes': []});
      final s = AppState()..aiSource = fake;
      s.startWorkout(s.platformPlans.firstWhere((p) => p.exercises.isNotEmpty));
      s.aiRequest(AiSource.duringTraining, '很' * 500);
      await s.aiConfirmDemand(AiSource.duringTraining, '減少組數');

      await s.aiProduceSuggestionAsync(AiSource.duringTraining);
      expect((fake.sent!['note'] as String).length, 200);
    });

    /// 走到「產出建議」那一步。**changes 不能是空的** ——
    /// 空的會在「沒有可調的空間」就提前返回，走不到後面那幾句。
    Future<AppState> produced({
      required String source,
      String? error,
    }) async {
      final base = AppState();
      base.startWorkout(
          base.platformPlans.firstWhere((p) => p.exercises.isNotEmpty));
      final first = base.session!.exercises.first;

      final s = AppState()
        ..aiSource = _FakeSource(reply: {
          'source': source,
          'error': ?error,
          'changes': [
            {
              'index': 0,
              'name': first.exercise.name,
              'after': [
                {'weight': first.planned.first.targetWeight, 'reps': 33},
              ],
            },
          ],
        });
      s.startWorkout(s.platformPlans.firstWhere((p) => p.exercises.isNotEmpty));
      s.aiRequest(AiSource.beforeTraining, '');
      await s.aiConfirmDemand(AiSource.beforeTraining, '整體降強度');
      await s.aiProduceSuggestionAsync(AiSource.beforeTraining);
      return s;
    }

    test('退回規則時標題不帶「AI」—— 靜默退回咬過這個專案四次', () async {
      final s = await produced(source: 'rule', error: 'gemini 404: 模型不存在');
      final texts =
          s.aiConversations[AiSource.beforeTraining]!.map((t) => t.text);
      expect(texts.any((t) => t.startsWith('建議如下')), isTrue);
      expect(texts.any((t) => t.startsWith('AI 建議如下')), isFalse);
    });

    test('模型產的標題帶「AI」', () async {
      final s = await produced(source: 'gemini');
      final texts =
          s.aiConversations[AiSource.beforeTraining]!.map((t) => t.text);
      expect(texts.any((t) => t.startsWith('AI 建議如下')), isTrue);
    });

    test('使用者看不到那個灰框 —— 建議本來就是可用的，不必多一句', () async {
      final s = await produced(source: 'rule', error: '隨便什麼錯');
      final texts =
          s.aiConversations[AiSource.beforeTraining]!.map((t) => t.text).join();
      expect(texts, isNot(contains('暫時無法使用')));
      expect(texts, isNot(contains('隨便什麼錯')));
    });

    test('對使用者不丟原始錯誤 —— 那串 JSON 是給我們查問題用的', () async {
      final s = await produced(
          source: 'rule',
          error: 'listModels 400: {"error":{"status":"INVALID_ARGUMENT"}}');
      final texts =
          s.aiConversations[AiSource.beforeTraining]!.map((t) => t.text).join();
      expect(texts, isNot(contains('INVALID_ARGUMENT')));
    });

    test('開發者模式才看得到技術細節', () async {
      final s = await produced(source: 'rule', error: 'listModels 400: boom');
      s.developerMode = true;
      // 重跑一次才會用到新的旗標。
      s.aiReset(AiSource.beforeTraining);
      s.aiRequest(AiSource.beforeTraining, '');
      await s.aiConfirmDemand(AiSource.beforeTraining, '整體降強度');
      await s.aiProduceSuggestionAsync(AiSource.beforeTraining);

      final texts =
          s.aiConversations[AiSource.beforeTraining]!.map((t) => t.text);
      expect(texts.any((t) => t.contains('listModels 400')), isTrue);
    });

    test('退回規則時仍講得出為什麼這樣改', () async {
      final s = await produced(source: 'rule', error: '隨便什麼錯');
      final texts =
          s.aiConversations[AiSource.beforeTraining]!.map((t) => t.text).join();
      expect(texts, contains('總反覆量維持不變'),
          reason: '規則引擎逐筆說不出話，但整條規則的依據講得出來');
    });

    test('追問那一句不再說「了解。」—— 前面沒有話可以了解', () {
      final s = AppState();
      s.startWorkout(s.platformPlans.firstWhere((p) => p.exercises.isNotEmpty));
      s.aiOpen(AiSource.beforeTraining);
      final first = s.aiConversations[AiSource.beforeTraining]!.single.text;
      expect(first, isNot(startsWith('了解')));
      expect(first, startsWith('這份課表要怎麼調'));
    });

    test('模型回的建議會取代端內規則的結果', () async {
      final base = AppState()
        ..startWorkout(AppState()
            .platformPlans
            .firstWhere((p) => p.exercises.isNotEmpty));
      final first = base.session!.exercises.first;

      final s = await upToAnalyzing(_FakeSource(reply: {
        'source': 'gemini',
        'changes': [
          {
            'index': 0,
            'name': first.exercise.name,
            'after': [
              {'weight': first.planned.first.targetWeight, 'reps': 33},
            ],
          },
        ],
      }));
      await s.aiProduceSuggestionAsync(AiSource.beforeTraining);

      final sug = s.aiSuggestion[AiSource.beforeTraining]!;
      expect(sug.changes.single.after.single.targetReps, 33,
          reason: '33 是規則引擎絕對算不出來的數字');
      expect(s.aiLastOrigin, SuggestionOrigin.gemini);
    });

    test('還沒產出建議就失敗 —— 不退不該退的點', () async {
      // 這是既有的 bug，接外部 API 才踩到：畫面上的「模擬逾時」
      // 顯示在 analyzing 階段，而扣點發生在「成功產出建議」時。
      // aiFail 原本無條件退 1 點 —— 使用者每失敗一次就白賺一點。
      final s = await upToAnalyzing(null);
      final before = s.aiTotal;
      s.aiFail(AiSource.beforeTraining, AiFailReason.timeout);
      expect(s.aiTotal, before, reason: '沒扣過就不該退');
    });

    test('扣過了才退 —— 成功產出後失敗，點數淨額為零', () async {
      final s = await upToAnalyzing(null);
      final before = s.aiTotal;
      await s.aiProduceSuggestionAsync(AiSource.beforeTraining);
      expect(s.aiTotal, before - 1, reason: '前提：成功產出時扣了一點');

      s.aiFail(AiSource.beforeTraining, AiFailReason.timeout);
      expect(s.aiTotal, before, reason: '扣了就要退回來');
    });

    test('接受之後的失敗不退點 —— 那一點已經定了', () async {
      final s = await upToAnalyzing(null);
      final before = s.aiTotal;
      await s.aiProduceSuggestionAsync(AiSource.beforeTraining);
      s.aiAccept(AiSource.beforeTraining);
      s.aiFail(AiSource.beforeTraining, AiFailReason.timeout);
      expect(s.aiTotal, before - 1);
    });

    test('外部 API 失敗走既有的退點流程 —— 點數淨額為零', () async {
      final s = await upToAnalyzing(_FakeSource(throws: true));
      final before = s.aiTotal;

      await s.aiProduceSuggestionAsync(AiSource.beforeTraining);

      expect(s.aiStage[AiSource.beforeTraining], AiStage.failed);
      expect(s.aiTotal, before,
          reason: '失敗在產出之前，所以沒扣到也不該退 —— 淨額為零');
      expect(s.aiSuggestion[AiSource.beforeTraining], isNull,
          reason: '失敗時維持原課表，不留半份建議');
    });
  });

  group('HTTP 實作', () {
    final url = Uri.parse('https://example.workers.dev');

    HttpAiSuggestionSource src(
      MockClient client, {
      String? token = 'tok',
    }) =>
        HttpAiSuggestionSource(
          endpoint: url,
          idToken: () async => token,
          client: client,
        );

    test('帶上 Bearer token —— Worker 靠它擋掉別人', () async {
      late http.Request seen;
      final s = src(MockClient((r) async {
        seen = r;
        return http.Response(
            jsonEncode({'source': 'rule', 'changes': []}), 200);
      }));
      await s.suggest(exercises: _plan(), intent: AdjustIntent.easier);

      expect(seen.headers['Authorization'], 'Bearer tok');
      expect(jsonDecode(seen.body)['intent'], 'easier');
    });

    test('使用者自己打的話會一起送出去', () async {
      late http.Request seen;
      final s = src(MockClient((r) async {
        seen = r;
        return http.Response(
            jsonEncode({'source': 'rule', 'changes': []}), 200);
      }));
      await s.suggest(
        exercises: _plan(),
        intent: AdjustIntent.trim,
        note: '幫我保留一個動作就好',
      );
      expect(jsonDecode(utf8.decode(seen.bodyBytes))['note'], '幫我保留一個動作就好');
    });

    test('沒有補充時不送 note 這個欄位', () async {
      late http.Request seen;
      final s = src(MockClient((r) async {
        seen = r;
        return http.Response(
            jsonEncode({'source': 'rule', 'changes': []}), 200);
      }));
      await s.suggest(exercises: _plan(), intent: AdjustIntent.easier);
      expect(jsonDecode(seen.body).containsKey('note'), isFalse);
    });

    test('沒登入就不送出去 —— 不浪費一趟往返', () async {
      var called = false;
      final s = src(
        MockClient((_) async {
          called = true;
          return http.Response('{}', 200);
        }),
        token: null,
      );
      await expectLater(
        s.suggest(exercises: _plan(), intent: AdjustIntent.easier),
        throwsA(isA<StateError>()),
      );
      expect(called, isFalse);
    });

    test('非 200 視為失敗 —— 交給既有的退點流程', () async {
      final s = src(MockClient((_) async => http.Response('boom', 500)));
      await expectLater(
        s.suggest(exercises: _plan(), intent: AdjustIntent.easier),
        throwsA(isA<http.ClientException>()),
      );
    });

    test('中文以 UTF-8 解，動作名稱才對得上', () async {
      final s = src(MockClient((_) async => http.Response.bytes(
            utf8.encode(jsonEncode({
              'source': 'gemini',
              'changes': [
                {
                  'index': 0,
                  'name': '槓鈴臥推',
                  'after': [
                    {'weight': 55, 'reps': 10},
                  ],
                },
              ],
            })),
            200,
          )));
      final got =
          await s.suggest(exercises: _plan(), intent: AdjustIntent.easier);
      expect(got.origin, SuggestionOrigin.gemini);
      expect(got.suggestion.changes.single.exerciseName, '槓鈴臥推');
    });
  });
}


/// 卡在呼叫端給的那個 Future 上 —— 用來觀察「等待期間」的狀態。
class _SlowSource implements AiSuggestionSource {
  /// 這幾份假件都不測自動優化 —— **擲例外而不是回空值**：
  /// 回空值會讓「沒被呼叫到」與「回了個空的」長得一樣。
  @override
  Future<RemoteAutoAdjust> suggestAuto({
    required List<PlanExercise> exercises,
    AdjustContext? context,
    Map<String, List<Exercise>> candidates = const {},
  }) =>
      throw UnimplementedError('這個假件不支援自動優化');

  final Future<RemoteIntent> gate;
  _SlowSource(this.gate);

  @override
  Future<RemoteIntent> classify(String say) => gate;

  @override
  Future<RemoteSuggestion> suggest({
    required List<PlanExercise> exercises,
    required AdjustIntent intent,
    int onlyFrom = 0,
    String? note,
    AdjustContext? context,
    Map<String, List<Exercise>> candidates = const {},
  }) =>
      throw UnimplementedError();
}
