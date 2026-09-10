import 'package:flutter/material.dart';

import '../data/store.dart';
import '../design/error_state.dart';
import '../state/app_state.dart';
import '../theme.dart';

/// 讀存檔期間的畫面。
///
/// **不是可有可無的過場**：讀完之前若讓主畫面畫出來，使用者會對著一份
/// 假資料操作，他按下的簽到會在存檔讀回來時被整份蓋掉，而且沒有任何跡象。
class BootLoading extends StatelessWidget {
  const BootLoading({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
        backgroundColor: C.bgPage,
        body: Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: C.actionPrimary,
            ),
          ),
        ),
      );
}

/// 存檔讀不出來。
///
/// 這裡刻意**不自動改用假資料**：那樣使用者看到的是「我的進度全部不見了」，
/// 沒有說明、沒有重試，還會在下一次自動存檔時把原本可能救得回來的檔案覆蓋掉。
/// 要不要放棄那份存檔是他的決定。
class BootFailed extends StatelessWidget {
  final StoreLoadException? error;
  final VoidCallback onRetry;
  final VoidCallback onContinue;

  const BootFailed({
    super.key,
    required this.error,
    required this.onRetry,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final backup = error?.backupPath;
    return Scaffold(
      backgroundColor: C.bgPage,
      body: SafeArea(
        child: ErrorState(
          title: '讀不到你的進度',
          // 【必須】錯誤說明要講得出發生什麼事、以及接下來會怎樣。
          // 最要緊的一句是「沒有被清空」—— 使用者第一個念頭一定是那個。
          message: '存檔在，但讀不出來。你的資料沒有被清空，'
              '${backup == null ? '原檔仍在原處。' : '原檔已改名保留在裝置上。'}'
              '可以再試一次；若選擇先進去，這次之後的進度會存成新的一份。',
          retryLabel: '再試一次',
          onRetry: onRetry,
          secondaryLabel: '先用示範資料進去',
          onSecondary: onContinue,
        ),
      ),
    );
  }
}

/// 依讀取階段決定要畫什麼。
class BootGate extends StatelessWidget {
  final Widget child;
  const BootGate({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    switch (s.hydration) {
      case HydrationPhase.loading:
        return const BootLoading();
      case HydrationPhase.failed:
        return BootFailed(
          error: s.hydrationError,
          onRetry: s.retryHydration,
          onContinue: s.continueWithoutSave,
        );
      case HydrationPhase.ready:
        return child;
    }
  }
}
