// 公開檔案（[BE-11] 批次 1）。
//
// 這是整個模型裡第一個「別人讀得到我的資料」的集合，所以測試的重點
// **不是存讀有沒有成功，而是不該公開的東西有沒有真的沒被公開**。
// 存讀寫錯了使用者會抱怨；可見度寫錯了使用者不會知道，直到資料已經外流。

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/public_profile.dart';
import 'package:fitness_app/data/public_profile_firestore.dart';
import 'package:fitness_app/domain/ability.dart';

const _points = {
  Dim.chest: 486,
  Dim.back: 452,
  Dim.legs: 318,
  Dim.shoulders: 274,
  Dim.arms: 305,
  Dim.core: 190,
};

PublicProfile build({
  bool abilityPublic = true,
  bool overallGradePublic = true,
  bool isInstructor = false,
  int? reputation,
  List<String> specialties = const [],
}) =>
    PublicProfile.of(
      uid: 'u1',
      displayName: '阿昶',
      rank: 45,
      points: _points,
      abilityPublic: abilityPublic,
      overallGradePublic: overallGradePublic,
      isInstructor: isInstructor,
      reputation: reputation,
      specialties: specialties,
    );

void main() {
  group('可見度：兩個開關各自獨立', () {
    test('兩個都開 —— 六維與綜合等級都公開', () {
      final p = build();
      expect(p.ability, isNotNull);
      expect(p.grade, isNotNull);
    });

    test('只關六維 —— 綜合等級仍公開', () {
      final p = build(abilityPublic: false);
      expect(p.ability, isNull);
      expect(p.grade, isNotNull, reason: '兩個開關是獨立的，關一個不該連帶關掉另一個');
    });

    test('只關綜合等級 —— 六維仍公開', () {
      final p = build(overallGradePublic: false);
      expect(p.grade, isNull);
      expect(p.ability, isNotNull);
    });

    test('兩個都關 —— 兩者都不公開', () {
      final p = build(abilityPublic: false, overallGradePublic: false);
      expect(p.ability, isNull);
      expect(p.grade, isNull);
    });
  });

  group('可見度：教官身分讓開關失效', () {
    // 規格規定：學徒要挑教官，看不到能力值就無從判斷，
    // 所以成為教官等同接受這部分公開。這不是這裡的判斷，是規格的規定。
    test('教官即使關掉開關，六維與綜合等級照樣公開', () {
      final p = build(
        abilityPublic: false,
        overallGradePublic: false,
        isInstructor: true,
      );
      expect(p.ability, isNotNull);
      expect(p.grade, isNotNull);
    });

    test('非教官不帶聲望與專長', () {
      final p = build(reputation: 150, specialties: ['增肌', '徒手']);
      expect(p.reputation, isNull);
      expect(p.specialties, isEmpty);
    });

    test('教官才帶聲望與專長', () {
      final p = build(
          isInstructor: true, reputation: 150, specialties: ['增肌', '徒手']);
      expect(p.reputation, 150);
      expect(p.specialties, ['增肌', '徒手']);
    });
  });

  group('落地形狀：關閉的欄位不可以出現在文件裡', () {
    // 安全規則的粒度是**文件**，不是欄位 —— 一旦寫進去，
    // 「他有幾點但不給你看」這件事本身就已經在雲端、別人讀得到了。
    // 所以關掉可見度必須是「不寫這個鍵」，不是「寫 null」。
    test('關閉六維時 json 裡沒有 ability 這個鍵', () {
      final j = build(abilityPublic: false).toJson();
      expect(j.containsKey('ability'), isFalse);
    });

    test('關閉綜合等級時 json 裡沒有 grade 這個鍵', () {
      final j = build(overallGradePublic: false).toJson();
      expect(j.containsKey('grade'), isFalse);
    });

    test('非教官的 json 裡沒有 reputation 這個鍵', () {
      final j = build(reputation: 150).toJson();
      expect(j.containsKey('reputation'), isFalse);
    });
  });

  group('Firestore 存讀', () {
    late FakeFirebaseFirestore db;

    setUp(() => db = FakeFirebaseFirestore());

    FirestorePublicProfile srcFor(String uid) =>
        FirestorePublicProfile(uid: uid, firestore: db);

    test('寫了別人讀得到', () async {
      await srcFor('u1').publish(build());

      final others = await srcFor('u2').others();
      expect(others, hasLength(1));
      expect(others.first.displayName, '阿昶');
      expect(others.first.uid, 'u1');
    });

    test('自己不在「別人」的清單裡', () async {
      await srcFor('u1').publish(build());
      expect(await srcFor('u1').others(), isEmpty);
    });

    test('關掉可見度之後重新發布，雲端就讀不到能力值了', () async {
      // 這條鎖住的是「用 set 整份覆寫，不用 merge」那個決定。
      // 用 merge 的話舊的 ability 會留在文件裡，
      // 使用者以為自己關了、別人其實還讀得到。
      final me = srcFor('u1');
      await me.publish(build());
      expect((await srcFor('u2').others()).first.ability, isNotNull);

      await me.publish(build(abilityPublic: false));
      expect((await srcFor('u2').others()).first.ability, isNull);
    });

    test('壞掉的一筆不會把整份清單弄掉', () async {
      await srcFor('u1').publish(build());
      // 沒有 displayName 的文件認不出是誰。
      await db.collection('public_profiles').doc('broken').set({'rank': 9});

      final others = await srcFor('u2').others();
      expect(others, hasLength(1));
      expect(others.first.uid, 'u1');
    });

    test('沒有任何人時回傳空清單，不是錯誤', () async {
      expect(await srcFor('u1').others(), isEmpty);
    });
  });
}
