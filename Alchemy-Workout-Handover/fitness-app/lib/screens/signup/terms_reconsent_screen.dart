import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../domain/registration.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

/// 條款改版後，既有使用者於下次登入時重新同意。
///
/// 規格三處都寫著這件事（〈註冊流程〉、〈01_Command清單〉、
/// 〈02_Aggregate定義〉的「已同意條款版本」），但在 2026-09-24 之前
/// **使用者 Aggregate 根本沒有那個欄位** —— 2026-09-18 條文由 v3.2 升為
/// v4.0，沒有任何既有使用者被要求重新同意。條款本身寫明了這件事會發生，
/// 所以那是一個對外承諾了、實際沒做的功能（PROGRESS.md 第 5 節 0b）。
///
/// ## 為什麼沒有「不同意」
///
/// **規格沒寫拒絕的後果。** 註冊時不同意就不能註冊，那是自明的；
/// 但既有使用者拒絕了要怎麼辦（登出？轉唯讀？保留到期限？）三份文件
/// 一個字都沒提。這裡只實作規格寫到的部分 —— 跳出來要求同意 ——
/// 不替規格補一個它沒有的分支。要補的話那是產品與法務的決定。
class TermsReconsentScreen extends StatefulWidget {
  /// 同意之後要做什麼。呼叫端負責把畫面換掉。
  final VoidCallback onAgreed;
  const TermsReconsentScreen({super.key, required this.onAgreed});

  @override
  State<TermsReconsentScreen> createState() => _TermsReconsentScreenState();
}

class _TermsReconsentScreenState extends State<TermsReconsentScreen> {
  bool checked = false;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return Scaffold(
      backgroundColor: C.bgPage,
      appBar: AppBar(title: const Text('服務條款已更新')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(S.base),
              children: [
                Text('服務條款與隱私權政策　$kTermsVersion', style: T.h3()),
                const SizedBox(height: S.sm),
                Text(
                  // 講清楚為什麼突然跳出來 —— 不說的話，使用者以為
                  // 自己被登出了、或是 App 壞了。
                  '條款內容有更新，請再看一次並確認。'
                  '${s.agreedTermsVersion == null ? '' : '你先前同意的是 ${s.agreedTermsVersion}。'}',
                  style: T.caption(),
                ),
                const SizedBox(height: S.base),
                // 逐節一張卡，與註冊流程那一頁同一套 —— 近兩千字擠成一段
                // 沒有人會讀，那個勾選就成了純粹的形式。
                for (final (heading, body) in kTermsSections) ...[
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (heading.isNotEmpty) ...[
                          Text(heading, style: T.body(weight: FontWeight.w700)),
                          const SizedBox(height: S.sm),
                        ],
                        Text(body, style: T.body()),
                      ],
                    ),
                  ),
                  const SizedBox(height: S.md),
                ],
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(S.base),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      AppSwitch(
                        value: checked,
                        onChanged: (v) => setState(() => checked = v),
                      ),
                      const SizedBox(width: S.md),
                      Expanded(
                        child: Text('我已閱讀並同意服務條款', style: T.body()),
                      ),
                    ],
                  ),
                  const SizedBox(height: S.md),
                  AppButton(
                    label: '同意',
                    onPressed: checked
                        ? () {
                            s.agreeTerms();
                            widget.onAgreed();
                          }
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
