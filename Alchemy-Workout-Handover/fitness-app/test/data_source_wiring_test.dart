// `lib/data/` 的每一支介面方法都要有人呼叫。
//
// ## 為什麼需要這道檢查
//
// 2026-09-24 掃描時查出**六支方法寫好了卻沒有人呼叫**：
// `PostSource.updatePostText`、`markPostDeleted`（貼文編輯與刪除只改記憶體，
// 重新整理就變回去）、`MentorSource.bond`、`recover`、`ask`、`answer`
// （師徒關係與問答完全沒上雲，兩邊重整就消失）。
//
// 介面備妥、Firestore 實作完整、連 `post_data_test` 都測過那兩支 ——
// **就是狀態層沒接線**。這種漏接不會編譯錯、不會跑出例外、測試也不會紅，
// 只會安靜地讓資料留在本機，等使用者回報「我明明改了啊」。
//
// ## 這道檢查抓得到什麼、抓不到什麼
//
// 抓得到：**方法從頭到尾沒有人呼叫**。
//
// **抓不到「有呼叫但呼叫錯了」** —— 同一批 bug 裡的階級凍結
// （呼叫了，但顯示的是快照不是現值）與動態牆選單沒分支
// （呼叫了，但沒有先判斷是不是自己的貼文），這道檢查一個都擋不住。
// 別把它當護身符。
//
// **偽陰性（漏抓）**：比對的是方法名字串，而名字會撞。撞了兩次，
// 兩次都是真的漏抓：
//
//   · **兩個介面同名**：`MentorSource.dropRequest` 一個呼叫端都沒有
//     （接受與拒絕請求都沒清掉雲端那筆），但 `TeamSource` 也有一支
//     同名方法而那支有人呼叫。2026-09-24 追查「團隊重整後不見了」才發現。
//   · **方法名撞到欄位名**：`MentorSource.tasks()`／`questions()` 同樣
//     沒有呼叫端（教官讀不回學徒的提問與評分，星等因此永遠是 0），
//     而畫面上有個同名的 `s.questions` 欄位。做 `[BE-15]` 時才發現。
//
// 所以現在**兩種撞名都必須具名承認**（寫進 `_ambiguous`）——
// 用途不是讓測試變綠，是讓「這幾支沒被真正檢查」這件事看得見。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 允許暫時沒有呼叫端的方法。
///
/// **鍵是 `介面.方法`，值是理由 —— 沒有理由不准加。**
///
/// 加進來之前先問自己：這真的是「功能還沒做」，還是**漏接**？
/// 那六支被抓到的當初看起來全都像前者。白名單最常見的失敗方式，
/// 就是變成「測試紅了就加一行」的地方。
const _allowed = <String, String>{
  // 以下四支是**已知漏接，不是「還沒做」** —— 見 PROGRESS.md 第 5 節 0d。
  //
  // 使用者 2026-09-24 選擇先修貼文那一組，並明示這一項不可遺忘。
  // 列在這裡是為了讓這道檢查能保護「之後新增的」介面方法；
  // **這四行要在師徒接線完成時一起刪掉**，刪不掉就代表那項還沒做完。
  // `bond`／`recover`／`ask` 已於 2026-09-24 接上。
  //
  // **`answer` 不是漏接，是教官側的本機模型還沒做。**
  // `answerQuestion()` 整個函式只有一個計數器 —— 連回答的文字都沒存，
  // 也不知道是回哪一則。`mentorTasks`／`questions` 是一份共用清單，
  // 沒記錄「這則是哪位學徒的」，而雲端的問答掛在特定關係下。
  // 見 PROGRESS.md 的 `[BE-15]`。
  'MentorSource.answer': '教官側本機模型缺學徒身分，見 [BE-15]',
};

/// 與別的介面撞名、因此這道檢查驗不了的方法。
///
/// **每一筆都要寫「怎麼人工確認的」。** 這張表的用途不是讓測試變綠，
/// 是讓「這幾支沒被真正檢查」這件事**看得見**。
const _ambiguous = <String, String>{
  'MentorSource.dropRequest':
      '2026-09-24 接上：`_dropCloudRequest()` 的師徒分支',
  'TeamSource.dropRequest': '拒絕申請、取消邀請、撤回申請、`_dropCloudRequest()`',
  'MentorSource.sendRequest': '`applyMentor()` 送出拜師申請',
  'TeamSource.sendRequest': '申請加入公開團隊、隊長邀請成員',
  'PostSource.publish': '`publishPost()` 與 `shareWorkout()`',
  'PublicProfileSource.publish': '`publishMyProfile()` 與 `AuthGate._syncProfile`',
  // 這兩支撞的是**欄位名**（畫面上的 `s.questions`），不是別的介面。
  'MentorSource.questions': '2026-09-24 接上：`loadMentorSideOf()`',
  'MentorSource.tasks': '2026-09-24 接上：`loadMentorSideOf()`',
  'MentorSource.bond': '`_pushBond()`，接受拜師／收徒時建立關係',
  'TeamSource.myTeam': '`refreshInbound()` 與 `AuthGate._syncProfile` 的「我的團隊」',

  // ── 2026-09-25 把正則的巢狀泛型漏洞修掉之後，這 14 支才第一次
  //    進入檢查範圍。全部逐一人工確認過（下面各自註明行號來源）。
  //    在那之前它們**從頭到尾沒有被檢查過**。
  'PlatformDataSource.load': '`AuthGate._loadPlatformData()` → `applyPlatformData`',
  'Store.load': '`AppState.hydrate()`',
  'TeamSource.requestsFor': '`refreshInbound()` 與 `AuthGate` 的「團隊請求」',
  'MentorSource.requestsFor': '`refreshInbound()` 與 `AuthGate` 的「師徒申請」',
  'FollowSource.following': '`AuthGate` 的「關注」那一塊',
  'FollowSource.followers': '同上，緊接著那一行',
  'ChatSource.conversations': '`refreshInbound()` 與 `AuthGate` 的「私訊」',
  'PublicProfileSource.others': '`AuthGate._syncProfile` 撈最近活躍的人',
  // 檢舉與申訴各有一組同名的三支。兩組都在 2026-09-25 接上。
  'ReportSource.file': '`_pushReport()`，使用者按下檢舉',
  'AppealSource.file': '`fileAppeal()`',
  'ReportSource.queue': '`loadReportQueue()`',
  'AppealSource.queue': '`loadAppealQueue()`',
  'ReportSource.judge': '`_pushVerdict()`，檢舉裁決回寫',
  'AppealSource.judge': '`_pushAppealVerdict()`，申訴裁決回寫',
};

/// 從 `abstract class X { ... }` 裡抓出方法名。
List<(String cls, String method)> _interfaceMethods(String src) {
  final out = <(String, String)>[];
  final classes = RegExp(r'abstract class (\w+)\s*\{(.*?)\n\}', dotAll: true);
  // 回傳型別可能是 Future<...>、Stream<...>、void、bool、int、String。
  //
  // **`[^>]*` 是錯的，而且錯得很安靜。** 它在第一個 `>` 就停住，
  // 所以 `Future<List<CloudReport>>` 這種巢狀泛型**一支都比對不到** ——
  // 而那正是資料層所有「讀」的方法的長相。
  //
  // 2026-09-25 修掉時，這道檢查從 51 支變成 66 支：漏掉的 15 支是
  // `recent`／`bonds`／`conversations`／`following`／`followers`／`tasks`／
  // `questions`／`requestsFor`／`openTeams`／`others`／`byUids`／`load`／
  // `queue`×2。**整個讀取側。**
  //
  // 而這道檢查存在的理由，正是 2026-09-24 那批「介面寫好了沒人呼叫」的
  // bug —— 其中 `MentorSource.tasks()`／`questions()` 零呼叫端害教官讀不回
  // 學徒的提問與評分。它們當時被人工發現、寫進了 `_ambiguous`，
  // 而這道檢查**從頭到尾沒有真的檢查過它們**。
  //
  // 這就是本專案守則第 2 條的意思：驗證工具本身要先被驗證。
  // 下面那條 `greaterThan` 的門檻也一併提高 —— 它本來是 20，
  // 51 支的時候通過得太輕鬆，看不出漏了 15 支。
  final sig = RegExp(
    r'^  (?:(?:Future|Stream)<.*?>|void|bool|int|String)\??\s+(\w+)\s*\(',
    multiLine: true,
  );
  for (final m in classes.allMatches(src)) {
    for (final s in sig.allMatches(m.group(2)!)) {
      out.add((m.group(1)!, s.group(1)!));
    }
  }
  return out;
}

void main() {
  test('lib/data/ 的每一支介面方法都有呼叫端', () {
    final methods = <(String, String)>[];
    for (final f in Directory('lib/data').listSync().whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      methods.addAll(_interfaceMethods(f.readAsStringSync()));
    }

    // 抓不到任何方法＝正則失效了，那比漏接更糟 —— 它會讓這道檢查
    // 永遠是綠的，而沒有人會發現。
    // 2026-09-25：實際 66 支。門檻設在 60 —— 刻意貼近，
    // 少了幾支就會紅。設 20 的時候漏掉 15 支也照樣是綠的。
    expect(methods.length, greaterThan(60),
        reason: '介面的寫法變了，這條測試的正則要跟著更新');

    // 呼叫端：狀態層與畫面層。`lib/data/` 自己不算 —— 實作呼叫自己的
    // 介面（或彼此呼叫）不代表這個功能真的接上了。
    final callers = StringBuffer();
    for (final dir in ['lib/state', 'lib/screens']) {
      for (final f in Directory(dir).listSync(recursive: true).whereType<File>()) {
        if (f.path.endsWith('.dart')) callers.write(f.readAsStringSync());
      }
    }
    final code = callers.toString();

    // **撞名要具名承認，不能靜默放行。**
    //
    // 比對的是方法名，所以兩個介面有同名方法時，只要其中一支有人呼叫，
    // 另一支沒接線的就會被誤判為已接。`MentorSource.dropRequest` 就是
    // 這樣漏掉的。發現新的撞名時，這條測試會失敗並要求你把它寫進
    // `_ambiguous` —— 附上「這一支是怎麼人工確認過的」。
    final byName = <String, List<String>>{};
    for (final (cls, method) in methods) {
      (byName[method] ??= []).add(cls);
    }
    // 呼叫端那一側的欄位名。`.questions` 既是 `MentorSource` 的方法，
    // 也是畫面讀的 `s.questions` —— 那次漏抓就是這樣來的。
    final fields = RegExp(r'\b(\w+)\s*=\s*')
        .allMatches(code)
        .map((m) => m.group(1)!)
        .toSet();
    final collisions = {
      for (final e in byName.entries)
        if (e.value.length > 1 || fields.contains(e.key))
          for (final cls in e.value)
            // 已經列為「還沒接線」的不必再承認一次撞名 —— 那是另一回事。
            if (!_allowed.containsKey('$cls.${e.key}')) '$cls.${e.key}',
    };
    expect(collisions.difference(_ambiguous.keys.toSet()), isEmpty,
        reason: '這幾支方法與別的介面撞名，這道檢查對它們無效。\n'
            '人工確認它們真的有呼叫端之後，寫進 _ambiguous 並註明怎麼確認的。');

    final dead = <String>[];
    for (final (cls, method) in methods) {
      if (_allowed.containsKey('$cls.$method')) continue;
      if (!RegExp(r'\.' + method + r'\s*\(').hasMatch(code)) {
        dead.add('$cls.$method');
      }
    }

    expect(dead, isEmpty,
        reason: '這幾支介面方法沒有任何呼叫端 —— 功能寫好了、線沒接。\n'
            '不會編譯錯也不會跑出錯，只會讓資料安靜地留在本機。\n'
            '確認過真的是「還沒做」再加進 _allowed，**並寫上理由**。');
  });
}
