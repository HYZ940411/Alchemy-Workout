// 開發者模式的測試輔助。
//
// QA-02n／QA-02o 之後，「流程示範」那一整區（註冊流程、AI 自動優化、
// 管理員後台、骨架屏與錯誤頁、模擬對方）與退步頁的模擬時鐘都收進了
// 開發者模式，一般使用者看不到。要走那些畫面的測試因此得先打開它。
//
// **這裡刻意直接呼叫 AppState 的方法，而不是每個測試都自己長按頁首。**
// 那些測試驗的是後台與示範畫面本身，不是隱藏入口長什麼樣；
// 把手勢複製五份，入口一改就會有五個不相干的測試一起紅。
// 長按手勢本身由 developer_mode_test.dart 單獨釘住，只釘一次。

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/screens/me/more_screen.dart';
import 'package:fitness_app/state/app_state.dart';

/// 打開開發者模式。呼叫前畫面上要有 [MoreScreen]。
///
/// 已經是開著的就什麼都不做 —— toggle 語意的開關若無條件呼叫，
/// 第二次呼叫會把它關回去。
Future<void> enableDeveloperMode(WidgetTester t) async {
  final s = AppScope.of(t.element(find.byType(MoreScreen)));
  if (!s.developerMode) s.toggleDeveloperMode();
  await t.pumpAndSettle();
}
