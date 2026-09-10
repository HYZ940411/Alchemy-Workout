import 'dart:async';

import 'package:flutter/material.dart';

import '../design/error_state.dart';
import '../design/skeleton.dart';
import '../design/tokens.dart';
import '../state/app_state.dart';

/// 載入邊界 —— 首次載入走骨架屏，失敗走錯誤頁，成功才畫真的內容。
///
/// 三件事被綁在同一個地方，因為它們是同一段生命週期的三個結果；
/// 分散在各頁自己寫，遲早會出現「有骨架沒錯誤頁」或「錯誤頁沒有重試」。
///
/// 骨架屏只給**首次載入**（§8.6）：下拉重整用頂部轉圈、按鈕觸發用按鈕內轉圈，
/// 都不走這裡。
class LoadBoundary extends StatefulWidget {
  /// 該畫面的識別碼。用來記住「這頁載過了」，回訪不再骨架一次。
  final String id;
  final SkeletonKind kind;

  /// 顯示列數 —— 依該頁首屏可見的列數，不多不少（§8.6）。
  final int rows;

  /// 著陸頁的錯誤文案講的是連線本身，次層頁講的是這份清單。
  final bool landing;
  final EdgeInsets padding;
  final WidgetBuilder builder;

  const LoadBoundary({
    super.key,
    required this.id,
    required this.kind,
    required this.rows,
    required this.builder,
    this.landing = false,
    this.padding = const EdgeInsets.all(S.base),
  });

  @override
  State<LoadBoundary> createState() => _LoadBoundaryState();
}

enum _Phase { loading, error, ready }

class _LoadBoundaryState extends State<LoadBoundary> {
  _Phase phase = _Phase.ready;
  Timer? timer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (phase == _Phase.ready && timer == null) _start();
  }

  void _start() {
    final s = AppScope.of(context);
    // 未開模擬、或這頁載過了，就直接是內容 —— 不平白讓人等。
    if (s.demoLoadMs <= 0 || s.hasLoadedOnce(widget.id)) {
      phase = _Phase.ready;
      return;
    }
    phase = _Phase.loading;
    timer = Timer(Duration(milliseconds: s.demoLoadMs), () {
      if (!mounted) return;
      setState(() {
        if (s.demoOffline) {
          phase = _Phase.error;
        } else {
          phase = _Phase.ready;
          s.markLoadedOnce(widget.id);
        }
      });
    });
  }

  void _retry() {
    timer?.cancel();
    timer = null;
    setState(_start);
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => switch (phase) {
        _Phase.loading => SingleChildScrollView(
            padding: widget.padding,
            physics: const NeverScrollableScrollPhysics(),
            child: Skeleton(kind: widget.kind, rows: widget.rows),
          ),
        _Phase.error => widget.landing
            ? ErrorState.landing(onRetry: _retry)
            : ErrorState(onRetry: _retry),
        _Phase.ready => widget.builder(context),
      };
}
