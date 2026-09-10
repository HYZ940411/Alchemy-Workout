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
