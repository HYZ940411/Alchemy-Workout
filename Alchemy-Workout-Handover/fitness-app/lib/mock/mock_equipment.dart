/// 器材設定 Aggregate —— 器材品項與其「哪裡有」，由管理員於後台維護。
/// 本表是**動作可練場所的推導依據**：動作只填需要什麼器材，能在哪練由系統推導。
const kEquipmentVenues = <String, Set<String>>{
  '徒手': {'健身房', '居家', '徒手'},
  '彈力繩': {'健身房', '居家'},
  '啞鈴': {'健身房', '居家'},
  '壺鈴': {'健身房', '居家'},
  '槓鈴': {'健身房'},
  '機械式器材': {'健身房'},
  '繩索（滑輪）': {'健身房'},
  '有氧器材': {'健身房'},
};

/// 8 個品項的值域。動作的「所需器材明細」與使用者的「持有器材明細」共用同一組。
const kEquipmentItems = <String>[
  '徒手', '彈力繩', '啞鈴', '壺鈴', '槓鈴', '機械式器材', '繩索（滑輪）', '有氧器材',
];

/// 需要多項器材時，可練場所為**同時具備全部器材**的場所。
/// 所需器材為空值者不參與器材比對 —— 於動作庫依器材篩選時不出現於任何器材分類。
Set<String> venuesFor(Set<String> equipment) {
  if (equipment.isEmpty) return const {};
  return equipment
      .map((e) => kEquipmentVenues[e] ?? const <String>{})
      .reduce((a, b) => a.intersection(b));
}

/// 從動作的器材字串解析出「所需器材明細」。
/// 顯示字串的形式為「槓鈴 · 繩索（滑輪） ＋ 平板椅」——
/// 「＋」之後為配件，不屬模型值域，不參與器材比對。
Set<String> requiredEquipment(String display) {
  final head = display.split(' ＋ ').first.trim();
  if (head.isEmpty || head == '不限') return const {};
  return head.split(' · ').map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
}

/// 這個動作是否通得過「名稱關鍵字 ＋ 器材」兩道篩選。
///
/// **動作庫與「加入動作至本次訓練」共用這一份。**
/// 原本它是 `exercise_library_screen.dart` 裡的私有方法，於是
/// 訓練中的動作選擇抽屜沒有篩選可用 —— 使用者回報想要。
/// 抽出來而不是在抽屜裡再寫一次：這個專案的 bug 有一整排正是
/// 「同一個決定寫在兩個地方，只有一處做對」。
///
/// [owned] 為空集合代表**不篩器材**（未設定持有器材明細者）。
///
/// 動作要做得起來，其**所需器材必須全部**在 [owned] 內 ——
/// 與〈可練場所的推導〉同一判準：需要多項器材時，要同時具備全部。
/// 所需器材為空值者不參與器材比對，於器材篩選時不出現於任何分類。
bool exerciseMatchesFilter(
  ({String name, String equipment}) e, {
  required Set<String> owned,
  required String query,
}) {
  if (query.isNotEmpty && !e.name.contains(query)) return false;
  if (owned.isEmpty) return true;
  final need = requiredEquipment(e.equipment);
  if (need.isEmpty) return false;
  return need.every(owned.contains);
}
