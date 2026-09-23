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
// **偽陰性（漏抓）**：比對的是方法名字串，而名字會撞 ——
// `publish` 同時屬於 `PostSource` 與 `PublicProfileSource`，
// `remove`、`clear`、`load`、`save` 也都很常見。撞名時，只要有**任何一個**
// 同名方法被呼叫，另一個沒接線的就會被誤判為已接。
// 這是這道檢查最主要的限制，要誠實看待。

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

/// 從 `abstract class X { ... }` 裡抓出方法名。
List<(String cls, String method)> _interfaceMethods(String src) {
  final out = <(String, String)>[];
  final classes = RegExp(r'abstract class (\w+)\s*\{(.*?)\n\}', dotAll: true);
  // 回傳型別可能是 Future<...>、void、bool、int、String、Stream<...>
  final sig = RegExp(
    r'^  (?:Future<[^>]*>|Stream<[^>]*>|void|bool|int|String)\??\s+(\w+)\s*\(',
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
    expect(methods.length, greaterThan(20),
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
