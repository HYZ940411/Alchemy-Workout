import '../../domain/clock.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme.dart';
import '../../widgets/common.dart';

/// 組間休息全屏倒數（§8.10 全屏大型）。
///
/// 【必須】這是全 App 唯一使用 `Display 64／72` 的地方。由來為 R-28：
/// 組間休息是**隔著 1～2 公尺瞄一眼**的情境，手機多半放在地上或器材架上，
/// 行內小卡的字級在該距離讀不到，等於作廢這條裁決的理由。
///
/// 圓環進度依 §8.20 留在本畫面，不抽成共用元件 —— 全案只有這裡用得到。
class RestCountdownScreen extends StatefulWidget {
  /// 休息結束的時刻。秒數與圓環比例皆由它與 [totalSeconds] 推得。
  final DateTime endsAt;

  /// 本次休息的總秒數，取值優先序見 `AppState.restSecondsFor`。
  final int totalSeconds;

  /// 計時自然歸零 —— 由系統觸發的「組間休息已結束」。
  final VoidCallback onFinished;

  /// 使用者按跳過 —— 由使用者觸發的「組間休息已結束」。
  final VoidCallback onSkip;

  /// 看接下來這個動作的說明。**不結束休息**：說明頁疊在上面，返回時倒數還在走。
  /// 空值＝不顯示按鈕（休息時最有空讀說明，卻是全屏蓋住訓練頁的時候 —— 2026-10-19 使用者回報）。
  final VoidCallback? onInfo;

  const RestCountdownScreen({
    super.key,
    required this.endsAt,
    required this.totalSeconds,
    required this.onFinished,
    required this.onSkip,
    this.onInfo,
  });

  @override
  State<RestCountdownScreen> createState() => _RestCountdownScreenState();
}

class _RestCountdownScreenState extends State<RestCountdownScreen> {
  Timer? _tick;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    // 一秒一跳 —— 數字與圓環同步走格。刻意不用每幀動畫：連續重繪會讓
    // `pumpAndSettle` 永遠等不到靜止，且倒數本來就是以秒為單位的東西。
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  /// 剩餘秒數 —— 數字與圓環比例共用同一個值，兩者不會對不上。
  int get _remaining {
    final ms = widget.endsAt.difference(appNow()).inMilliseconds;
    // 進位而非捨去：休息一開始就該看到完整的秒數（90 秒顯示 90，不是 89）。
    return ms > 0 ? (ms + 999) ~/ 1000 : 0;
  }

  void _handleZero() {
    if (_finished) return;
    _finished = true;
    // 【必須】歸零時觸發中強度震動 —— 使用者此時多半沒有看著螢幕。
    HapticFeedback.mediumImpact();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onFinished();
    });
  }

  @override
  Widget build(BuildContext context) {
    final remaining = _remaining;
    if (remaining <= 0) _handleZero();
    final progress = widget.totalSeconds > 0
        ? (remaining / widget.totalSeconds).clamp(0.0, 1.0)
        : 0.0;

    return Material(
      color: C.bgPage,
      // 不透明的 Material 會吃掉點擊 —— 底下訓練頁的步進器與勾選框
      // 在休息期間按不到（測試：〈全屏層吃掉點擊〉）。
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: S.base),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              Text('組間休息', style: T.h3(color: C.textSecondary)),
              const SizedBox(height: S.xl),
              SizedBox(
                key: restRingKey,
                width: _ringDiameter,
                height: _ringDiameter,
                child: CustomPaint(
                  painter: _RestRingPainter(progress: progress),
                  child: Center(
                    child: Text(
                      '$remaining',
                      // 比照 `restRingKey` —— 測試要驗的是**這個字級**，
                      // 而不是「畫面上有沒有『88』這三個字」。用字面值去找
                      // 會綁死真實時鐘：倒數慢一拍就變成 87，測試隨機轉紅。
                      key: restSecondsKey,
                      // 全 App 唯一的 Display 用例。
                      style: T.display(color: C.textPrimary),
                    ),
                  ),
                ),
              ),
              const Spacer(),
              if (widget.onInfo != null) ...[
                SizedBox(
                  width: double.infinity,
                  child: AppButton(
                    key: restInfoKey,
                    label: '看這個動作的說明',
                    kind: BtnKind.secondary,
                    onPressed: widget.onInfo,
                  ),
                ),
                const SizedBox(height: S.sm),
              ],
              SizedBox(
                width: double.infinity,
                child: AppButton(
                  label: '跳過休息',
                  kind: BtnKind.secondary,
                  onPressed: widget.onSkip,
                ),
              ),
              const SizedBox(height: S.lg),
            ],
          ),
        ),
      ),
    );
  }
}

/// 圓環的量測點 —— 直徑受規格書約束，由測試把關。
const Key restRingKey = Key('rest-ring');

/// 倒數的大數字。見上方註解：不可用字面值定位。
const Key restSecondsKey = Key('rest-seconds');

/// 休息畫面的「看這個動作的說明」鈕。
const Key restInfoKey = Key('rest-info');

/// 圓環直徑 240px、線寬 8px（§8.10）。
const double _ringDiameter = 240.0;
const double _ringStroke = 8.0;

class _RestRingPainter extends CustomPainter {
  /// 剩餘比例，1 為滿、0 為空。圓環隨剩餘秒數收合。
  final double progress;

  const _RestRingPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - _ringStroke) / 2;

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _ringStroke
      ..color = C.lineTrack;
    canvas.drawCircle(center, radius, track);

    if (progress <= 0) return;

    final fill = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _ringStroke
      ..strokeCap = StrokeCap.round
      ..color = C.statusSuccess;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2, // 十二點鐘方向起算
      2 * math.pi * progress,
      false,
      fill,
    );
  }

  @override
  bool shouldRepaint(_RestRingPainter old) => old.progress != progress;
}
