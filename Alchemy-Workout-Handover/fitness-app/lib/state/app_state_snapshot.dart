part of 'app_state.dart';

/// 存檔格式版本。欄位語意改變時 +1 —— 舊版存檔一律整份忽略，重新開始。
///
/// 不做「盡量套用能認得的欄位」：半套的存檔會讓使用者拿到一個
/// 自相矛盾的狀態（例如金幣還在、但購買紀錄不見了），比重來一次更難解釋。
/// 存檔格式版本。**改動任何欄位的形狀就要升這個數字。**
///
/// v1 → v2：`MailReward` 由「存一句顯示文字」改為「存數額」。
/// 當時沒升版本，於是舊存檔的 `content` 被新讀取器忽略、四個數額欄位
/// 各自預設為 0，下一次自動存檔再把 0 寫回去 —— 信箱裡的獎勵被靜默清空，
/// 而且不可回復。版本不符時整份忽略、回到假資料，比留下歸零的資料好。
const int kSnapshotVersion = 2;

String? _iso(DateTime? d) => d?.toIso8601String();
DateTime? _date(Object? v) =>
    v is String ? DateTime.tryParse(v) : null;

/// 一筆存檔的識別鍵：類別 ＋ 門檻。用索引的話，成就表一改順序，
/// 已解鎖的紀錄就會套到別的成就上。
String _achievementKey(Achievement a) => '${a.category}#${a.threshold}';


Map<String, dynamic> _plannedToJson(List<PlannedSet> l) => {
      // Firestore 不收「陣列裡面再放陣列」，每組用一個小物件。
      'sets': [
        for (final p in l) {'w': p.targetWeight, 'r': p.targetReps},
      ],
    };

List<PlannedSet>? _plannedFromJson(Object? v) {
  if (v is! Map) return null;
  final sets = v['sets'];
  if (sets is! List) return null;
  return [
    for (final e in sets)
      if (e is Map && e['w'] is num && e['r'] is num)
        PlannedSet((e['w'] as num).toDouble(), (e['r'] as num).round()),
  ];
}

Map<String, dynamic> _customPlanToJson(CustomPlan p) => {
      'id': p.id,
      'name': p.name,
      'state': p.state.name,
      'myUses': p.myUses,
      'visibleToFollowers': p.visibleToFollowers,
      'appliedAt': _iso(p.appliedAt),
      'rejectReason': p.rejectReason,
      'lastTrainedAt': _iso(p.lastTrainedAt),
      'lastCompletion': p.lastCompletion,
      'exercises': [
        for (final e in p.exercises)
          {
            'exerciseId': e.exercise.id,
            'planned': _plannedToJson(e.planned),
            if (e.replacedFrom != null) 'replacedFromId': e.replacedFrom!.id,
            if (e.replacedPlanned != null)
              'replacedPlanned': _plannedToJson(e.replacedPlanned!),
            if (e.restSeconds != null) 'restSeconds': e.restSeconds,
            'unit': e.unit.name,
          },
      ],
    };

extension AppStateSnapshot on AppState {
  // ===========================================================================
  // 匯出
  // ===========================================================================

  /// 整份使用者狀態的快照。
  ///
  /// **不含**平台目錄與社群假資料（動作庫、貼文、訂單、團隊、後台佇列）——
  /// 那些在真實系統裡本來就來自伺服器，不是這台裝置上的東西。
  /// 存檔裡的一份自訂訓練讀回來。動作用 id 對回動作庫（平台＋自建）；
  /// **找不到動作的那一筆跳過**，其餘照常讀 —— 一個動作被下架不該讓整份課表消失。
  /// 整份讀不出來（缺 id／名稱）就回空值。
  CustomPlan? _customPlanFromJson(Map<String, dynamic> j) {
    final id = j['id'];
    final name = j['name'];
    if (id is! String || name is! String) return null;
    Exercise? find(Object? exId) {
      if (exId is! String) return null;
      for (final e in [...platformExercises, ...kAllExercises, ...myExercises]) {
        if (e.id == exId) return e;
      }
      return null;
    }

    final exs = <PlanExercise>[];
    final raw = j['exercises'];
    if (raw is List) {
      for (final e in raw) {
        if (e is! Map) continue;
        final ex = find(e['exerciseId']);
        final planned = _plannedFromJson(e['planned']);
        if (ex == null || planned == null) continue;
        exs.add(PlanExercise(
          exercise: ex,
          planned: planned,
          replacedFrom: find(e['replacedFromId']),
          replacedPlanned: _plannedFromJson(e['replacedPlanned']),
          restSeconds:
              e['restSeconds'] is num ? (e['restSeconds'] as num).round() : null,
          unit: _enumByName(PlanUnit.values, e['unit']) ?? PlanUnit.reps,
        ));
      }
    }
    return CustomPlan(
      id: id,
      name: name,
      exercises: exs,
      myUses: j['myUses'] is num ? (j['myUses'] as num).round() : 0,
      state: _enumByName(CustomPlanState.values, j['state']) ??
          CustomPlanState.saved,
      visibleToFollowers: j['visibleToFollowers'] == true,
      appliedAt: _date(j['appliedAt']),
      rejectReason: j['rejectReason'] as String?,
    )
      ..lastTrainedAt = _date(j['lastTrainedAt'])
      ..lastCompletion =
          j['lastCompletion'] is num ? (j['lastCompletion'] as num).toDouble() : null;
  }

  Map<String, dynamic> toSnapshot() => {
        'v': kSnapshotVersion,
        'savedAt': DateTime.now().toIso8601String(),

        // --- 身分與身體數據 ---
        'displayName': displayName,
        'bodyweightKg': bodyweightKg,
        'heightCm': heightCm,
        'isMale': isMale,
        'registeredOn': _iso(registeredOn),
        'signUpCompleted': signUpCompleted,
        'agreedTermsVersion': agreedTermsVersion,

        // --- 註冊問卷的四個欄位（已落地的值） ---
        'daysPerWeek': daysPerWeek,
        'duration': duration,
        'commonGoal': commonGoal,
        'experience': experience,
        'equipmentTier': equipmentTier,
        'birthday': _iso(birthday),
        'motiveGoal': motiveGoal,
        'weightUpdatedAt': _iso(weightUpdatedAt),
        'surveyUpdatedAt': _iso(surveyUpdatedAt),
        'weightAskSkippedAt': _iso(_weightAskSkippedAt),
        'surveyAskSkippedAt': _iso(_surveyAskSkippedAt),

        // --- 能力值 ---
        'points': {for (final e in points.entries) e.key.name: e.value},
        'pending': {for (final e in pending.entries) e.key.name: e.value},
        'trainedDims': [for (final d in trainedDims) d.name],
        'snapshots': {
          for (final e in snapshots.entries)
            '${e.key}': {for (final p in e.value.entries) p.key.name: p.value},
        },
        'decayTimers': {
          for (final e in decayTimers.entries)
            e.key.name: {
              'lastTrainedDate': _iso(e.value.lastTrainedDate),
              'nextDecayAt': _iso(e.value.nextDecayAt),
              'cumulative': e.value.cumulative,
              'floorReached': e.value.floorReached,
            },
        },

        // --- 進度與經濟 ---
        'totalExp': totalExp,
        'coins': coins,
        'trainingStreakDays': trainingStreakDays,
        // 中斷預告發到哪一階。存起來，重開 App 才不會把同一則預告再發一次。
        'trainNoticeStage': _trainNoticeStage.name,
        'checkInNoticeStage': _checkInNoticeStage.name,
        'totalWorkouts': totalWorkouts,
        'totalWorkoutDays': totalWorkoutDays,
        'lastTrainedDate': _iso(lastTrainedDate),
        // 連續簽到天數不存 —— 它由每日簽到紀錄推算而來。
        // 存下來就會有兩份可能對不起來的事實，那正是原本的毛病。
        'checkInTotal': checkInTotal,
        'checkInLongest': checkInLongest,
        // 上次簽到日期不存 —— 它就是簽到紀錄裡最晚的那一天。
        'weeklyScore': weeklyScore,
        'monthlyScore': monthlyScore,
        'lockedRankGroup': lockedRankGroup,
        'lockedMonthlyGroup': lockedMonthlyGroup,
        'makeupTickets': makeupTickets,
        'aiMonthly': aiMonthly,
        'aiPermanent': aiPermanent,

        // --- 當日計數（換日即歸零，但同一天內重開 App 不該重置） ---
        'expGrantedOn': _iso(_expGrantedOn),
        'rewardCounterDay': _iso(_rewardCounterDay),
        'coinsGrantedToday': _coinsGrantedToday,
        'scoreGrantedToday': _scoreGrantedToday,
        'maxCompletionToday': _maxCompletionToday,
        'dailyTaskDay': _iso(_dailyTaskDay),
        'allTasksBonusGiven': _allTasksBonusGiven,
        'interactDay': _iso(_interactDay),
        'interactCounts': {..._interactCounts},
        'aiResetMonth': _iso(_aiResetMonth),
        'lastSnapshotOn': _iso(_lastSnapshotOn),

        // --- 任務與成就 ---
        'dailyTasks': [
          for (final t in dailyTasks)
            {
              'name': t.name,
              'sourceEvent': t.sourceEvent,
              'target': t.target,
              'progress': t.progress,
              'claimed': t.claimed,
            },
        ],
        'achievements': {
          for (final a in achievements)
            if (a.unlocked || a.claimed)
              _achievementKey(a): {
                'unlocked': a.unlocked,
                'claimed': a.claimed,
                'at': _iso(a.unlockedAt),
              },
        },
        'interactionTotals': {...interactionTotals},
        // 互動獎勵的請求識別碼。不存的話重開 App 即可對同一篇再領一次。
        'rewardedRequests': rewardedRequests.toList(),
        // 等我回應的請求。不存的話重開 App 就消失了，而它們各自有
        // 168 小時的期限 —— 「還剩幾天」要跨啟動才算得準。
        'inbox': [for (final r in inbox) r.toJson()],
        'autoOptimizeCount': autoOptimizeCount,
        // 哪一份課表掛著優化建議。**平台目錄存不住它** ——
        // `applyPlatformData()` 每次登入都整份重建（見 `applyOptimizationMark`）。
        'optimizedPlanId': optimizedPlanId,
        'followTotal': followTotal,
        'mentorUnlocked': mentorUnlocked,

        // --- 新手 / 回歸任務 ---
        'noviceStarted': noviceStarted,
        'noviceSelected': noviceSelected,
        'noviceChecked': noviceChecked,
        'noviceFinished': noviceFinished,
        'noviceRewardClaimed': noviceRewardClaimed,

        // --- 引導收尾：偏好訓練時段與體驗評分 ---
        //
        // **這兩個原本不在存檔裡。** 新手任務的最後兩步問了使用者，
        // 然後在下一次重新整理時把答案丟掉 —— 而重填一次還是會丟。
        // 偏好時段沒了，訓練提醒就沒有來源（`reminderSource` 會說
        // 「尚未填寫」）；評分沒了，那一頁又會回頭問一次。
        //
        // 收尾這一段是後來才加的，旁邊的 `noviceStarted`／`noviceFinished`
        // ／`noviceRewardClaimed` 全都有存 —— **只有這兩個漏掉**。
        //
        // **攤平成一維，不可以是「七天各一個陣列」。**
        //
        // Firestore 不收陣列包陣列 —— 而且不是只丟掉那個欄位，是**整份
        // 寫入被拒**。`AppState.saveNow()` 對寫入失敗是靜默吞掉的，
        // 所以症狀會是「從今以後什麼都存不起來」，而且毫無徵兆。
        //
        // 我第一版就是寫成 `[[{from,to}], [], ...]`，本機測試全綠
        // （MemoryStore／FileStore 是純 JSON，收得下巢狀陣列），
        // 上線後使用者回報「填了刷新還是未填寫」—— 真相是那一刻起
        // 他的**所有**資料都停止存檔了。
        //
        // 訓練歷史的 `sets` 早就踩過同一個坑（見 `store_firestore.dart`
        // 的 `_historyToDoc`），但那邊是在 Store 那一層轉形狀。這裡直接
        // 存成攤平的樣子 —— 少一層轉換，就少一個會忘記的地方。
        'preferredTimes': [
          for (var day = 0; day < preferredTimes.byDay.length; day++)
            for (final r in preferredTimes.byDay[day])
              {'day': day, 'from': r.startMin, 'to': r.endMin},
        ],
        'experienceRatings': [
          for (final r in experienceRatings)
            {
              'target': r.target.name,
              'targetId': r.targetId,
              'rater': r.rater,
              if (r.raterUid != null) 'raterUid': r.raterUid,
              'stars': r.stars,
              'feedback': r.feedback,
              'at': _iso(r.at),
            },
        ],
        'socialUnlocked': socialUnlocked,
        'returnTaskAssigned': returnTaskAssigned,
        'returnTaskAssignedAt': _iso(returnTaskAssignedAt),
        'returnTaskViewedAt': _iso(returnTaskViewedAt),
        'returnTaskDone': returnTaskDone,
        'returnTaskDim': returnTaskDim?.name,
        'returnRewardClaimed': returnRewardClaimed,
        // 存紀錄不存計數 —— 連續逾期次數為衍生值。
        'returnTaskLog': [
          for (final r in returnTaskLog)
            {'at': _iso(r.assignedAt), 'overdue': r.overdue},
        ],

        // --- 訂閱與購買 ---
        'membership': membership.name,
        'membershipExpiry': _iso(membershipExpiry),
        'membershipLockedPlanIds': membershipLockedPlanIds,
        'purchasedPlanIds': purchasedPlanIds.toList(),
        'currentPlanId': currentPlan?.id,

        // --- 改名（階段五）---
        'lastRenamedAt': _iso(lastRenamedAt),
        'formerNames': formerNames,

        // --- 關注 ---
        //
        // **鍵不是暱稱**（暱稱重構階段三）。欄位名跟著換，舊存檔裡的
        // `following`／`followers` 因此不會被當成鍵讀進來 ——
        // 版本號要另外維護，換欄位名不用。
        'followingKeys': following.toList(),
        'followerKeys': followers,
        'followNames': _followNames,
        'peakFollowerCount': peakFollowerCount,

        // --- 訓練歷史與信箱（會隨使用累積，丟了最有感） ---
        'history': [
          for (final h in history)
            {
              'date': _iso(h.date),
              'planName': h.planName,
              'volume': h.volume,
              'minutes': h.minutes,
              'calories': h.calories,
              // 2026-09-26 新增。舊存檔沒有這個鍵，讀回來是空值 ——
              // 那是誠實的：那幾場的完成度我們真的不知道。
              if (h.completion != null) 'completion': h.completion,
              'exercises': [
                for (final e in h.exercises)
                  {
                    'id': e.id,
                    'name': e.name,
                    'isTimed': e.isTimed,
                    'sets': [
                      for (final t in e.sets) [t.$1, t.$2],
                    ],
                  },
              ],
            },
        ],
        'mailbox': [
          for (final m in mailbox)
            {
              'source': m.source,
              // 存數額，不存顯示文字 —— 文字由數額推導。
              'exp': m.exp,
              'coins': m.coins,
              'makeupTickets': m.makeupTickets,
              'aiCredits': m.aiCredits,
              'at': _iso(m.at),
              'claimed': m.claimed,
            },
        ],
        // **通知連同已讀狀態一起存。**
        //
        // 在此之前整份通知清單完全不進存檔：每次啟動都是空的，再由
        // `runStreakCheck()` 之類的重新產生一遍，而新產生的一律是未讀。
        // 於是「已讀」只活在記憶體裡 —— 使用者一重新整理，讀過的通知
        // 全部變回未讀，紅點也跟著回來。
        //
        // 舊存檔沒有這個鍵，讀進來就是空清單，與現在的行為相同，
        // 所以不必升 `kSnapshotVersion`。
        'notifications': [
          for (final n in notifications)
            {
              'id': n.id,
              'sourceEvent': n.sourceEvent,
              'title': n.title,
              'body': n.body,
              'at': _iso(n.at),
              'kind': n.kind.name,
              'priority': ?n.priority?.name,
              'read': n.read,
            },
        ],
        // 每日簽到紀錄：只存已簽到的日子。
        'checkInRecords': [
          for (final e in checkInRecords.entries)
            {'date': _iso(e.key), 'method': e.value.name},
        ],

        // --- 自建動作 ---
        'myExercises': [
          for (final e in myExercises)
            if (e.isCustom)
              {
                'id': e.id,
                'name': e.name,
                'dim': e.dim?.name,
                'equipment': e.equipment,
                'isBodyweight': e.isBodyweight,
                'type': e.type.name,
                'defaultRestSeconds': e.defaultRestSeconds,
              },
        ],

        // --- 我的自訂訓練 ---
        //
        // 只存「我的」。**在此之前整份沒存**：建好的課表重新整理就不見了，
        // 而畫面上寫著「已儲存」（第二批第 4 項實測，2026-10-15）。
        'customPlans': [
          for (final p in customPlans)
            if (p.isMine) _customPlanToJson(p),
        ],

        // --- 教官 ---
        'isInstructor': isInstructor,
        'instructorReputation': instructorReputation,
        'peakReputation': peakReputation,
        'instructorSpecialties': instructorSpecialties.toList(),

        // **這兩個不進存檔的話，每次重新整理就退回「還沒確認」。**
        // 而它們守的是 Command：教官不能指派任務、學徒不能提問 ——
        // 兩者都是靜靜地不做事，畫面照樣說成功了。
        // 2026-09-30：教官指派任務，toast 跳「已指派」、雲端什麼都沒有。
        'instructorDutyVersion': instructorDutyVersion,
        'mentorDisclaimerVersion': mentorDisclaimerVersion,

        // **這兩份記的是「這筆帳已經算過了」，不是畫面上的東西。**
        // 學徒的評分存在雲端，我每次重讀都會再看到它一次；少了這兩份，
        // 教官每重開一次 App 聲望就再加一次。
        'creditedTaskRatings': creditedTaskRatings.toList(),
        'creditedWeeklyRatings': creditedWeeklyRatings.toList(),

        // --- 師徒的週期計數器 ---
        // 一併存檔，否則重開 App 就等於過了一個新的週 ——
        // 「每週最多 N 次」的上限會從另一道門重新變成無上限。
        'mentorWeek': _iso(_mentorWeek),
        'ratedThisWeek': ratedThisWeek,
        'taskRatingsThisWeek': taskRatingsThisWeek,
        'mentorRewardsThisWeek': mentorRewardsThisWeek,

        // 累計違規次數**不隨時間清零**，故必須跨重啟保留 ——
        // 不存的話每次重開 App 都從警告重新起算。
        'myViolations': myViolations,

        // --- 設定 ---
        'ownedEquipment': ownedEquipment.toList(),
        'aiAutoOptimize': aiAutoOptimize,
        'abilityPublic': abilityPublic,
        'overallGradePublic': overallGradePublic,
        'email': email,
        'metricUnits': metricUnits,
        'deletionRequestedAt': _iso(deletionRequestedAt),
        'deletionCoolingDays': deletionCoolingDays,

        // --- 示範時鐘 ---
        // 存它是因為退步、冷卻、到期全掛在它身上；不存的話重開就跳回現在，
        // 剛快轉出來的那些狀態會整批消失。
        'demoClockOffsetMs': demoClockOffset.inMilliseconds,
      };

  // ===========================================================================
  // 匯入
  // ===========================================================================

  /// 套用一份快照。版本不符即整份忽略，回傳 false。
  bool applySnapshot(Map<String, dynamic> j) {
    if (j['v'] != kSnapshotVersion) return false;

    T? pick<T>(String key) => j[key] is T ? j[key] as T : null;
    int intOf(String key, int fallback) =>
        j[key] is num ? (j[key] as num).round() : fallback;
    double dblOf(String key, double fallback) =>
        j[key] is num ? (j[key] as num).toDouble() : fallback;
    bool boolOf(String key, bool fallback) => pick<bool>(key) ?? fallback;
    List<String> strs(String key) => [
          for (final v in (pick<List>(key) ?? const [])) if (v is String) v,
        ];

    displayName = pick<String>('displayName') ?? displayName;
    bodyweightKg = dblOf('bodyweightKg', bodyweightKg);
    heightCm = dblOf('heightCm', heightCm);
    isMale = boolOf('isMale', isMale);
    registeredOn = _date(j['registeredOn']) ?? registeredOn;
    signUpCompleted = boolOf('signUpCompleted', signUpCompleted);
    // **讀不到就是空值，不是沿用預設的現行版本。** 這個欄位 2026-09-24
    // 才加，舊存檔一個都沒有 —— 沿用預設等於替他們按了同意鍵。
    agreedTermsVersion = pick<String>('agreedTermsVersion');

    daysPerWeek = intOf('daysPerWeek', daysPerWeek);
    duration = pick<String>('duration') ?? duration;
    commonGoal = pick<String>('commonGoal') ?? commonGoal;
    experience = pick<String>('experience') ?? experience;
    equipmentTier = pick<String>('equipmentTier') ?? equipmentTier;
    birthday = _date(pick<String>('birthday')) ?? birthday;
    motiveGoal = pick<String>('motiveGoal') ?? motiveGoal;
    weightUpdatedAt = _date(j['weightUpdatedAt']);
    surveyUpdatedAt = _date(j['surveyUpdatedAt']);
    _weightAskSkippedAt = _date(j['weightAskSkippedAt']);
    _surveyAskSkippedAt = _date(j['surveyAskSkippedAt']);

    void readDims(String key, Map<Dim, int> target) {
      final m = pick<Map>(key);
      if (m == null) return;
      for (final d in Dim.values) {
        final v = m[d.name];
        if (v is num) target[d] = v.round();
      }
    }

    readDims('points', points);
    readDims('pending', pending);
    final dims = strs('trainedDims');
    if (pick<List>('trainedDims') != null) {
      trainedDims
        ..clear()
        ..addAll(Dim.values.where((d) => dims.contains(d.name)));
    }

    final snaps = pick<Map>('snapshots');
    if (snaps != null) {
      snapshots.clear();
      snaps.forEach((k, v) {
        final day = int.tryParse('$k');
        if (day == null || v is! Map) return;
        snapshots[day] = {
          for (final d in Dim.values)
            if (v[d.name] is num) d: (v[d.name] as num).round(),
        };
      });
    }

    final timers = pick<Map>('decayTimers');
    if (timers != null) {
      for (final d in Dim.values) {
        final t = timers[d.name];
        if (t is! Map) continue;
        final last = _date(t['lastTrainedDate']);
        if (last == null) continue;
        decayTimers[d] = DimDecay(lastTrainedDate: last)
          ..nextDecayAt = _date(t['nextDecayAt'])
          ..cumulative = t['cumulative'] is num
              ? (t['cumulative'] as num).round()
              : 0
          ..floorReached = t['floorReached'] == true;
      }
    }

    totalExp = intOf('totalExp', totalExp);
    coins = intOf('coins', coins);
    trainingStreakDays = intOf('trainingStreakDays', trainingStreakDays);
    _trainNoticeStage =
        _enumByName(DecayStage.values, j['trainNoticeStage']) ??
            _trainNoticeStage;
    _checkInNoticeStage =
        _enumByName(CheckInStage.values, j['checkInNoticeStage']) ??
            _checkInNoticeStage;
    totalWorkouts = intOf('totalWorkouts', totalWorkouts);
    totalWorkoutDays = intOf('totalWorkoutDays', totalWorkoutDays);
    lastTrainedDate = _date(j['lastTrainedDate']) ?? lastTrainedDate;
    // 舊存檔可能仍帶著 checkInStreak，一律忽略：以簽到紀錄推算為準。
    checkInTotal = intOf('checkInTotal', checkInTotal);
    checkInLongest = intOf('checkInLongest', checkInLongest);
    // 舊存檔可能仍帶著 lastCheckInDate，一律忽略：以簽到紀錄為準。
    weeklyScore = intOf('weeklyScore', weeklyScore);
    monthlyScore = intOf('monthlyScore', monthlyScore);
    // 空值有意義（本週期尚未鎖定），故不能用「取不到就沿用」的寫法。
    lockedRankGroup =
        j['lockedRankGroup'] is num ? (j['lockedRankGroup'] as num).round() : null;
    lockedMonthlyGroup = j['lockedMonthlyGroup'] is num
        ? (j['lockedMonthlyGroup'] as num).round()
        : null;
    makeupTickets = intOf('makeupTickets', makeupTickets);
    aiMonthly = intOf('aiMonthly', aiMonthly);
    aiPermanent = intOf('aiPermanent', aiPermanent);

    _expGrantedOn = _date(j['expGrantedOn']);
    _rewardCounterDay = _date(j['rewardCounterDay']);
    _coinsGrantedToday = intOf('coinsGrantedToday', 0);
    _scoreGrantedToday = intOf('scoreGrantedToday', 0);
    _maxCompletionToday = dblOf('maxCompletionToday', 0);
    _dailyTaskDay = _date(j['dailyTaskDay']);
    _allTasksBonusGiven = boolOf('allTasksBonusGiven', false);
    _interactDay = _date(j['interactDay']);
    final counts = pick<Map>('interactCounts');
    if (counts != null) {
      _interactCounts
        ..clear()
        ..addAll({
          for (final e in counts.entries)
            if (e.value is num) '${e.key}': (e.value as num).round(),
        });
    }
    _aiResetMonth = _date(j['aiResetMonth']);
    _lastSnapshotOn = _date(j['lastSnapshotOn']);

    final tasks = pick<List>('dailyTasks');
    if (tasks != null) {
      dailyTasks = [
        for (final t in tasks)
          if (t is Map && t['name'] is String)
            DailyTask(
              name: t['name'] as String,
              sourceEvent: '${t['sourceEvent']}',
              target: t['target'] is num ? (t['target'] as num).round() : 1,
              progress:
                  t['progress'] is num ? (t['progress'] as num).round() : 0,
              claimed: t['claimed'] == true,
            ),
      ];
      if (dailyTasks.isEmpty) dailyTasks = buildDailyTasks();
    }

    final unlocked = pick<Map>('achievements');
    if (unlocked != null) {
      for (final a in achievements) {
        final e = unlocked[_achievementKey(a)];
        // **存檔是權威**：先一律歸為未解鎖，再套用存檔說的。
        //
        // 不能寫成 `存檔 || 現況` —— 建構子會先對**假資料**跑一次
        // [_syncAchievements]（預設 totalExp 1700 ＝ 45 階），
        // 那一次解鎖的成就會被 `|| 現況` 保留下來，蓋在真實存檔之上。
        // 結果就是成就頁寫「達到 45 階 ✓」，個人頁寫「38 階」。
        // 解鎖為單調遞增指的是**同一個帳號存續期間**，不是跨存檔載入。
        a.unlocked = e is Map && e['unlocked'] == true;
        a.claimed = e is Map && e['claimed'] == true;
        a.unlockedAt = e is Map ? _date(e['at']) : null;
      }
      // **補跑的解鎖判定不在這裡** —— 見 `applySnapshot` 結尾。
      //
      // 原本在這裡就呼叫 `syncAchievementsAfterLoad()`，而那時候
      // **後面的欄位都還沒還原**：互動計數在第 520 行左右、
      // 訓練天數在 `repairLoadedState()`。於是重算讀到的是建構子
      // 留下的**示範種子**（`interactionTotals` 的 `{按讚:143, …}`）。
      //
      // 2026-09-28 使用者實測：一個讚都沒按過，卻有「按讚 1／10／25／
      // 50／100 次」五個已解鎖成就 —— 就是這樣來的。
      // 而且它**在計數被清空之後仍然留著**：成就是單調遞增的，
      // 一旦被錯誤地解鎖就撤不回來。
    }

    final box = pick<List>('inbox');
    if (box != null) {
      inbox
        ..clear()
        ..addAll(box.map(InboundRequest.fromJson).nonNulls);
    }
    final reqs = pick<List>('rewardedRequests');
    if (reqs != null) {
      rewardedRequests
        ..clear()
        ..addAll(reqs.map((e) => '$e'));
    }
    // **先清空再填。**
    //
    // 原本是直接覆寫存檔裡有的鍵 —— 而 `interactionTotals` 有一組示範用的
    // 種子值（`{分享:26, 發文:18, 按讚:143, 留言:41}`）。新帳號在
    // `resetToNewAccount()` 裡被清空，存進去的是 `{}`；讀回來時
    // `{}` 不是 null，但**迴圈一圈都沒跑**，種子值原封不動留著。
    //
    // 2026-09-28 使用者實測：貼文 0、粉絲 0、關注 0、訓練 6 次，
    // **按讚卻是 145**，而且「按讚 1／10／25／50／100 次」五個成就
    // 一開始就已領取 —— 他一個讚都沒按過。
    //
    // 旁邊的 `interactCounts` 與 `snapshots` 本來就是先 clear 再 addAll，
    // **這一處是唯一的例外**。
    final totals = pick<Map>('interactionTotals');
    if (totals != null) {
      interactionTotals
        ..clear()
        ..addAll({
          for (final e in totals.entries)
            if (e.value is num) '${e.key}': (e.value as num).round(),
        });
    }

    followTotal = intOf('followTotal', followTotal);
    autoOptimizeCount = intOf('autoOptimizeCount', autoOptimizeCount);
    optimizedPlanId = pick<String>('optimizedPlanId');
    // 存檔載回來之後，記號要貼回目錄上才看得見。
    applyOptimizationMark();
    // 單調遞增：存檔說解鎖過就是解鎖過。
    if (boolOf('mentorUnlocked', false)) markMentorUnlocked();

    noviceStarted = boolOf('noviceStarted', noviceStarted);
    noviceSelected = pick<String>('noviceSelected');
    noviceChecked = boolOf('noviceChecked', noviceChecked);
    noviceFinished = boolOf('noviceFinished', noviceFinished);
    noviceRewardClaimed = boolOf('noviceRewardClaimed', noviceRewardClaimed);

    // 缺鍵時不動預設值（空的）—— 舊存檔沒有這兩個鍵。
    if (pick<List>('preferredTimes') case final rows?) {
      final byDay = List.generate(7, (_) => <TimeRange>[]);
      for (final r in rows) {
        if (r is! Map) continue;
        final day = (r['day'] as num?)?.toInt();
        final from = (r['from'] as num?)?.toInt();
        final to = (r['to'] as num?)?.toInt();
        if (day == null || from == null || to == null) continue;
        if (day < 0 || day > 6) continue; // 壞資料不要打翻整份
        byDay[day].add(TimeRange(from, to));
      }
      preferredTimes = PreferredTimes(byDay);
    }
    if (pick<List>('experienceRatings') case final rows?) {
      experienceRatings.clear();
      for (final r in rows) {
        if (r is! Map) continue;
        final target = _enumByName(RatingTarget.values, r['target']);
        final at = _date(r['at']);
        if (target == null || at == null) continue;
        experienceRatings.add(ExperienceRating(
          target: target,
          targetId: r['targetId'] as String? ?? '',
          rater: r['rater'] as String? ?? '',
          raterUid: r['raterUid'] as String?,
          stars: (r['stars'] as num?)?.toInt() ?? 0,
          feedback: r['feedback'] as String?,
          at: at,
        ));
      }
    }
    socialUnlocked = boolOf('socialUnlocked', socialUnlocked);
    returnTaskAssigned = boolOf('returnTaskAssigned', returnTaskAssigned);
    returnTaskAssignedAt = _date(j['returnTaskAssignedAt']);
    returnTaskViewedAt = _date(j['returnTaskViewedAt']);
    returnTaskDone = boolOf('returnTaskDone', returnTaskDone);
    returnTaskDim = _enumByName(Dim.values, j['returnTaskDim']);
    returnRewardClaimed = boolOf('returnRewardClaimed', returnRewardClaimed);
    if (pick<List>('returnTaskLog') case final rows?) {
      returnTaskLog
        ..clear()
        ..addAll([
          for (final r in rows.whereType<Map>())
            if (_date(r['at']) case final at?)
              (assignedAt: at, overdue: r['overdue'] == true),
        ]);
    }

    membership =
        _enumByName(MembershipState.values, j['membership']) ?? membership;
    membershipExpiry = _date(j['membershipExpiry']);
    membershipLockedPlanIds = strs('membershipLockedPlanIds');
    if (pick<List>('purchasedPlanIds') != null) {
      purchasedPlanIds
        ..clear()
        ..addAll(strs('purchasedPlanIds'));
    }
    final planId = pick<String>('currentPlanId');
    currentPlan = planId == null
        ? null
        : platformPlans.where((p) => p.id == planId).firstOrNull;

    lastRenamedAt = _date(pick<String>('lastRenamedAt'));
    if (pick<List>('formerNames') != null) {
      formerNames
        ..clear()
        ..addAll(strs('formerNames'));
    }

    // 關注名單。新欄位是鍵，舊欄位（階段三之前）是暱稱，翻一次。
    final names = pick<Map>('followNames');
    if (names != null) {
      _followNames
        ..clear()
        ..addAll({
          for (final e in names.entries)
            if (e.value is String) '${e.key}': e.value as String,
        });
    }
    if (pick<List>('followingKeys') != null) {
      following
        ..clear()
        ..addAll(strs('followingKeys'));
    } else if (pick<List>('following') != null) {
      following
        ..clear()
        ..addAll(strs('following').map(followKeyFromLegacyName));
    }
    if (pick<List>('followerKeys') != null) {
      followers = strs('followerKeys');
    } else if (pick<List>('followers') != null) {
      followers = strs('followers').map(followKeyFromLegacyName).toList();
    }
    peakFollowerCount = intOf('peakFollowerCount', peakFollowerCount);

    final hist = pick<List>('history');
    if (hist != null) {
      history = [
        for (final h in hist)
          if (h is Map && _date(h['date']) != null)
            HistoryEntry(
              _date(h['date'])!,
              '${h['planName']}',
              h['volume'] is num ? (h['volume'] as num).toDouble() : 0,
              h['minutes'] is num ? (h['minutes'] as num).round() : 0,
              h['calories'] is num ? (h['calories'] as num).round() : 0,
              [
                for (final e in (h['exercises'] as List? ?? const []))
                  if (e is Map)
                    HistoryExercise(
                      '${e['name']}',
                      [
                        for (final t in (e['sets'] as List? ?? const []))
                          if (t is List && t.length == 2)
                            ((t[0] as num).toDouble(), (t[1] as num).round()),
                      ],
                      id: e['id'] is String ? e['id'] as String : null,
                      isTimed: e['isTimed'] == true,
                    ),
              ],
              // 舊存檔沒有這個鍵 → 空值 → 畫面顯示「—」。
              completion: (h['completion'] as num?)?.toDouble(),
            ),
      ];
      // **訓練歷史一律新的在前。**
      //
      // 這是 `AppState.history` 的不變條件（`finishWorkout` 是
      // `insert(0, …)`），而在此之前它只是「存檔裡剛好是那個順序」。
      // 2026-09-26 Firestore 那一側的文件順序真的壞過一次，讀回來變成
      // 舊的在前 —— 而首頁、訓練歷史頁、課表卡的「上次訓練」全都
      // 假設了這個順序。
      //
      // 各個 Store 各自保證一次，就是同一個決定寫在三個地方。
      // 在這裡排一次，任何來源進來都成立。
      history.sort((a, b) => b.date.compareTo(a.date));
    }

    final mails = pick<List>('mailbox');
    if (mails != null) {
      mailbox = [
        for (final m in mails)
          if (m is Map && _date(m['at']) != null)
            MailReward(
              source: '${m['source']}',
              exp: (m['exp'] as num?)?.round() ?? 0,
              coins: (m['coins'] as num?)?.round() ?? 0,
              makeupTickets: (m['makeupTickets'] as num?)?.round() ?? 0,
              aiCredits: (m['aiCredits'] as num?)?.round() ?? 0,
              at: _date(m['at'])!,
              claimed: m['claimed'] == true,
            ),
      ];
      // 不變條件：信箱裡不該有數額為 0 的獎勵。
      // 有的話代表讀取端與寫入端的欄位對不上（v1→v2 就是這樣把獎勵清空的），
      // 留著只會讓使用者領到「無」。丟掉比留著一筆領了沒東西的假獎勵好。
      mailbox.removeWhere((m) => m.isEmpty);
    }

    if (pick<List>('notifications') case final rows?) {
      notifications
        ..clear()
        ..addAll([
          for (final n in rows.whereType<Map>())
            if (_date(n['at']) case final at?)
              AppNotification(
                id: '${n['id']}',
                sourceEvent: '${n['sourceEvent']}',
                title: '${n['title']}',
                body: '${n['body']}',
                at: at,
                kind: NotifyKind.values.firstWhere(
                  (k) => k.name == n['kind'],
                  orElse: () => NotifyKind.inApp,
                ),
                priority: NotifyPriority.values
                    .where((x) => x.name == n['priority'])
                    .firstOrNull,
                read: n['read'] == true,
              ),
        ]);
    }

    if (pick<List>('checkInRecords') case final rows?) {
      checkInRecords
        ..clear()
        ..addEntries([
          for (final r in rows.whereType<Map>())
            if (_date(r['date']) case final d?)
              MapEntry(
                DateTime(d.year, d.month, d.day),
                _enumByName(CheckInMethod.values, r['method']) ??
                    CheckInMethod.real,
              ),
        ]);
    }

    final mine = pick<List>('myExercises');
    if (mine != null) {
      // 平台動作庫來自伺服器，只把自建動作放回去。
      myExercises = [
        for (final e in mine)
          if (e is Map && e['id'] is String)
            Exercise(
              id: e['id'] as String,
              name: '${e['name']}',
              dim: _enumByName(Dim.values, e['dim']),
              relativeIntensity: 1.0,
              isBodyweight: e['isBodyweight'] == true,
              type: _enumByName(ExerciseType.values, e['type']) ??
                  ExerciseType.strength,
              equipment: '${e['equipment']}',
              isCustom: true,
              defaultRestSeconds: e['defaultRestSeconds'] is num
                  ? (e['defaultRestSeconds'] as num).round()
                  : null,
            ),
      ];
    }

    final savedPlans = pick<List>('customPlans');
    if (savedPlans != null) {
      // 只換掉「我的」，其餘（別人送審的）不是這份存檔的東西，不動。
      customPlans = [
        for (final e in savedPlans)
          if (e is Map<String, dynamic>) ?_customPlanFromJson(e),
        ...customPlans.where((p) => !p.isMine),
      ];
      // 目前選的課表若是自訂訓練，上面照 platformPlans 找是找不到的。
      final cur = pick<String>('currentPlanId');
      if (currentPlan == null && cur != null) {
        currentPlan = customPlans
            .where((p) => p.id == cur)
            .map((p) => p.toWorkoutPlan())
            .firstOrNull;
      }
    }

    isInstructor = boolOf('isInstructor', isInstructor);
    instructorDutyVersion =
        pick<String>('instructorDutyVersion') ?? instructorDutyVersion;
    mentorDisclaimerVersion =
        pick<String>('mentorDisclaimerVersion') ?? mentorDisclaimerVersion;
    instructorReputation = intOf('instructorReputation', instructorReputation);
    peakReputation = intOf('peakReputation', peakReputation);
    _mentorWeek = _date(j['mentorWeek']) ?? _mentorWeek;
    ratedThisWeek = boolOf('ratedThisWeek', ratedThisWeek);
    taskRatingsThisWeek = intOf('taskRatingsThisWeek', taskRatingsThisWeek);
    mentorRewardsThisWeek =
        intOf('mentorRewardsThisWeek', mentorRewardsThisWeek);
    myViolations = intOf('myViolations', myViolations);
    if (pick<List>('instructorSpecialties') != null) {
      instructorSpecialties
        ..clear()
        ..addAll(strs('instructorSpecialties'));
    }
    if (pick<List>('creditedTaskRatings') != null) {
      creditedTaskRatings
        ..clear()
        ..addAll(strs('creditedTaskRatings'));
    }
    if (pick<List>('creditedWeeklyRatings') != null) {
      creditedWeeklyRatings
        ..clear()
        ..addAll(strs('creditedWeeklyRatings'));
    }

    if (pick<List>('ownedEquipment') != null) {
      ownedEquipment
        ..clear()
        ..addAll(strs('ownedEquipment'));
    }
    aiAutoOptimize = boolOf('aiAutoOptimize', aiAutoOptimize);
    abilityPublic = boolOf('abilityPublic', abilityPublic);
    overallGradePublic = boolOf('overallGradePublic', overallGradePublic);
    email = j['email'] as String?;
    metricUnits = boolOf('metricUnits', metricUnits);
    deletionRequestedAt = _date(j['deletionRequestedAt']);
    deletionCoolingDays =
        j['deletionCoolingDays'] is num ? intOf('deletionCoolingDays', 30) : null;

    demoClockOffset = Duration(milliseconds: intOf('demoClockOffsetMs', 0));
    repairLoadedState();

    // **最後才補跑解鎖判定。**
    //
    // 「依真實進度補上存檔沒記到的」要成立，前提是**真實進度已經全部
    // 還原完**。擺在中間就會拿建構子的示範資料去解鎖（見上方
    // `achievements` 那一段）。`repairLoadedState()` 之後也是刻意的 ——
    // 它會補回累積訓練天數，而那是累積訓練成就的依據。
    syncAchievementsAfterLoad();
    return true;
  }

  /// 載入後的針對性修復。
  ///
  /// **不是升版本**：升版本會把整份存檔丟掉，而這裡要救的正是那份存檔。
  /// 只修「兩個欄位彼此矛盾、而正確答案唯一」的情形 ——
  /// 需要猜的一律不動。
  void repairLoadedState() {
    // 已訓練過的維度，訓練歷史裡要找得到證據。
    //
    // [AppState.resetToNewAccount] 曾漏清 [trainedDims] 與 [pending]，
    // 於是那時開的新帳號會宣稱六維全都練過。後果是每一維真正的第一場
    // 都走成「非首場」：首場可直接對齊實測值，非首場只能爬到下一個
    // 節點的上緣 —— 實測 296 分的第一場只給到 69。
    //
    // 只**移除**沒有證據的，不新增 —— 歷史不設上限、每場結算都寫一筆，
    // 所以「歷史裡沒有」就是真的沒練過。自建動作不計，與結算時同一條規則。
    final evidenced = <Dim>{};
    for (final h in history) {
      for (final e in h.exercises) {
        final ex = _exerciseOf(e);
        if (ex.isCustom || ex.dim == null) continue;
        evidenced.add(ex.dim!);
      }
    }
    final ghosts = trainedDims.difference(evidenced);
    if (ghosts.isNotEmpty) {
      trainedDims.removeAll(ghosts);
      // 待兌現分數同樣是那一維訓練史的產物，一起清掉。
      for (final d in ghosts) {
        pending[d] = 0;
      }
    }

    // --- 訓練天數：歷史裡有幾天就至少是幾天 ---
    //
    // 2026-09-28 使用者實測：累積訓練次數 6、**累積訓練天數 0**。
    // 根因修好了（`finishWorkout` 原本問 `lastTrainedDate != today`，
    // 而新帳號的那個值就是今天 —— 見 1C），但**修不了已經漏掉的那幾天**：
    // 那一天的訓練已經寫進歷史，計數器卻永遠少了 1。
    //
    // 所以在這裡補。與上面清 [trainedDims] 同一個原則：
    // **歷史是證據**。差別只在方向 —— 那邊是移除沒有證據的，
    // 這邊是補上有證據卻沒算到的。
    //
    // **只增不減**，維持「單調遞增」的不變條件
    //（`02_Aggregate定義.md` §47）。算多了不在這裡處理，
    // 那是 `reconcileWorkoutCount()` 的事。
    final days = {for (final h in history) businessDate(h.date)};
    if (days.length > totalWorkoutDays) totalWorkoutDays = days.length;

    // --- 連續訓練天數：只補「今天」這一格 ---
    //
    // **不整段重算。** 連續天數的規則只能有一份，而它在 `finishWorkout`
    // （遞增）與 `runStreakCheck`（超過 36 小時歸零）兩處 ——
    // `finishWorkout` 自己的註解就寫著「與 `runStreakCheck` 的中斷判定
    // 共用同一條規則，兩邊各寫一份就會對不起來」。在載入時再推算一次
    // 就是第三份。
    //
    // 但**今天練過卻顯示 0 天**是實話與畫面不符 —— 那是 1C 那個缺陷的
    // 殘留：那一天的遞增分支沒跑到，而今天不會再跑第二次。
    // 所以只補這一格：歷史裡今天有訓練，連續天數至少是 1。
    // 這不是重算，是把 `finishWorkout` 當時該寫進去的下限補上。
    //
    // 〔更正〕第一版我寫的理由是「連續天數可以被合法地調低（永久停權
    // 經申訴撤銷時要重設）」—— **那是錯的**：`rebaseClocks()` 只移動
    // 計時基準，完全不動 `trainingStreakDays`。留著錯的理由比沒有理由糟。
    if (trainingStreakDays == 0 &&
        history.any((h) => businessDate(h.date) == businessDate(now))) {
      trainingStreakDays = 1;
    }
  }
}

/// 依名稱還原列舉。找不到時回傳空值 —— 存檔裡的舊值域不該讓整份讀取失敗。
T? _enumByName<T extends Enum>(List<T> values, Object? name) {
  if (name is! String) return null;
  for (final v in values) {
    if (v.name == name) return v;
  }
  return null;
}
