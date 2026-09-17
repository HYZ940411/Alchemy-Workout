import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../domain/ability.dart';
import '../../domain/decay.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

/// 能力值退步狀態 —— 六個各自獨立的計時器
///
/// 為什麼一頁列六個而不是一個總計時器：退步是**逐維**判定的。
/// 每天練胸的人，腿仍會在第 10 天退步；只給一個「上次訓練」的數字，
/// 使用者永遠看不出退的是哪一維、為什麼退。
class DecayScreen extends StatefulWidget {
  const DecayScreen({super.key});

  @override
  State<DecayScreen> createState() => _DecayScreenState();
}

class _DecayScreenState extends State<DecayScreen> {
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final t = s.now;

    return Scaffold(
      backgroundColor: C.bgPage,
      appBar: AppBar(title: const Text('能力值退步狀態')),
      body: ListView(
        padding:
            const EdgeInsets.fromLTRB(S.base, S.base, S.base, S.scrollBottom),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '六維各自獨立計時，自該維最後訓練日的日界（次日 04:00）起算，'
                  '滿 ${kDecayIntervalHours ~/ 24} 天未訓練該維即退 '
                  '${(kDecayRatio * 100).round()}%。',
                  style: T.caption(),
                ),
                const SizedBox(height: S.sm),
                Text(
                  '退步下限為「本次中斷前所處節點的主階降 $kFloorMajorDrop 階、'
                  '小節點保留」之下緣，不低於該維初始值 —— '
                  '練到 A 級者停練夠久也不會退回註冊起點。',
                  style: T.caption(),
                ),
              ],
            ),
          ),

          const SectionTitle('六個計時器', trailing: '24 / 36 / 96 / 240 小時'),
          ListGroup(rows: [
            for (var i = 0; i < Dim.values.length; i++)
              _row(s, Dim.values[i], t, i != Dim.values.length - 1),
          ]),

          if (s.decayLog.isNotEmpty) ...[
            const SectionTitle('能力值已退步', trailing: '攜帶資訊：肌群維度'),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final e in s.decayLog.reversed.take(12))
                    Padding(
                      padding: const EdgeInsets.only(bottom: S.sm),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${dimNames[e.$1]}　'
                              '${e.$2.month}/${e.$2.day.toString().padLeft(2, '0')}',
                              style: T.body(),
                            ),
                          ),
                          Text(
                            e.$3 == 0 ? '已在下限' : '−${e.$3} 點',
                            style: T.body(
                                color: e.$3 == 0
                                    ? C.textSecondary
                                    : C.statusError),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],

          // 模擬時鐘只在開發者模式顯示。機制保留（它是 clock.dart 明文
          // 記載的展示設計，用來當場演出退步、到期、結算），
          // 但一般使用者看到「＋10 天」只會困惑 —— 那不是他能操作的東西。
          if (s.developerMode) ...[
          const SectionTitle('模擬時鐘', trailing: '開發者模式'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  // 原本寫「本 App 沒有後端」—— 那已經不是事實了（`[QA-02m]`）。
                  '時間不快轉就看不到第 10 天會發生什麼。'
                  '已位移 ${s.demoClockOffset.inDays} 天。',
                  style: T.caption(),
                ),
                const SizedBox(height: S.md),
                ButtonRow(
                  left: AppButton(
                    label: '＋1 天',
                    kind: BtnKind.secondary,
                    onPressed: () => setState(
                        () => s.advanceDemoClock(const Duration(days: 1))),
                  ),
                  right: AppButton(
                    label: '＋10 天',
                    onPressed: () => setState(
                        () => s.advanceDemoClock(const Duration(days: 10))),
                  ),
                ),
              ],
            ),
          ),
          ],
        ],
      ),
    );
  }

  ListRow _row(AppState s, Dim d, DateTime now, bool divider) {
    final td = s.decayTimers[d]!;
    final hours = hoursSinceBoundary(td.lastTrainedDate, now);
    final stage = stageOf(hours);
    final floor = s.decayFloorFor(d);
    final pts = s.points[d]!;

    final sub = StringBuffer()
      ..write('${nodeOf(pts).label}　$pts 點')
      ..write('　·　下限 ${nodeOf(floor).label} $floor 點');
    if (td.cumulative > 0) sub.write('　·　本次中斷已退 ${td.cumulative} 點');
    sub.write('\n');
    if (td.stopped) {
      // 停止後的計時器不再推進，直到該維再次被訓練才重新起算。
      sub.write('已觸及下限，計時器停止');
    } else {
      final left = td.nextDecayAt!.difference(now);
      final h = left.inHours;
      sub.write(h <= 0
          ? '即將退步'
          : (h >= 24 ? '距下次退步 ${left.inDays + 1} 天' : '距下次退步 $h 小時'));
    }
    sub.write('　·　最後訓練 '
        '${td.lastTrainedDate.month}/'
        '${td.lastTrainedDate.day.toString().padLeft(2, '0')}');

    return ListRow(
      title: dimNames[d]!,
      subtitle: sub.toString(),
      trailing: TagBadge(
        decayStageNames[stage]!,
        borderColor: switch (stage) {
          DecayStage.normal => C.statusSuccess,
          DecayStage.decaying => C.statusError,
          _ => C.statusWarning,
        },
      ),
      showDivider: divider,
    );
  }
}
