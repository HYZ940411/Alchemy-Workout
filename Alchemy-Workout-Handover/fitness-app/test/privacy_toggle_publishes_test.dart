// 隱私設定要真的生效（第二批第 3 項）。
//
// 關掉「六維能力值對外可見」之後，別人讀到的公開檔案必須馬上沒有能力值。
// 實測：`setFlag()` 只改本機旗標，公開檔案要等下次升階或下次登入才重寫 ——
// 使用者以為自己關了，別人其實還讀得到。

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/public_profile.dart';
import 'package:fitness_app/state/app_state.dart';

class _Recorder implements PublicProfileSource {
  final List<PublicProfile> published = [];
  @override
  Future<void> publish(PublicProfile me) async => published.add(me);
  @override
  dynamic noSuchMethod(Invocation i) => Future<void>.value();
}

AppState _me(_Recorder r) => AppState(demo: false)
  ..myUid = 'u1'
  ..displayName = '阿昶'
  ..profileSource = r;

void main() {
  test('關掉六維能力值：馬上重寫公開檔案，而且裡面沒有能力值', () {
    final r = _Recorder();
    final s = _me(r);
    s.setFlag(ability: false);

    expect(r.published, hasLength(1));
    expect(r.published.single.ability, isNull);
    expect(r.published.single.grade, isNotNull, reason: '兩個開關各自獨立');
  });

  test('關掉綜合等級：公開檔案沒有等級、仍有六維', () {
    final r = _Recorder();
    final s = _me(r);
    s.setFlag(overall: false);

    expect(r.published.single.grade, isNull);
    expect(r.published.single.ability, isNotNull);
  });

  test('再打開：公開檔案又有了', () {
    final r = _Recorder();
    final s = _me(r);
    s.setFlag(ability: false);
    s.setFlag(ability: true);

    expect(r.published, hasLength(2));
    expect(r.published.last.ability, isNotNull);
  });

  test('沒有改變的開關不重寫（免得白白打雲端）', () {
    final r = _Recorder();
    final s = _me(r);
    s.setFlag(ability: true); // 預設就是開
    s.setFlag(metric: true);
    s.setFlag(autoOptimize: true);

    expect(r.published, isEmpty);
  });

  test('教官身分讓兩個開關都失效：關了也照樣公開', () {
    final r = _Recorder();
    final s = _me(r)..isInstructor = true;
    s.setFlag(ability: false, overall: false);

    expect(r.published.single.ability, isNotNull);
    expect(r.published.single.grade, isNotNull);
  });
}
