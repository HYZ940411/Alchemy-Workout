import 'package:flutter/material.dart';

import '../data/store.dart';
import '../design/error_state.dart';
import '../design/overlays.dart';
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
    // 接了後端時**沒有「示範資料」這種東西**，而且「先進去」的後果不一樣：
    // 本機存檔是另存一份，Firestore 是**覆蓋同一份**。
    // 同一句文案在兩種情況下一句是安慰、一句是誤導。
    final cloud = !AppScope.of(context).demo;
    return Scaffold(
      backgroundColor: C.bgPage,
      body: SafeArea(
        child: ErrorState(
          title: '讀不到你的進度',
          // 【必須】錯誤說明要講得出發生什麼事、以及接下來會怎樣。
          // 最要緊的一句是「沒有被清空」—— 使用者第一個念頭一定是那個。
          message: cloud
              ? '存檔在雲端，但這次讀不出來。你的資料沒有被清空，'
                  '也沒有被覆寫 —— 這個畫面出現的時候，自動存檔是停著的。\n\n'
                  '請先再試一次。若這個錯誤一直出現，'
                  '請把畫面上的訊息回報給我們，不要選下面那個按鈕。'
              : '存檔在，但讀不出來。你的資料沒有被清空，'
                  '${backup == null ? '原檔仍在原處。' : '原檔已改名保留在裝置上。'}'
                  '可以再試一次；若選擇先進去，這次之後的進度會存成新的一份。',
          retryLabel: '再試一次',
          onRetry: onRetry,
          // 接了後端時這一顆是**破壞性**的 —— 進去之後的第一次自動存檔
          // 就會蓋掉雲端那份讀不出來的資料。標題要講得出後果，
          // 而不是一句聽起來很安全的「先用示範資料進去」。
          secondaryLabel:
              cloud ? '捨棄雲端那份，重新開始' : '先用示範資料進去',
          onSecondary: cloud ? () => _confirmDiscard(context) : onContinue,
        ),
      ),
    );
  }

  Future<void> _confirmDiscard(BuildContext context) async {
    final ok = await showAppDialog(
      context,
      title: '確定捨棄雲端的存檔？',
      message: '你在雲端的訓練紀錄、能力值、金幣與社群內容會在下一次自動存檔時'
          '被這個空白帳號覆蓋，無法復原。\n\n'
          '只有在你確定不要那份資料時才這樣做。',
      confirmLabel: '捨棄並重新開始',
      destructive: true,
    );
    if (ok == true) onContinue();
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
