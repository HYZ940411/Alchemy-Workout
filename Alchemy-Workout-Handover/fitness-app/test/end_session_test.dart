// 登出再登入另一個帳號，不能看到上一個帳號的東西（第二批第 1 項）。
//
// `AppState` 在整個網頁連線期間只有一份。存檔裡的欄位會被下一個帳號的存檔整份蓋掉，
// 但團隊、貼文、封鎖名單、師徒關係、處罰、資料來源這些**不進存檔**，
// 不清的話就原封不動留給下一個人。2026-10-15 實測：帳號 A 的團隊、貼文、封鎖名單、uid
// 全都出現在切過去的帳號 B 身上。

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/chat_data.dart';
import 'package:fitness_app/data/store.dart';
import 'package:fitness_app/data/team_data.dart';
import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/state/app_state.dart';

class _Anything implements TeamSource {
  @override
  dynamic noSuchMethod(Invocation i) => Future<void>.value();
}

class _Chat implements ChatSource {
  @override
  dynamic noSuchMethod(Invocation i) => Future<void>.value();
}

Future<AppState> _load(MemoryStore st) async {
  final s = AppState(demo: false);
  await s.hydrate(st);
  return s;
}

Future<MemoryStore> _storeFor(String name) async {
  final st = MemoryStore();
  final s = AppState(demo: false);
  await s.hydrate(MemoryStore());
  s.displayName = name;
  s.signUpCompleted = true;
  await st.save(s.toSnapshot());
  return st;
}

Map<String, dynamic> _snap(AppState s) {
  final m = s.toSnapshot()..remove('savedAt');
  return jsonDecode(jsonEncode(m)) as Map<String, dynamic>;
}

void main() {
  /// 把帳號 A 用得很滿。
  Future<AppState> usedByA(MemoryStore storeA) async {
    final a = await _load(storeA);
    a.myUid = 'uA';
    a.coins = 7777;
    a.createTeam('A的隊');
    a.publishPost('A的貼文', PostVisibility.public);
    a.toggleFollow('某人', uid: 'u-x');
    a.blockUser('壞人', uid: 'u-bad');
    a.setEmail('a@a.co');
    a.adminClaim = true;
    a.adminMode = true;
    a.myViolations = 2;
    a.mentorApplications.add(PendingRequest('教官甲', 30, DateTime(2030)));
    a.sentApplications.add(PendingRequest('某隊', 30, DateTime(2030)));
    a.apprentices = [
      const Apprentice(
          name: '學徒乙',
          uid: 'u-app',
          rank: 10,
          ability: {},
          recentWorkouts: [])
    ];
    a.teamSource = _Anything();
    a.chatSource = _Chat();
    a.syncReport['x'] = 'y';
    await a.saveNow();
    return a;
  }

  test('登出之後，上一個帳號綁在身上的東西都被清掉', () async {
    final a = await usedByA(await _storeFor('A君'));

    a.endSession();

    expect(a.myUid, isNull);
    expect(a.adminClaim, isFalse, reason: '管理員身分不能留給下一個人');
    expect(a.adminMode, isFalse);
    expect(a.myTeam, isNull);
    expect(a.posts, isEmpty);
    expect(a.blockedUsers, isEmpty);
    expect(a.mentorApplications, isEmpty);
    expect(a.sentApplications, isEmpty);
    expect(a.apprentices, isEmpty);
    expect(a.myViolations, 0);
    expect(a.punishment, isNull);
    expect(a.teamSource, isNull, reason: '資料來源綁著 A 的 uid，留著會替 A 讀寫');
    expect(a.chatSource, isNull);
    expect(a.syncReport, isEmpty);
  });

  test('換成帳號 B 之後，跟全新載入 B 沒有差別', () async {
    final storeB = await _storeFor('B君');
    final a = await usedByA(await _storeFor('A君'));

    a.endSession();
    await a.hydrate(storeB);
    final b = await _load(storeB);

    expect(_snap(a), _snap(b), reason: '存檔裡的欄位');
    expect(a.displayName, 'B君');
    expect(a.coins, b.coins);
    expect(a.myTeam?.name, b.myTeam?.name);
    expect(a.posts.map((p) => p.text), b.posts.map((p) => p.text));
    expect(a.blockedUsers.map((x) => x.name), b.blockedUsers.map((x) => x.name));
    expect(a.following, b.following);
    expect(a.email, b.email);
    expect(a.myUid, b.myUid);
    expect(a.adminMode, b.adminMode);
    expect(a.apprentices.length, b.apprentices.length);
  });

  test('清掉之後不會再把資料寫回上一個帳號的存檔', () async {
    final storeA = await _storeFor('A君');
    final a = await usedByA(storeA);
    final savesBefore = storeA.saves;

    a.endSession();
    a.coins = 1; // 登出後的任何異動
    await a.saveNow();

    expect(storeA.saves, savesBefore, reason: '登出後 A 的存檔不該再被動到');
  });

  test('AuthGate 在登出與直接換人時都會呼叫 endSession', () {
    final src = File('lib/screens/auth_gate.dart').readAsStringSync();
    final start = src.indexOf('void _onAuthChanged');
    final body = src.substring(start, src.indexOf('/// 冷靜期已過就執行刪除。'));
    // 兩個地方：換人（_hydratedFor 不同且非空）、登出（user == null）。
    expect('endSession()'.allMatches(body).length, 2);
    expect(body, contains('_hydratedFor != null'));
  });
}
