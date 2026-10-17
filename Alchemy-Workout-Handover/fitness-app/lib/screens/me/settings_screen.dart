import 'package:cloud_firestore/cloud_firestore.dart' show FirebaseFirestore;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../../build_stamp.dart';
import '../../data/auth.dart';
import '../../data/firestore_setup.dart';
import '../../data/guarded_transaction.dart'
    show fallbackCount, lastFallbackNote, probeTransactionRead;
import '../../domain/registration.dart';
import '../../mock/mock_data.dart';
import '../../mock/mock_equipment.dart';
import '../../state/app_state.dart';
import '../train/preferred_times_screen.dart';
import 'account_delete_screen.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Read Model：設定頁
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  /// 值域為〈器材設定 Aggregate〉的 8 個品項，與動作的「所需器材明細」同一組。
  static const _equipment = kEquipmentItems;

  /// 登出。
  ///
  /// **先補一次存檔再登出**：自動存檔有 300ms 防抖，登出當下若剛好還在
  /// 那個窗口裡，最後一筆變動會跟著登入狀態一起消失。
  ///
  /// **登出之後一定要把疊上去的畫面收掉。** [AuthGate] 換掉的是
  /// `MaterialApp.home`，也就是**最底層**那一頁；而設定頁是
  /// `Navigator.push` 疊在它上面的。只換底層的話，登入頁是畫出來了，
  /// 卻整個被設定頁蓋住 —— 使用者看到的是「按了登出完全沒反應」。
  static Future<void> _logOut(BuildContext context) async {
    final confirm = await showAppDialog(
      context,
      title: '要登出嗎？',
      message: '你的進度存在雲端，下次用同一個帳號登入就會回來。',
      confirmLabel: '登出',
      cancelLabel: '取消',
    );
    if (confirm != true || !context.mounted) return;

    // 先取出來，之後的 await 會讓這個 context 不再保證可用。
    final navigator = Navigator.of(context);
    final state = AppScope.of(context);

    // 離線時 saveNow 永遠不會回來，原本在這裡直接 await 會卡死。
    // 最多等 3 秒；沒送完就先問，不替使用者決定把資料丟掉。
    final synced = await state.flushForSignOut(
      askToForce: () async =>
          await showAppDialog(
            context,
            title: '還有資料沒同步',
            message: '目前連不上網路，最後一些變動還沒送到雲端。'
                '現在登出，這些變動可能會遺失。要仍然登出嗎？',
            confirmLabel: '仍要登出',
            cancelLabel: '先不要',
          ) ==
          true,
    );
    if (synced == null) return;

    await AuthService().signOut();
    navigator.popUntil((route) => route.isFirst);
    // 資料都送完了才清本機快取（共用電腦不留下上一位的資料）；
    // 沒送完的話清掉等於把那些還沒送出的變動一起丟掉。
    if (synced) await wipeLocalCacheAndReload(FirebaseFirestore.instance);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final delDays = s.deletionDaysLeft;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          '設定',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 50),
        children: [
          // **這四列原本是寫死的字串**（`4 天`、`60–90 分`、`增肌`、`中階`），
          // 每一位使用者看到的都一樣，而且點下去什麼都不會發生 ——
          // 儘管右邊畫著一個看起來可點的箭頭，標題上還寫著
          // 「更新後立即重新推薦」。
          //
          // 值本來就在 [AppState] 裡（註冊時由 `completeSignUp` 落地、
          // 存檔也有存），只是這一頁沒有去讀。改成讀真值並可編輯，
          // 更新走 `updateSurvey` —— 與簽到頁的 90 天週期詢問同一支，
          // 那句「立即重新推薦」由它兌現。
          const SectionLabel('訓練問卷', trailing: '更新後立即重新推薦'),
          Panel(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(
              children: [
                _Row(
                  label: '每週健身天數',
                  value: '${s.daysPerWeek} 天',
                  onTap: () => _pickOne(
                    context,
                    title: '每週健身天數',
                    options: const ['1', '2', '3', '4', '5', '6', '7'],
                    labelOf: (v) => '$v 天',
                    current: '${s.daysPerWeek}',
                    onPick: (v) => s.updateSurvey(daysPerWeek: int.parse(v)),
                  ),
                ),
                _Row(
                  label: '每次健身時長',
                  value: s.duration,
                  onTap: () => _pickOne(
                    context,
                    title: '每次健身時長',
                    options: kDurations,
                    current: s.duration,
                    onPick: (v) => s.updateSurvey(duration: v),
                  ),
                ),
                _Row(
                  label: '健身目標',
                  value: s.commonGoal,
                  onTap: () => _pickOne(
                    context,
                    title: '健身目標',
                    options: kCommonGoals,
                    current: s.commonGoal,
                    onPick: (v) => s.updateSurvey(commonGoal: v),
                  ),
                ),
                _Row(
                  label: '健身經驗',
                  value: s.experience,
                  onTap: () => _pickOne(
                    context,
                    title: '健身經驗',
                    options: kExperience,
                    current: s.experience,
                    onPick: (v) => s.updateSurvey(experience: v),
                  ),
                ),
                // 動機類目標。**註冊問卷問了，在此之前沒有任何地方存它**，
                // 也就從來沒有出現在這一頁 —— 與生日同一個毛病。
                // 選填，所以「未填寫」是合法狀態，也給得清空。
                _Row(
                  label: '健身動機',
                  value: s.motiveGoal ?? '未填寫（選填）',
                  onTap: () => _pickOne(
                    context,
                    title: '健身動機',
                    options: kMotiveGoals,
                    current: s.motiveGoal ?? '',
                    allowNone: '不設定',
                    onPick: (v) => s.updateMotiveGoal(v.isEmpty ? null : v),
                  ),
                ),
                // 器材也是註冊問卷問的，而且是推薦的**第一順位**比對維度
                // （硬約束：器材不符即完全無法執行）。原本這一頁根本沒有它，
                // 於是換了健身房、或退掉會員回家徒手練的人無從更新。
                _Row(
                  label: '可用器材',
                  value: s.equipmentTier,
                  onTap: () => _pickOne(
                    context,
                    title: '可用器材',
                    options: kEquipmentTiers,
                    current: s.equipmentTier,
                    onPick: (v) => s.updateSurvey(equipmentTier: v),
                  ),
                ),
              ],
            ),
          ),
          const SectionLabel('個人資料'),
          Panel(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(
              children: [
                _Row(
                  label: '身高',
                  value: s.heightText(s.heightCm),
                  onTap: () => _editNumber(
                    context,
                    title: '身高',
                    unit: s.metricUnits ? 'cm' : 'in',
                    current: s.heightCm,
                    min: 100,
                    max: 250,
                    onSave: s.updateHeight,
                  ),
                ),
                _Row(
                  label: '體重',
                  value: s.weightText(s.bodyweightKg),
                  onTap: () => _editNumber(
                    context,
                    title: '體重',
                    unit: s.metricUnits ? 'kg' : 'lb',
                    current: s.bodyweightKg,
                    min: 25,
                    max: 300,
                    onSave: s.updateWeight,
                  ),
                ),
                // **原本寫死成 `1996 / 03 / 12`**，每個人都一樣。
                // 註冊問卷第 4 題問了生日，但在此之前沒有任何地方存它 ——
                // 問了就丟。現在存了（`AppState.birthday`），
                // 沒有的就說沒有，不擺一個看起來很真的假日期。
                // 生日：**沒填的可以補，填了就鎖住**（2026-09-26 使用者裁決 B）。
                //
                // 唯讀是規格的裁決（〈設定頁 Read Model〉）：生日決定年齡係數，
                // 改動會使既有點數失去計算基準，如需更正屬客服範疇。
                // 但規格沒設想到「從來沒存過」這種狀況 —— 2026-09-26 之前
                // 註冊問卷問了生日卻沒地方存，那些帳號永遠填不進去。
                // 補一個從來沒有的值不會讓任何點數失去基準，因為在它之前
                // 根本沒有基準。
                //
                // **鎖著也要說得出理由。** 原本只有一把鎖頭圖示，
                // 使用者看不出那是刻意的還是壞了。
                _Row(
                  label: '生日',
                  value: s.birthday == null ? '未填寫（可補填）' : _ymd(s.birthday!),
                  readOnly: s.birthday != null,
                  onTap: s.birthday != null
                      ? () => showToast(context,
                          '生日決定年齡係數，填寫後不可修改。如需更正請聯繫客服。')
                      : () => _fillBirthday(context, s),
                ),
                _Row(
                  label: '性別',
                  value: s.isMale ? '男' : '女',
                  readOnly: true,
                  onTap: () => showToast(
                      context, '性別決定 DOTS 係數，改動會讓既有能力值失去基準。如需更正請聯繫客服。'),
                ),
                // 選填。填了才收得到處罰與申訴結果、帳號刪除排程
                // 兩類電子郵件通知；不填一樣由推播與 App 內通知承擔。
                _Row(
                  label: '電子郵件',
                  value: s.email ?? '未填寫（選填）',
                  onTap: () => _editEmail(context, s),
                ),
              ],
            ),
          ),
          const SectionLabel('顯示偏好'),
          Panel(
            child: _Toggle(
              label: '使用公制單位',
              sub: s.metricUnits ? '公斤 / 公分' : '磅 / 英吋',
              value: s.metricUnits,
              onChanged: (v) => s.setFlag(metric: v),
            ),
          ),
          // 這一段講的是「你的進度存在哪裡」。
          //
          // **接了帳號的人看不到它**（2026-09-28 使用者裁決：
          // 「設定內的儲存可以拿掉，不用給使用者看到」）——
          // 對他而言答案是「存在帳號裡，不會不見」，那是預期，不是新聞；
          // 而「已存 41 次」是給我看的除錯數字，不是給他看的。
          //
          // **示範模式留著**：那時候資料真的存在這台裝置上，清瀏覽器資料
          // 就會不見，那句話非說不可。開發者模式也留著。
          if (s.demo || s.developerMode) ...[
          SectionLabel('儲存', trailing: s.demo ? '存在這台裝置上' : '存在你的帳號'),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.demo
                      ? '進度會自動存到本機，關掉重開仍在。已存 ${s.saveCount} 次。'
                      : '進度會自動存到你的帳號。換裝置、清瀏覽器資料都不會不見。'
                          '已存 ${s.saveCount} 次。',
                  style: T.body(),
                ),
                // 說清楚哪些東西沒存 —— 使用者發現團隊變回去時，
                // 要能在這裡找到答案，而不是以為壞掉了。
                // 接了帳號就沒有這回事，那句話也就不必說。
                if (s.demo) ...[
                  const SizedBox(height: 6),
                  Text(
                    '不含動作庫、貼文、訂單、團隊與後台佇列。',
                    style: T.caption(),
                  ),
                  const SizedBox(height: 14),
                  AppButton(
                    label: '重設示範資料',
                    kind: BtnKind.secondary,
                    onPressed: () async {
                      final ok = await showAppDialog(
                        context,
                        title: '清除存檔？',
                        message: '這台裝置上的進度會全部刪除，'
                            '下次開啟回到最初的示範資料。這個動作無法復原。',
                        confirmLabel: '清除',
                        destructive: true,
                      );
                      if (ok != true || !context.mounted) return;
                      await s.clearSaved();
                      if (!context.mounted) return;
                      showToast(context, '已清除，重開 App 即回到初始狀態');
                    },
                  ),
                ],
              ],
            ),
          ),
          ],
          // 模擬載入與模擬離線是除錯用的控制項，跟 `[QA-02n]`／`[QA-02o]`
          // 那一批同一個道理 —— 一般使用者看到只會問「這是什麼」。
          if (s.developerMode) ...[
            const SectionLabel('示範', trailing: '開發者模式'),
            Panel(
              child: Column(
                children: [
                  _Toggle(
                    label: '模擬首次載入',
                    sub: s.demoLoadMs > 0
                        ? '每頁首次進入先顯示 ${s.demoLoadMs} 毫秒骨架屏'
                        : '關閉。資料就在記憶體裡，平白讓每頁慢一秒只是折磨人',
                    value: s.demoLoadMs > 0,
                    onChanged: (v) => s.setDemoLoadMs(v ? 900 : 0),
                  ),
                  const SizedBox(height: 14),
                  _Toggle(
                    label: '模擬離線',
                    sub: '載入結束時改走錯誤頁，可按重新載入重試'
                        '${s.demoLoadMs > 0 ? '' : '（需先開啟模擬首次載入）'}',
                    value: s.demoOffline,
                    onChanged: (v) => s.setDemoOffline(v),
                  ),
                ],
              ),
            ),
            // 登入後每一塊同步的結果。這幾塊全部吞掉錯誤 —— 那是對的
            // （社群讀不到不該擋住訓練），代價是出問題時完全沒有跡象。
            // 「申請送得出去、對方看不到」查了三輪都在猜，就是因為
            // 這幾條路徑什麼都不說。
            // 累積訓練次數與訓練歷史筆數的對帳。
            //
            // 這兩個數字曾經漂開很久都沒被發現（次數無條件 +1、歷史要求
            // 「有完成的組」），使用者是在教官申請頁看到 11 而訓練清單只有
            // 1 才回報的。**沒有任何地方把它們並排過。**
            //
            // 現在兩者讀同一個旗標（見 `finishWorkout` 的 `recorded`），
            // 不該再漂 —— 但雲端寫入失敗一樣會讓歷史少掉幾筆，
            // 而那條路已經出事過一次。並排一次，下次一眼就看得出來。
            // 快轉到教官門檻。**只給開發者模式**，而且可還原。
            //
            // 使用者要測 T1／T3（師徒關係），兩者都要求其中一方是教官，
            // 而初審門檻是階級 ≥20 且累積訓練次數 ≥50 —— 測試帳號到不了。
            // 建置戳記。使用者回報「某功能沒生效」時，第一個要排除的是
            // 「他在舊版上測」—— 在此之前沒有任何辦法分辨那兩件事，
            // 而它們的下一步完全相反。
            // 診斷：網頁版交易的讀取（tx.get）從 2026-10-17 起丟出空物件。
            // 只讀一份文件、不寫任何東西，可以隨時重做；配合網址參數（?longpoll=force 等）比對。
            // 管理員：重置所有人今天的限時任務（Demo 或事故後用）。
            // 完成紀錄分散在每個人的存檔與各隊文件裡，沒有集中的地方可以逐一清，
            // 所以是換一個「重置代數」—— 所有人下次載入時，今天的限時任務就當作還沒做。
            if (s.isPlatformAdmin) ...[
              const SectionLabel('重置限時任務', trailing: '管理員・開發者模式'),
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '把所有人今天的限時任務、已領的獎勵都當作還沒做。'
                      '對方要重新整理頁面才會看到；已經領過的獎勵可以再領一次。',
                      style: TextStyle(fontSize: 11.5, color: AppColors.textFaint),
                    ),
                    const SizedBox(height: 8),
                    AppButton(
                      label: '重置所有人今天的限時任務',
                      kind: BtnKind.secondary,
                      onPressed: () async {
                        final ok = await showAppDialog(
                          context,
                          title: '重置所有人今天的限時任務？',
                          message: '所有人今天的完成紀錄與已領的獎勵都會當作還沒做，'
                              '獎勵可以再領一次。對方要重新整理頁面才會生效。',
                          confirmLabel: '重置',
                          cancelLabel: '取消',
                        );
                        if (ok != true || !context.mounted) return;
                        final err = await s.resetTimedTaskForAll();
                        if (!context.mounted) return;
                        showToast(context, err ?? '已重置，請大家重新整理頁面');
                      },
                    ),
                  ],
                ),
              ),
            ],
            const SectionLabel('交易讀取測試', trailing: '開發者模式'),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '只用交易讀一份文件，不寫任何東西。成功代表交易的讀取正常。',
                    style: TextStyle(fontSize: 11.5, color: AppColors.textFaint),
                  ),
                  const SizedBox(height: 8),
                  AppButton(
                    label: '測試交易讀取',
                    kind: BtnKind.secondary,
                    onPressed: () async {
                      final path = s.myTeam != null
                          ? 'teams/${s.myTeam!.id}'
                          : (s.myUid != null ? 'public_profiles/${s.myUid}' : null);
                      s.setTransactionProbeResult(path == null
                          ? '沒有可讀的文件（還沒登入）'
                          : await probeTransactionRead(
                              FirebaseFirestore.instance, path));
                    },
                  ),
                  if (s.transactionProbeResult != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      s.transactionProbeResult!,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: s.transactionProbeResult!.startsWith('成功')
                            ? AppColors.textFaint
                            : C.statusError,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SectionLabel('版本', trailing: '開發者模式'),
            Panel(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: _Row(
                label: '建置',
                value: kBuildStamp.isEmpty ? '（本機執行）' : kBuildStamp,
                readOnly: true,
              ),
            ),
            const SizedBox(height: S.base),
            const SectionLabel('師徒解除冷卻', trailing: '開發者模式'),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '規格是解除後 3 天內不能與其他對象建立師徒關係。'
                    '開啟這個開關後，解除就立刻視為結束，可以馬上重新申請 ——'
                    '代價是這段期間沒有「恢復」可以測。'
                    '只在開發者模式有效，不進存檔。',
                    style: T.caption(),
                  ),
                  const SizedBox(height: S.md),
                  AppButton(
                    label: s.devSkipMentorCooldown
                        ? '關閉：解除後照規格等 3 天'
                        : '開啟：解除後立刻可重新申請',
                    kind: BtnKind.secondary,
                    onPressed: () {
                      s.toggleDevSkipMentorCooldown();
                      showToast(
                          context,
                          s.devSkipMentorCooldown
                              ? '已開啟，解除後可立刻重新申請'
                              : '已關閉，恢復照規格 3 天');
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: S.base),
            const SectionLabel('教官門檻', trailing: '開發者模式'),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Builder(builder: (_) {
                    final g = s.instructorGate;
                    return Text(
                      '目前：階級 ${s.rank} / ${g.requiredRank}　·　'
                      '訓練 ${s.totalWorkouts} / ${g.requiredWorkouts} 次\n'
                      '只會把這兩個數字推到門檻上，不會讓你直接變成教官 —— '
                      '申請、初審、測驗、人工審核仍要照走。',
                      style: T.caption(),
                    );
                  }),
                  const SizedBox(height: S.md),
                  AppButton(
                    label: '快轉到教官門檻',
                    kind: BtnKind.secondary,
                    onPressed: () {
                      s.fastForwardToInstructorGate();
                      showToast(context, '已推到門檻，可用下面那顆還原');
                    },
                  ),
                  // 14 天重考鎖的逃生門。
                  //
                  // 使用者測驗沒過被駁回後問「有沒有辦法跳過測驗」——
                  // 當下沒有：Demo 推進鍵的階段清單裡沒有「已駁回」，
                  // 而重新申請擋在 14 天鎖上。**逃生門在最需要它的時候
                  // 打不開。**
                  //
                  // 只清時間鎖，不改階段、不給分數。
                  if (s.examRetakeLeft > Duration.zero) ...[
                    const SizedBox(height: S.sm),
                    Text('重考鎖剩餘 ${_dh(s.examRetakeLeft)}。',
                        style: T.caption()),
                    const SizedBox(height: S.sm),
                    AppButton(
                      label: '解除重考鎖',
                      kind: BtnKind.secondary,
                      onPressed: () {
                        s.clearExamRetakeLock();
                        showToast(context, '已解除，可以重新申請了');
                      },
                    ),
                  ],
                  if (s.canUndoInstructorFastForward) ...[
                    const SizedBox(height: S.sm),
                    AppButton(
                      label: '還原成原本的數字',
                      kind: BtnKind.secondary,
                      onPressed: () {
                        s.undoInstructorFastForward();
                        showToast(context, '已還原');
                      },
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: S.base),
            // AI 意圖分類的診斷。
            //
            // **這一區原本只在「判定過之後」才出現** —— 使用者回報
            // 「沒找到在哪看」。要看到它，得先開一場訓練、進調整畫面、
            // 打一句話、再回到設定頁；中間任何一步走岔就什麼都沒有。
            // 改成一律顯示，並加一顆直接打一次的按鈕。
            const SectionLabel('AI 意圖分類', trailing: '開發者模式'),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('上次由誰判定：${s.intentDecidedBy ?? '尚未判定過'}',
                      style: T.caption()),
                  if (s.aiProbeResult case final r?) ...[
                    const SizedBox(height: S.sm),
                    Text(r, style: T.caption(color: C.textPrimary)),
                  ],
                  const SizedBox(height: S.md),
                  AppButton(
                    label: '直接測一次 AI 連線',
                    kind: BtnKind.secondary,
                    onPressed: () async {
                      final r = await s.runAiProbe();
                      if (context.mounted) showToast(context, r);
                    },
                  ),
                  // 品質評分（教官初審）走的是**另一條** Worker 路徑
                  // （`sessions` 分流）。它失敗時申請會停在「初審中」，
                  // 而在此之前那個原因只存在於 `debugPrint` 裡。
                  if (s.qualityScoreError case final e?) ...[
                    const SizedBox(height: S.md),
                    Text('品質評分上次失敗：$e', style: T.caption()),
                  ],
                ],
              ),
            ),
            const SizedBox(height: S.base),
            const SectionLabel('訓練次數對帳', trailing: '開發者模式'),
            Panel(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Column(
                children: [
                  _Row(
                      label: '累積訓練次數',
                      value: '${s.totalWorkouts}',
                      readOnly: true),
                  _Row(
                      label: '訓練歷史筆數',
                      value: '${s.history.length}',
                      readOnly: true),
                  _Row(
                    label: '差異',
                    value: s.totalWorkouts == s.history.length
                        ? '0（相符）'
                        : '${s.totalWorkouts - s.history.length}（歷史少了）',
                    readOnly: true,
                  ),
                  // 2026-09-28 加：使用者要驗「同一天練兩場，天數只加一」，
                  // 而**累積訓練天數畫面上根本沒有**，只有次數看得到 ——
                  // 那一條就測不了。三個並排才看得出哪一個不對。
                  _Row(
                      label: '累積訓練天數',
                      value: '${s.totalWorkoutDays}',
                      readOnly: true),
                  _Row(
                      label: '連續訓練天數',
                      value: '${s.trainingStreakDays}',
                      readOnly: true),
                  // 自動優化的計數。**在此之前任何地方都看不到它** ——
                  // 使用者問「我要去哪看優化推薦」，而答案取決於這個數字
                  // 是 0 還是 2，我卻沒辦法從外面判斷他是哪一種狀態。
                  _Row(
                    label: '自動優化計數',
                    value: '${s.autoOptimizeCount} / '
                        '${AppState.kAutoOptimizeEvery}'
                        '${s.optimizedPlanId == null ? '' : '（已有一份待看）'}',
                    readOnly: true,
                  ),
                ],
              ),
            ),
            // 互動計數的自救鍵（2026-09-28 使用者裁決 A）。
            //
            // 示範種子漏進真帳號那件事今天發生了四次，而這一個**修不回來**：
            // 「按過幾個讚」沒有證據可查。與其硬湊一個數字，不如給一顆
            // 讓他自己歸零的按鈕 —— 下次再漏也不必等我改程式再部署。
            const SizedBox(height: S.sm),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '互動計數：'
                    '${kInteractionKinds.map((k) => '$k ${s.interactionTotals[k] ?? 0}').join('、')}',
                    style: T.caption(),
                  ),
                  // 改名冷卻鎖的逃生門。理由同上面的重考鎖 ——
                  // 測的人一按下去就把自己鎖住 30 天。
                  if (s.renameBlockedReason() case final why?) ...[
                    const SizedBox(height: S.md),
                    Text(why, style: T.caption()),
                    const SizedBox(height: S.sm),
                    AppButton(
                      label: '解除改名冷卻',
                      kind: BtnKind.secondary,
                      onPressed: () {
                        s.clearRenameCooldown();
                        showToast(context, '已解除，可以再改一次暱稱了');
                      },
                    ),
                  ],
                  const SizedBox(height: S.md),
                  AppButton(
                    label: '重設互動計數',
                    kind: BtnKind.secondary,
                    onPressed: () async {
                      final ok = await showAppDialog(
                        context,
                        title: '把互動計數歸零？',
                        message: '分享、發文、按讚、留言的終身累計會歸零。'
                            '已經解鎖的成就不會被收回。',
                        confirmLabel: '歸零',
                      );
                      if (ok != true || !context.mounted) return;
                      s.resetInteractionTotals();
                      if (!context.mounted) return;
                      showToast(context, '互動計數已歸零');
                    },
                  ),
                ],
              ),
            ),
            if (s.totalWorkouts != s.history.length) ...[
              const SizedBox(height: S.sm),
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '差異不為 0 代表次數曾經多算過。兩個來源，而它們無法事後'
                      '區分：一是 2026-09-26 之前「開場即關閉」也算一次訓練的'
                      '舊行為（依現在的規則本來就不該算），二是雲端寫入失敗吃掉的'
                      '真實場次（那是真的練過）。',
                      style: T.caption(),
                    ),
                    const SizedBox(height: S.md),
                    AppButton(
                      label: '校正為訓練歷史的筆數',
                      kind: BtnKind.secondary,
                      onPressed: () => _reconcile(context, s),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: S.base),
            const SectionLabel('登入同步', trailing: '開發者模式'),
            // 存檔失敗原本完全無聲。2026-09-24 一個形狀不合的欄位讓
            // Firestore 整份拒收，帳號從那一刻起什麼都存不起來，而畫面上
            // 唯一的跡象是某一頁顯示「未填寫」。
            if (s.saveError != null) ...[
              Panel(
                color: C.statusError.withValues(alpha: 0.08),
                border: C.statusError,
                child: Text(
                    '存檔失敗，連續 ${s.consecutiveSaveFailures} 次：\n${s.saveError}',
                    style: const TextStyle(
                        fontSize: 11.5, color: C.statusError)),
              ),
              const SizedBox(height: 10),
            ],
            if (s.chatSendError != null) ...[
              Panel(
                color: C.statusError.withValues(alpha: 0.08),
                border: C.statusError,
                child: Text('最近一次私訊送出失敗：\n${s.chatSendError}',
                    style: const TextStyle(
                        fontSize: 11.5, color: C.statusError)),
              ),
              const SizedBox(height: 10),
            ],
            // 評分寫不上雲的原因。**同步報告只記登入那一趟**，
            // 而評分是使用者按下去的那一刻才寫 —— 兩者不同時機，
            // 所以另外列一行。
            if (s.ratingSyncError case final why?) ...[
              Panel(
                color: C.statusError.withValues(alpha: 0.08),
                border: C.statusError,
                child: Text('評分沒有寫上雲：$why',
                    style: const TextStyle(
                        fontSize: 11.5, color: C.statusError)),
              ),
              const SizedBox(height: 10),
            ],
            Panel(
              child: s.syncReport.isEmpty
                  ? const Text(
                      '尚未同步。這一份在登入後才會有內容 ——'
                      '目前是未登入，或還沒跑完。',
                      style: TextStyle(
                          color: AppColors.textFaint, fontSize: 11.5),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final e in s.syncReport.entries) ...[
                          Text(
                            e.key,
                            style: const TextStyle(
                                fontSize: 12.5, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            e.value,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: e.value.startsWith('失敗') ||
                                      e.value.contains('⚠️')
                                  ? C.statusError
                                  : AppColors.textFaint,
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                      ],
                    ),
            ),
            const SizedBox(height: 10),
            // 即時訂閱（`[BE-16]`）。**「完全沒有變動」與「訂閱根本沒掛上」
            // 在畫面上長得一模一樣** —— 兩者都是什麼都不動。所以把
            // 「訂了沒、醒過幾次」攤出來，實測時才分得出是哪一種。
            Panel(
              child: s.cloudWatchReport.isEmpty
                  ? Text(
                      s.isWatchingCloud
                          ? '訂閱中。'
                          : '沒有任何即時訂閱 —— 對方的變動要重新整理才看得到。',
                      style: const TextStyle(
                          color: AppColors.textFaint, fontSize: 11.5),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('即時訂閱',
                            style: TextStyle(
                                fontSize: 12.5, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        for (final e in s.cloudWatchReport.entries)
                          Text(
                            '${e.key}　${e.value}',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: e.value.startsWith('失敗')
                                  ? C.statusError
                                  : AppColors.textFaint,
                            ),
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: 10),
            // 雲端讀取。**「雲端本來就沒有」與「這一趟讀失敗了」
            // 在畫面上長得一模一樣** —— 兩者都是空的。
            if (s.cloudReadReport.isNotEmpty)
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('雲端讀取',
                        style: TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    for (final e in s.cloudReadReport.entries)
                      Text(
                        '${e.key}　${e.value}',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: e.value.startsWith('失敗') ||
                                  e.value.startsWith('沒讀')
                              ? C.statusError
                              : AppColors.textFaint,
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            // 即發即忘的寫入。**「沒送出」原本與「成功」長得一模一樣** ——
            // 2026-09-30 教官指派的任務到不了學徒，畫面上跳「已指派」、
            // 雲端連子集合都沒有，而沒有任何地方看得出來。
            if (s.cloudWriteReport.isNotEmpty)
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('雲端寫入',
                        style: TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    for (final e in s.cloudWriteReport.entries)
                      Text(
                        '${e.key}　${e.value}',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: e.value.startsWith('失敗') ||
                                  e.value.startsWith('沒送出')
                              ? C.statusError
                              : AppColors.textFaint,
                        ),
                      ),
                    // 交易的讀取壞掉、改走「一般讀取＋批次寫入」的次數。
                    // 這條路沒有交易的併發保證，不能悄悄地用。
                    if (fallbackCount > 0)
                      Text(
                        '交易讀取壞了，改用一般讀取＋批次寫入　$fallbackCount 次'
                        '${lastFallbackNote == null ? '' : '\n$lastFallbackNote'}',
                        style: const TextStyle(
                            fontSize: 11.5, color: AppColors.textFaint),
                      ),
                  ],
                ),
              ),
          ],
          const SectionLabel('訓練設定'),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '持有器材明細',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                const Text(
                  '動作庫的器材篩選預設帶入此處',
                  style: TextStyle(color: AppColors.textFaint, fontSize: 11),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final e in _equipment)
                      GestureDetector(
                        onTap: () => s.toggleEquipment(e),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 13,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: s.ownedEquipment.contains(e)
                                ? AppColors.accent
                                : AppColors.surfaceAlt,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            e,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: s.ownedEquipment.contains(e)
                                  ? AppColors.onAccent
                                  : AppColors.textDim,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const Divider(height: 26, color: AppColors.line),
                _Toggle(
                  label: 'AI 自動優化',
                  sub: '每 3 次訓練後自動調整長期課表範本',
                  value: s.aiAutoOptimize,
                  onChanged: (v) => s.setFlag(autoOptimize: v),
                ),
                const Divider(height: 26, color: AppColors.line),
                // 其後仍可於設定頁補填，補填時同樣產生「使用者已選擇偏好訓練時段」。
                _Row(
                  label: '偏好訓練時段',
                  value: s.preferredTimes.isEmpty
                      ? '未填'
                      : '${s.preferredTimes.filledDays} 天',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const PreferredTimesScreen(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SectionLabel('隱私', trailing: '兩者各自獨立'),
          Panel(
            child: Column(
              children: [
                _Toggle(
                  label: '六維能力值對外可見',
                  sub: '關閉後他人檢視你的個人檔案時不呈現能力值區塊',
                  value: s.abilityPublic,
                  onChanged: (v) => s.setFlag(ability: v),
                ),
                const Divider(height: 26, color: AppColors.line),
                _Toggle(
                  label: '綜合能力等級對外可見',
                  sub: '關閉六維但保留綜合，即只露出整體評價、隱藏各部位細節',
                  value: s.overallGradePublic,
                  onChanged: (v) => s.setFlag(overall: v),
                ),
                if (s.isInstructor) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: AppColors.gold.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      '你具備教官身分，上述設定不生效 —— 教官的六維能力值強制呈現。',
                      style: TextStyle(
                        color: AppColors.bronze,
                        fontSize: 11.5,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SectionLabel('帳號'),
          // 改名入口（暱稱重構階段五）。規格：「暱稱可於設定頁事後更新」。
          Panel(
            child: InkWell(
              onTap: () => _editNickname(context, s),
              child: Row(
                children: [
                  const Icon(Icons.badge_outlined,
                      size: 18, color: AppColors.textFaint),
                  const SizedBox(width: 11),
                  const Expanded(
                    child: Text('暱稱', style: TextStyle(fontSize: 13.5)),
                  ),
                  Text(s.displayName, style: T.caption()),
                  const Icon(Icons.chevron_right,
                      size: 18, color: AppColors.textFaint),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          // 沒有初始化 Firebase 就不顯示登出 —— 既有的 widget 測試
          // （畫面爬蟲會走過每一頁）沒有 Firebase，碰 FirebaseAuth.instance
          // 會當場丟例外。用 Firebase.apps 判斷是安全的：它是純查詢，不會拋。
          if (Firebase.apps.isNotEmpty) ...[
            Panel(
              child: InkWell(
                onTap: () => _logOut(context),
                child: const Row(
                  children: [
                    Icon(Icons.logout, size: 18, color: AppColors.textFaint),
                    SizedBox(width: 11),
                    Expanded(
                      child: Text('登出', style: TextStyle(fontSize: 13.5)),
                    ),
                    Icon(Icons.chevron_right,
                        size: 18, color: AppColors.textFaint),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          Panel(
            child: InkWell(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AccountDeleteScreen()),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.delete_outline,
                    size: 18,
                    color: AppColors.bronze,
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      delDays == null ? '申請刪除帳號' : '帳號待刪除　·　冷靜期剩餘 $delDays 天',
                      style: const TextStyle(
                        fontSize: 13.5,
                        color: AppColors.bronze,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: AppColors.textFaint,
                  ),
                ],
              ),
            ),
          ),
          if (s.isMember) ...[
            const SizedBox(height: 8),
            Panel(
              child: InkWell(
                onTap: () => showToast(context, '導向 Apple 原生訂閱管理面板'),
                child: const Row(
                  children: [
                    Icon(
                      Icons.card_membership,
                      size: 18,
                      color: AppColors.accent,
                    ),
                    SizedBox(width: 11),
                    Expanded(
                      child: Text('訂閱管理', style: TextStyle(fontSize: 13.5)),
                    ),
                    Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: AppColors.textFaint,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 使用者已填入電子郵件。空白即清空。
/// 把累積訓練次數校正成訓練歷史的筆數。
///
/// **這會讓數字變小，而規格明訂累積訓練次數單調遞增**（見
/// `AppState.reconcileWorkoutCount`）。所以按下去之前要把代價說清楚 ——
/// 被吃掉的真實場次會一起被抹掉，而教官初審的門檻是累積訓練次數 ≥50。
Future<void> _reconcile(BuildContext context, AppState s) async {
  final gap = s.totalWorkouts - s.history.length;
  final ok = await showAppDialog(
    context,
    title: '校正累積訓練次數？',
    message: '累積訓練次數會從 ${s.totalWorkouts} 降為 ${s.history.length}'
        '（少 $gap 次），累積訓練天數一併依訓練歷史重算。\n\n'
        '那 $gap 次裡有一部分是真的練過、只是紀錄被吃掉了 —— '
        '校正會把它們一起抹掉。教官初審的門檻是累積訓練次數 ≥ 50 次，'
        '進度會跟著往後退。\n\n'
        '這個動作無法復原。',
    confirmLabel: '確認校正',
    cancelLabel: '取消',
    destructive: true,
  );
  if (ok != true || !context.mounted) return;
  final removed = s.reconcileWorkoutCount();
  showToast(context, removed > 0 ? '已校正，扣掉 $removed 次' : '本來就相符');
}

/// 「N 天 M 小時」。重考鎖剩餘時間用。
String _dh(Duration d) =>
    d.inDays > 0 ? '${d.inDays} 天 ${d.inHours % 24} 小時' : '${d.inHours} 小時';

/// 補填生日。只在原本沒有時走得到這裡（見設定頁那一列）。
Future<void> _fillBirthday(BuildContext context, AppState s) async {
  final today = DateTime.now();
  final picked = await showDatePicker(
    context: context,
    // 預設落在一個合理的成年年份，而不是今天 —— 今天必然不合格，
    // 使用者一打開就看到一個會被擋掉的值。
    initialDate: DateTime(today.year - 25, today.month, today.day),
    firstDate: DateTime(today.year - 120),
    // 未滿 13 歲不得使用本服務，所以日期選擇器的上界就是 13 歲生日 ——
    // 讓他選得到一個必然被擋掉的日期再報錯，是多繞一圈。
    lastDate: DateTime(today.year - kMinAge, today.month, today.day),
    helpText: '選擇生日',
  );
  if (picked == null || !context.mounted) return;

  final ok = await showAppDialog(
    context,
    title: '確認生日',
    // 一次性的東西要說清楚是一次性的，在按下去之前。
    message: '${_ymd(picked)}\n\n'
        '生日決定年齡係數，填寫後不可自行修改（如需更正需聯繫客服）。'
        '確認無誤再送出。',
    confirmLabel: '確認送出',
    cancelLabel: '再看看',
  );
  if (ok != true || !context.mounted) return;

  final err = s.fillBirthday(picked);
  showToast(context, err ?? '已填入生日');
}

String _ymd(DateTime d) => '${d.year} / '
    '${d.month.toString().padLeft(2, '0')} / '
    '${d.day.toString().padLeft(2, '0')}';

/// 從值域裡挑一個。
///
/// 值域清單一律取 `domain/registration.dart` 的那幾個常數 ——
/// 註冊問卷、簽到頁的週期詢問、這一頁三處問的是同一件事，
/// 選項若各寫一份，遲早有一處漏掉新增的值。
Future<void> _pickOne(
  BuildContext context, {
  required String title,
  required List<String> options,
  required String current,
  required ValueChanged<String> onPick,
  String Function(String)? labelOf,
  /// 選填欄位的「清空」選項的鍵面文字。空值代表這一項是必填，沒有清空。
  String? allowNone,
}) async {
  final all = [if (allowNone != null) '', ...options];
  final picked = await showAppSheet<String>(
    context,
    title: title,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final o in all)
          ListRow(
            title: o.isEmpty ? allowNone! : (labelOf == null ? o : labelOf(o)),
            trailing: o == current
                ? const Icon(Icons.check_rounded,
                    size: Sz.iconDefault, color: C.accentDeep)
                : null,
            showDivider: o != all.last,
            onTap: () => Navigator.of(context).pop(o),
          ),
      ],
    ),
  );
  if (picked == null || picked == current || !context.mounted) return;
  onPick(picked);
  showToast(context, '已更新$title');
}

/// 改一個數字（身高、體重）。
///
/// 超出範圍就不給存 —— 身高 17 公分不是一個需要被尊重的輸入，
/// 而它會讓 BMI 與相對強度的計算全部失真。
Future<void> _editNumber(
  BuildContext context, {
  required String title,
  required String unit,
  required double current,
  required double min,
  required double max,
  required ValueChanged<double> onSave,
}) async {
  final s = AppScope.of(context);
  // 顯示單位可能是英制，而存的一律是公制 —— 進出都走同一組換算，
  // 不在這裡自己乘一次。
  final shown = s.metricUnits ? current : s.toDisplayUnit(current, title == '身高');
  final ctrl = TextEditingController(
      text: shown == shown.roundToDouble()
          ? shown.round().toString()
          : shown.toStringAsFixed(1));
  final ok = await showAppSheet<bool>(
    context,
    title: title,
    child: StatefulBuilder(
      builder: (context, setSheetState) {
        final v = double.tryParse(ctrl.text.trim());
        final metric =
            v == null ? null : (s.metricUnits ? v : s.toMetric(v, title == '身高'));
        final error = v == null
            ? '請輸入數字。'
            : (metric! < min || metric > max
                ? '$title須介於 ${min.round()}–${max.round()} '
                    '${title == '身高' ? 'cm' : 'kg'}。'
                : null);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: T.body(),
              onChanged: (_) => setSheetState(() {}),
              decoration: InputDecoration(
                isDense: true,
                suffixText: unit,
                errorText: error,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: S.base, vertical: S.md),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(R.control),
                ),
              ),
            ),
            const SizedBox(height: S.md),
            SizedBox(
              width: double.infinity,
              child: AppButton(
                label: '儲存',
                onPressed: error == null
                    ? () => Navigator.of(context).pop(true)
                    : null,
              ),
            ),
          ],
        );
      },
    ),
  );
  if (ok != true || !context.mounted) return;
  final v = double.parse(ctrl.text.trim());
  onSave(s.metricUnits ? v : s.toMetric(v, title == '身高'));
  showToast(context, '已更新$title');
}

/// 改名（暱稱重構階段五，使用者裁決 A：30 天一次）。
///
/// **冷卻期在打開之前就先講**，不是按下儲存才說 —— 讓人打完 12 個字
/// 才告訴他這個月不能改，是刁難不是驗證。
Future<void> _editNickname(BuildContext context, AppState s) async {
  final blocked = s.renameBlockedReason();
  if (blocked != null) {
    showToast(context, blocked);
    return;
  }
  final ctrl = TextEditingController(text: s.displayName);
  final ok = await showAppSheet<bool>(
    context,
    title: '修改暱稱',
    child: StatefulBuilder(
      builder: (context, setSheetState) {
        final v = ctrl.text.trim();
        final error = isValidNickname(v)
            ? (v == s.displayName ? '這就是你現在的暱稱。' : null)
            : '暱稱要 1–$kNicknameMaxLength 個字。';
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              style: T.body(),
              onChanged: (_) => setSheetState(() {}),
              decoration: InputDecoration(
                isDense: true,
                errorText: error,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: S.base, vertical: S.md),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(R.control),
                ),
              ),
            ),
            const SizedBox(height: S.sm),
            Text('改了之後，動態牆、隊伍、私訊、排行榜都會跟著改成新的名字。\n'
                '每 $kRenameCooldownDays 天只能改一次。',
                style: T.caption()),
            const SizedBox(height: S.md),
            SizedBox(
              width: double.infinity,
              child: AppButton(
                label: '儲存',
                onPressed: error == null
                    ? () => Navigator.of(context).pop(true)
                    : null,
              ),
            ),
          ],
        );
      },
    ),
  );
  if (ok != true || !context.mounted) return;
  final why = s.rename(ctrl.text);
  showToast(context, why ?? '暱稱已改成 ${s.displayName}');
}

Future<void> _editEmail(BuildContext context, AppState s) async {
  final ctrl = TextEditingController(text: s.email ?? '');
  final ok = await showAppSheet<bool>(
    context,
    title: '電子郵件（選填）',
    child: StatefulBuilder(
      builder: (context, setSheetState) {
        final error = AppState.isValidEmail(ctrl.text)
            ? null
            : '電子郵件格式不正確。';
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '填了才收得到處罰與申訴結果、帳號刪除排程兩類信件。'
              '不填一樣會收到推播與 App 內通知，不會少掉任何權益。',
              style: T.caption(),
            ),
            const SizedBox(height: S.md),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              style: T.body(),
              onChanged: (_) => setSheetState(() {}),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'name@example.com',
                hintStyle: T.body(color: C.textDisabled),
                errorText: error,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: S.base, vertical: S.md),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(R.control),
                ),
              ),
            ),
            const SizedBox(height: S.md),
            SizedBox(
              width: double.infinity,
              child: AppButton(
                label: ctrl.text.trim().isEmpty ? '清空並關閉' : '儲存',
                onPressed: error == null
                    ? () => Navigator.of(context).pop(true)
                    : null,
              ),
            ),
          ],
        );
      },
    ),
  );
  if (ok != true || !context.mounted) return;
  final err = s.setEmail(ctrl.text);
  showToast(context, err ?? (s.email == null ? '已清空電子郵件' : '已更新電子郵件'));
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final bool readOnly;
  final VoidCallback? onTap;
  const _Row({
    required this.label,
    required this.value,
    this.readOnly = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13.5))),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              color: readOnly ? AppColors.textFaint : AppColors.textDim,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 6),
          Icon(
            readOnly ? Icons.lock_outline : Icons.chevron_right,
            size: 15,
            color: AppColors.textFaint,
          ),
        ],
      ),
    ),
  );
}

class _Toggle extends StatelessWidget {
  final String label;
  final String sub;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _Toggle({
    required this.label,
    required this.sub,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              sub,
              style: const TextStyle(
                color: AppColors.textFaint,
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
      AppSwitch(value: value, onChanged: onChanged),
    ],
  );
}
