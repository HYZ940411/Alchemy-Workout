import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_app/mock/mock_equipment.dart';
import 'package:fitness_app/screens/train/exercise_picker.dart';
import 'package:fitness_app/state/app_state.dart';

/// 使用者要求：訓練中「加入動作至本次訓練」也要有篩選，像動作庫那樣。
///
/// **關鍵不是「有篩選」，是「與動作庫篩出來的結果一致」。**
/// 判準（`exerciseMatchesFilter`）與器材篩選條（`EquipmentFilterBar`）
/// 原本都是動作庫頁的私有東西，已抽出共用 —— 各寫一份遲早有一邊
/// 漏掉新規則，而這個專案的 bug 有一整排正是那個形狀。
void main() {
  group('篩選判準（動作庫與加入動作共用同一份）', () {
    ({String name, String equipment}) ex(String name, String equipment) =>
        (name: name, equipment: equipment);

    test('空集合代表不篩器材', () {
      expect(
        exerciseMatchesFilter(ex('臥推', '槓鈴'), owned: const {}, query: ''),
        isTrue,
      );
    });

    test('所需器材必須全部具備 —— 不是任一', () {
      // 與〈可練場所的推導〉同一判準。
      final need = requiredEquipment('槓鈴');
      expect(need, isNotEmpty, reason: '前提：這個字串解得出器材');
      expect(
        exerciseMatchesFilter(ex('臥推', '槓鈴'), owned: {'啞鈴'}, query: ''),
        isFalse,
      );
      expect(
        exerciseMatchesFilter(ex('臥推', '槓鈴'), owned: need, query: ''),
        isTrue,
      );
    });

    test('所需器材為空值者，篩器材時不出現於任何分類', () {
      expect(
        exerciseMatchesFilter(ex('某動作', ''), owned: {'啞鈴'}, query: ''),
        isFalse,
      );
      // 不篩的時候照樣出現。
      expect(
        exerciseMatchesFilter(ex('某動作', ''), owned: const {}, query: ''),
        isTrue,
      );
    });

    test('名稱關鍵字與器材是「且」的關係', () {
      final need = requiredEquipment('槓鈴');
      expect(
        exerciseMatchesFilter(ex('臥推', '槓鈴'), owned: need, query: '深蹲'),
        isFalse,
      );
      expect(
        exerciseMatchesFilter(ex('臥推', '槓鈴'), owned: need, query: '臥'),
        isTrue,
      );
    });
  });

  group('加入動作抽屜', () {
    Future<void> open(WidgetTester t, AppState s) async {
      await t.pumpWidget(AppScope(
        state: s,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () =>
                    pickExercise(context, myExercises: const []),
                child: const Text('開'),
              ),
            ),
          ),
        ),
      ));
      await t.tap(find.text('開'));
      await t.pumpAndSettle();
    }

    testWidgets('有搜尋框與器材篩選條', (t) async {
      await open(t, AppState());
      expect(find.text('搜尋動作名稱'), findsOneWidget);
      expect(find.textContaining('器材篩選'), findsOneWidget);
    });

    testWidgets('搜尋會縮小清單', (t) async {
      final s = AppState();
      await open(t, s);
      // 先確認有一個叫得出名字的動作在畫面上。
      final some = s.platformExercises.first.name;
      expect(find.text(some), findsWidgets);

      await t.enterText(find.byType(TextField).first, '不可能有這個動作的名字');
      await t.pumpAndSettle();
      expect(find.text(some), findsNothing);
      expect(find.text('沒有符合的動作'), findsOneWidget,
          reason: '篩到空要說得出來 —— 一片空白看起來像動作庫壞了');
    });

    testWidgets('「清除篩選」把搜尋與器材都清掉', (t) async {
      final s = AppState();
      await open(t, s);
      await t.enterText(find.byType(TextField).first, '不可能有這個動作的名字');
      await t.pumpAndSettle();
      // 空狀態的行動按鈕在抽屜裡會落到可見範圍之外（測試視窗 600 高，
      // 按鈕在 628）—— 先捲到它。使用者在真機上同樣要捲一下，
      // 而篩選條標題上本來就有一顆「清除」，這顆是順手的那個。
      await t.ensureVisible(find.text('清除篩選'));
      await t.pumpAndSettle();
      await t.tap(find.text('清除篩選'));
      await t.pumpAndSettle();
      expect(find.text('沒有符合的動作'), findsNothing);
    });

    // **預設不篩，與動作庫刻意不同。**
    //
    // 第一版我照動作庫的做法預設帶入可用器材，結果自訂課表編輯器裡的
    // 「划船機」直接消失，既有的 smoke 測試當場紅掉 —— 而編輯課表的人
    // 可能正在為別的場地寫課表。「有篩選可以用」不等於「預設就篩掉一半」。
    testWidgets('預設不篩器材 —— 要器械的動作一開始就看得到', (t) async {
      await open(t, AppState());
      expect(find.textContaining('器材篩選：全部動作'), findsOneWidget);
      // 划船機需要划船機，使用者的持有器材明細裡沒有它。
      await t.ensureVisible(find.text('划船機'));
      expect(find.text('划船機'), findsWidgets);
    });

    testWidgets('「只看我的器材做得到的」一鍵帶入可用器材', (t) async {
      final s = AppState();
      await open(t, s);
      await t.ensureVisible(find.text('只看我的器材做得到的'));
      await t.tap(find.text('只看我的器材做得到的'));
      await t.pumpAndSettle();
      expect(find.textContaining('器材篩選：${s.equipmentForFiltering.length} 項'),
          findsOneWidget);
    });

    testWidgets('本次訓練已解鎖器材時，那顆按鈕帶入的是全部品項', (t) async {
      // 解鎖了卻在加入動作時還被自己的設定擋住，等於沒解鎖。
      final s = AppState()..sessionEquipmentUnlocked = true;
      await open(t, s);
      await t.ensureVisible(find.text('只看我的器材做得到的'));
      await t.tap(find.text('只看我的器材做得到的'));
      await t.pumpAndSettle();
      expect(find.textContaining('器材篩選：${kEquipmentItems.length} 項'),
          findsOneWidget);
    });
  });
}
