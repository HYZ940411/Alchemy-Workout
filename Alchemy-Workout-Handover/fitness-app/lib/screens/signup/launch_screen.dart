import 'dart:async';

import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../widgets/common.dart';

/// 啟動頁
///
/// 沒有任何 Command —— 它只是「載入中」的一段時間，讓品牌先出現。
/// 載入結束即自動離開，不需使用者操作；點一下可以跳過等待。
class LaunchScreen extends StatefulWidget {
  final VoidCallback onDone;
  const LaunchScreen({super.key, required this.onDone});

  @override
  State<LaunchScreen> createState() => _LaunchScreenState();
}

class _LaunchScreenState extends State<LaunchScreen> {
  double progress = 0;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    // 用 Timer 而非重複播放的 AnimationController —— 後者會讓
    // pumpAndSettle 永遠等不到穩定狀態，測試直接卡死。
    timer = Timer.periodic(const Duration(milliseconds: 120), (t) {
      if (!mounted) return;
      setState(() => progress += 0.1);
      if (progress >= 1) {
        t.cancel();
        widget.onDone();
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        // 跳過等待：啟動頁沒有資訊要讀，不該擋著人。
        onTap: () {
          timer?.cancel();
          widget.onDone();
        },
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 原本是佔位用的方框＋通用啞鈴圖示。Logo 本身已經是一個
              // 完整的徽章造型，再框一層方框反而打架，所以直接呈現。
              Image.asset(
                'assets/images/logo.png',
                width: 96,
                height: 96,
                // 載不到就退回原本的佔位圖示，不要讓啟動頁破一個洞。
                errorBuilder: (_, _, _) => const Icon(
                  Icons.fitness_center,
                  size: 40,
                  color: C.textPrimary,
                ),
              ),
              const SizedBox(height: S.lg),
              Text('健金術', style: T.h1()),
              const SizedBox(height: S.xs),
              Text('ALCHEMY WORKOUT',
                  style: T.caption(color: C.textSecondary)),
              const SizedBox(height: S.xl),
              SizedBox(
                width: 200,
                child: BareProgress(value: progress.clamp(0, 1)),
              ),
            ],
          ),
        ),
      );
}
