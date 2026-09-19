import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../domain/ability.dart';
import '../../domain/platform_config.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

/// 帳號刪除流程
///
/// 納入軟體邊界不是選擇：App Store 自 2022 年起強制要求 App 內提供帳號刪除，
/// 而本平台的訂閱與儲值皆走 App Store。
///
/// 兩件事在這一頁必須講清楚，都是 Apple 的明文要求：
/// ① 刪除需時多久（冷靜期 30 天須於申請當下告知）；
/// ② 哪些資料會**暫時保留**、保留到何時（處理中的檢舉／申訴、已付款未出貨的收貨資訊）。
///
/// 刪除的是整筆帳號紀錄，**含使用者產生、已分享給他人的內容**（貼文、留言）——
/// 「保留但作者匿名」不符合要求，故本頁不提供該選項。
class AccountDeleteScreen extends StatefulWidget {
  const AccountDeleteScreen({super.key});

  @override
  State<AccountDeleteScreen> createState() => _AccountDeleteScreenState();
}

class _AccountDeleteScreenState extends State<AccountDeleteScreen> {
  bool understood = false;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return s.pendingDeletion ? _cooling(context, s) : _apply(context, s);
  }

  // -------------------------------------------------------------------------
  // 待刪除：帳號停用，可登入但只剩取消申請這一件事
  // -------------------------------------------------------------------------
  Widget _cooling(BuildContext context, AppState s) {
    final left = s.deletionDaysLeft!;
    return Scaffold(
      backgroundColor: C.bgPage,
      appBar: AppBar(title: const Text('帳號待刪除')),
      body: ListView(
        padding:
            const EdgeInsets.fromLTRB(S.base, S.base, S.base, S.scrollBottom),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.hourglass_bottom_rounded,
                        size: Sz.iconDense, color: C.statusError),
                    const SizedBox(width: S.sm),
                    Text('冷靜期剩餘 $left 天',
                        style: T.h3(color: C.statusError)),
                  ],
                ),
                const SizedBox(height: S.sm),
                Text(
                  '帳號目前為停用狀態：你登得進來，但只剩「取消刪除帳號申請」可以用。'
                  '冷靜期屆滿後由排程執行刪除，屆時資料永久移除。',
                  style: T.caption(),
                ),
              ],
            ),
          ),
          const SectionTitle('冷靜期間的計時', trailing: '一律照常'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final t in const [
                  '能力值退步（每 240 小時）',
                  '連續訓練天數歸零（36 小時）',
                  '簽到連續天數中斷（36 小時）',
                  '每日任務重置',
                  '排行榜週期結算',
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: S.sm),
                    child: Row(
                      children: [
                        Expanded(child: Text(t, style: T.body())),
                        TagBadge('照常'),
                      ],
                    ),
                  ),
                Text(
                  '取消申請時不重設任何計時基準、也不補償期間的損失。',
                  style: T.caption(),
                ),
              ],
            ),
          ),
          const SizedBox(height: S.lg),
          AppButton(
            label: '取消刪除帳號申請',
            onPressed: () {
              s.cancelDeletion();
              showToast(context, '已取消，帳號回復正常');
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 申請
  // -------------------------------------------------------------------------
  Widget _apply(BuildContext context, AppState s) {
    final days = kDeletionCoolingDays;
    final deleted = <String>[
      '訓練紀錄 ${s.totalWorkouts} 次與所有組紀錄',
      '六維能力值（綜合 ${overallGrade(s.points)}）、日快照與所有成就',
      '階級 ${s.rank}、經驗值 ${s.totalExp}、金幣 ${s.coins}、'
          'AI 點數 ${s.aiTotal}',
      '貼文、留言與私訊',
      '團隊與師徒關係',
      '帳密、第三方帳號綁定、生日、性別、身高、體重、電子郵件',
    ];

    return Scaffold(
      backgroundColor: C.bgPage,
      appBar: AppBar(title: const Text('申請刪除帳號')),
      body: ListView(
        padding:
            const EdgeInsets.fromLTRB(S.base, S.base, S.base, S.scrollBottom),
        children: [
          AppCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline,
                    size: Sz.iconDefault, color: C.statusError),
                const SizedBox(width: S.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('刪除後有 $days 天冷靜期', style: T.h3()),
                      const SizedBox(height: S.xs),
                      Text(
                        '期間內重新登入即可取消刪除，$days 天後資料永久移除，無法復原。',
                        style: T.caption(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SectionTitle('會被刪除的資料'),
          ListGroup(rows: [
            for (var i = 0; i < deleted.length; i++)
              ListRow(
                title: deleted[i],
                showDivider: i != deleted.length - 1,
              ),
          ]),

          // Apple：「若法規要求保留部分資料，須讓使用者知道」。
          const SectionTitle('會暫時保留的資料', trailing: '到期即一併清除'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Keep(
                  title: '處理中的檢舉／申訴所需的最小證據',
                  detail: '保留至該案件結案，結案後一併清除。',
                ),
                const SizedBox(height: S.md),
                _Keep(
                  title: '已付款未出貨的實體訂單收貨資訊',
                  detail: '保留至出貨完成，出貨後一併清除。'
                      '未付款的訂單會在刪除時自動取消並釋放庫存。',
                ),
              ],
            ),
          ),

          if (s.isMember) ...[
            const SectionTitle('生效中的會員訂閱'),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '刪除帳號不會自動取消訂閱，Apple 會繼續扣款。'
                    '平台沒有取消訂閱的權限，取消須由你本人在訂閱管理裡按下。',
                    style: T.body(),
                  ),
                  const SizedBox(height: S.md),
                  AppButton(
                    label: '前往訂閱管理',
                    kind: BtnKind.secondary,
                    onPressed: () =>
                        showToast(context, '導向 Apple 原生訂閱管理面板'),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: S.base),
          AppCard(
            child: Row(
              children: [
                AppCheckbox(
                  value: understood,
                  onChanged: (v) => setState(() => understood = v),
                ),
                const SizedBox(width: S.sm),
                Expanded(
                  child: Text('我了解刪除後資料無法復原', style: T.body()),
                ),
              ],
            ),
          ),
          const SizedBox(height: S.sm),
          Text(
            '刪除後可以用同一支門號重新註冊，但一律視為全新使用者：'
            '新的帳號、重新取得註冊獎勵，原本的能力值與訓練歷史不會回來。',
            style: T.caption(),
          ),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: EdgeInsets.fromLTRB(S.base, S.md, S.base,
            MediaQuery.of(context).padding.bottom + S.base),
        // bottomNavigationBar 拿到的是寬鬆約束：直接放 width:infinity 的
        // SizedBox 會把整個 body 擠成 0 高。用 min 的 Column 收住。
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              // R-23：破壞性動作用次要樣式，不給它主 CTA 的份量。
              child: AppButton(
                label: '申請刪除帳號',
                kind: BtnKind.secondary,
                onPressed: understood ? () => _confirm(context, s) : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirm(BuildContext context, AppState s) async {
    final ok = await showAppDialog(
      context,
      title: '確認申請刪除帳號？',
      message: '帳號會立刻停用，$kDeletionCoolingDays 天後永久刪除。'
          '期間內重新登入即可取消。',
      confirmLabel: '申請刪除',
      destructive: true,
    );
    if (ok != true || !context.mounted) return;
    s.requestDeletion();
    showToast(context, '已申請刪除，冷靜期 $kDeletionCoolingDays 天');
    setState(() {});
  }
}

class _Keep extends StatelessWidget {
  final String title;
  final String detail;
  const _Keep({required this.title, required this.detail});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: T.body(weight: FontWeight.w600)),
          const SizedBox(height: S.xs),
          Text(detail, style: T.caption()),
        ],
      );
}
