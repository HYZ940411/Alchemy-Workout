import 'dart:convert';
import 'dart:io';

import 'package:fitness_app/domain/platform_config.dart';
import 'package:fitness_app/domain/task_pool.dart';
import 'package:fitness_app/mock/mock_extra.dart';

/// 把教官測驗題庫匯出成一份**可以交給體適能專業人士覆核**的文件。
///
/// 覆核這件事是待辦清單裡唯一的硬性上線阻擋（`教官測驗題庫需由具備體適能
/// 專業的人覆核`）—— 那份題庫決定誰能帶別人訓練，而起草的是 Claude。
///
/// **為什麼要一支程式而不是手抄一份**：手抄的那一份從抄完的那一刻起就
/// 開始跟程式碼分岔，而覆核意見會回頭改程式碼。從 [buildExamBank] 直接
/// 匯出，看的人與跑的人永遠是同一份題目。及格標準也一樣，取自
/// [PlatformConfig] 的 `exam` 群組，不另寫一次。
///
/// 輸出 HTML（非 Markdown）的理由：覆核的人要的是**列印得出來、標得了
/// 意見**的東西，而 HTML 到 PDF 在這台機器上不必裝任何東西
/// （見 `tools/export_exam_bank.sh`）。
///
/// 用法：
///   cd fitness-app
///   dart run tools/export_exam_bank.dart [輸出路徑]   # 預設 build/exam_bank.html
void main(List<String> args) {
  final bank = buildExamBank();
  final mc = bank.where((q) => q.type == ExamQuestionType.multipleChoice).toList();
  final sa = bank.where((q) => q.type == ExamQuestionType.shortAnswer).toList();

  // 用 `i()` 而非 `group('exam').values` —— 後者是 num，而題數與百分比
  // 在畫面上一律是整數（沿用管理員編輯路徑的取整慣例）。
  final mcCount = platformConfig.i('exam', 'mcCount');
  final saCount = platformConfig.i('exam', 'saCount');
  final mcPass = platformConfig.i('exam', 'mcPass');

  final path = args.isNotEmpty ? args.first : 'build/exam_bank.html';
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(_html(mc, sa, mcCount, saCount, mcPass));

  stdout.writeln('教官測驗題庫已匯出 → $path');
  stdout.writeln('  選擇題：${mc.length} 題（每份考卷抽 $mcCount 題）');
  stdout.writeln('  簡答題：${sa.length} 題（每份考卷抽 $saCount 題）');

  // 題庫與考卷一樣大的時候，「隨機抽取」抽的是全部 —— 每個人拿到同一份
  // 考卷，只是順序不同。那正是 `drawExamPaper` 的註解說要避免的情況，
  // 而它避不掉：那是題數的問題，不是程式的問題。印出來才有人會發現。
  if (mc.length <= mcCount) {
    stdout.writeln('');
    stdout.writeln('⚠️ 選擇題題庫 ${mc.length} 題 = 考卷 $mcCount 題 —— '
        '「隨機抽取、題目不固定」目前並不成立。');
  }
  if (sa.length <= saCount) {
    stdout.writeln('⚠️ 簡答題題庫 ${sa.length} 題 = 考卷 $saCount 題 —— 同上。');
  }
}

/// HTML escape。題目裡有引號與角括號的話不跳脫會壞版。
String _e(String s) => const HtmlEscape().convert(s);

String _html(
  List<ExamQuestion> mc,
  List<ExamQuestion> sa,
  int mcCount,
  int saCount,
  int mcPass,
) {
  final b = StringBuffer();
  b.writeln('''<!DOCTYPE html>
<html lang="zh-Hant">
<head>
<meta charset="utf-8">
<title>健金術 教官測驗題庫 覆核用</title>
<style>
  @page { size: A4; margin: 18mm 16mm; }
  body {
    font-family: "PingFang TC", "Heiti TC", "Noto Sans CJK TC", sans-serif;
    font-size: 11.5pt; line-height: 1.75; color: #1a1a1a; max-width: 760px;
    margin: 0 auto; padding: 0 16px;
  }
  h1 { font-size: 20pt; margin: 0 0 4px; }
  h2 { font-size: 14pt; margin: 28px 0 10px; padding-bottom: 6px;
       border-bottom: 2px solid #333; }
  .sub { color: #555; margin: 0 0 20px; font-size: 10.5pt; }
  .box { border: 1px solid #bbb; background: #f7f7f7; padding: 12px 16px;
         margin: 16px 0; font-size: 10.5pt; }
  .box p { margin: 6px 0; }
  .q { margin: 0 0 18px; padding: 12px 14px; border: 1px solid #ddd;
       page-break-inside: avoid; }
  .qh { font-weight: 600; margin: 0 0 8px; }
  .qid { color: #888; font-weight: 400; font-size: 9.5pt; margin-left: 6px; }
  ol.opt { margin: 6px 0 10px; padding-left: 22px; }
  ol.opt li { margin: 2px 0; }
  li.ans { font-weight: 700; }
  li.ans::after { content: "　← 本題正解"; font-weight: 400; color: #0a7; font-size: 10pt; }
  .review { margin-top: 10px; border-top: 1px dashed #ccc; padding-top: 8px;
            font-size: 10pt; color: #666; }
  .review .line { border-bottom: 1px solid #ddd; height: 20px; margin-top: 6px; }
  .note { font-size: 10pt; color: #666; margin: 6px 0 0; }
  strong.warn { color: #b00; }
  .must { background: #b00; color: #fff; font-size: 9pt; padding: 1px 6px;
          border-radius: 3px; margin-left: 8px; vertical-align: 2px; }
  .why { font-size: 9.5pt; color: #444; background: #f4f4f4; margin: 8px 0 0;
         padding: 6px 10px; border-left: 3px solid #bbb; line-height: 1.6; }
  .why.fail { border-left-color: #b00; }
  table.chg { border-collapse: collapse; width: 100%; font-size: 9.5pt;
              margin: 12px 0; }
  table.chg th, table.chg td { border: 1px solid #ccc; padding: 5px 8px;
                               text-align: left; vertical-align: top; }
  table.chg th { background: #eee; }
  table.chg td.del { color: #b00; font-weight: 600; }
</style>
</head>
<body>

<h1>健金術　教官測驗題庫</h1>
<p class="sub">覆核用文件　·　產生日期 ${DateTime.now().toIso8601String().substring(0, 10)}　·　本文件由程式自題庫直接匯出</p>

<div class="box">
  <p><strong>請您協助覆核的是什麼</strong></p>
  <p>健金術是一款訓練紀錄 App。使用者通過這份測驗之後，就能成為「教官」，
     替其他使用者解答訓練問題、指派訓練任務。<strong class="warn">也就是說，
     這份題庫決定了誰有資格帶別人訓練。</strong></p>
  <p><strong>這是第二版。</strong>第一版由 AI 起草，經覆核指出五項缺陷後
     全面改寫：20 題的正解全部是 B、錯誤選項誇張到沒有人會選、題庫剛好
     等於考卷（等於沒在隨機抽題）、宣稱不考處方細節卻有四題在考、
     以及缺少數個高風險主題。</p>
  <p>我們需要您判斷的是：這些題目與標示的正解，是否符合您的專業認知；
     有沒有哪一題的「正解」其實有爭議，或有更該問而沒問的。
     <strong>標著「建議由專業人士確認」的命題理由，是我們對正解沒有十足
     把握的題目，請優先看那幾題。</strong></p>
</div>

<div class="box">
  <p><strong>測驗怎麼計分</strong></p>
  <p>每位應試者自題庫<strong>隨機抽取</strong> $mcCount 題選擇題（不固定題目，
     避免題庫外流後變成背答案），加上 $saCount 題簡答題。</p>
  <p>及格採<strong>三重門檻</strong>：選擇題答對率須達 <strong>$mcPass%</strong>、
     <strong>標示「必答」的題目不得答錯任何一題</strong>、
     且簡答題須由管理員人工審核全數通過。</p>
  <p>不採總分制 —— 總分制下選擇題滿分的人可以簡答全錯仍然及格。
     而必答題之所以要另立門檻，是因為百分比擋不住它們：
     $mcCount 題錯 4 題仍然達標，而那 4 題可能正好是「胸痛先休息一下」
     「未成年可以私下約」。<strong>必答題一定會出現在每一份考卷上</strong>，
     否則「答錯即不及格」的前提是那一題有被問到。</p>
</div>

<div class="box">
  <p><strong>出題方向（這是我們的判斷，也請您一併評估）</strong></p>
  <p>集中在<strong>安全、轉介時機、執業範圍與互動界線</strong>四類
     —— 那是教官做錯會實際傷到學員的地方。</p>
  <p>訓練處方的細節（組數次數、休息秒數、頻率、預備次數）<strong>一律不出成
     單選題</strong>：那有學派差異，出成單選題只會考出「有沒有背過我們這一套」，
     而不是「懂不懂」。要考只考背後的原則，不考具體數值。
     <strong>如果您認為這個取捨不對，請直接說。</strong></p>
  <p><strong>錯誤選項刻意寫成「聽起來合理、實務上真的有教練這樣做、
     但不正確」。</strong>如果您覺得某個誤答其實是可以接受的做法，
     那正是我們最需要知道的事。</p>
</div>

<div class="box">
  <p><strong>怎麼給意見</strong></p>
  <p>每題下方留了空白欄。可以直接在紙上寫，或在任何地方寫下「題號 + 意見」
     都可以（例如「mc07 正解應為 C」）。<strong>題號在每題標題的右側。</strong></p>
  <p>覺得沒問題的題目不必寫任何東西。若時間有限，
     <strong>請優先看標著「必答」的那幾題</strong>
     —— 它們答錯就直接不及格，所以正解一旦有爭議，代價最大。</p>
</div>
''');

  b.writeln('<h2>一、選擇題（題庫共 ${mc.length} 題，每份考卷抽 $mcCount 題）</h2>');
  for (var i = 0; i < mc.length; i++) {
    final q = mc[i];
    b.writeln('<div class="q">');
    b.writeln('<p class="qh">${i + 1}. ${_e(q.text)}'
        '${q.mustPass ? '<span class="must">必答</span>' : ''}'
        '<span class="qid">［${_e(q.id)}］</span></p>');
    b.writeln('<ol class="opt" type="A">');
    for (var j = 0; j < q.options.length; j++) {
      final cls = j == q.answerIndex ? ' class="ans"' : '';
      b.writeln('<li$cls>${_e(q.options[j])}</li>');
    }
    b.writeln('</ol>');
    if (q.rationale.trim().isNotEmpty) {
      b.writeln('<p class="why"><strong>命題理由</strong>：'
          '${_e(q.rationale)}</p>');
    }
    b.writeln('<div class="review">覆核意見<div class="line"></div></div>');
    b.writeln('</div>');
  }

  b.writeln('<h2>二、簡答題（題庫共 ${sa.length} 題，每份考卷抽 $saCount 題）</h2>');
  b.writeln('<p class="note">簡答題<strong>沒有標準答案</strong>，'
      '由管理員閱讀後人工判定通過與否。'
      '請您一併評估：這些題目問得出「這個人能不能安全地帶別人」嗎？'
      '另外，我們也想請教您<strong>什麼樣的回答應該算不通過</strong>。</p>');
  for (var i = 0; i < sa.length; i++) {
    final q = sa[i];
    b.writeln('<div class="q">');
    b.writeln('<p class="qh">${i + 1}. ${_e(q.text)}'
        '<span class="qid">［${_e(q.id)}］</span></p>');
    if (q.rubricPass.trim().isNotEmpty) {
      b.writeln('<p class="why"><strong>通過要素</strong>：'
          '${_e(q.rubricPass)}</p>');
    }
    if (q.rubricFail.trim().isNotEmpty) {
      b.writeln('<p class="why fail"><strong>直接不通過</strong>：'
          '${_e(q.rubricFail)}</p>');
    }
    if (q.followUp.trim().isNotEmpty) {
      b.writeln('<p class="why"><strong>追問範例</strong>：'
          '${_e(q.followUp)}</p>');
    }
    b.writeln('<div class="review">覆核意見（細則是否足以讓兩位審核者'
        '得到同一個結果？）'
        '<div class="line"></div><div class="line"></div>'
        '<div class="line"></div></div>');
    b.writeln('</div>');
  }

  b.writeln('<h2>三、整體意見</h2>');

  // 題庫大小 = 考卷大小的時候，「隨機抽取」抽的是全部。設計上想要的
  // 「題目不固定」並不成立，而這件事只有補題目才解得掉 —— 正好是眼前
  // 這位專業人士做得到、而我們做不到的事。所以它放在覆核文件裡，
  // 不是只記在我們自己的待辦上。
  if (mc.length <= mcCount) {
    b.writeln('''
<div class="q">
  <p class="qh"><strong class="warn">最想請您幫忙的一題：能不能再多出幾題？</strong></p>
  <p class="note">目前選擇題題庫是 ${mc.length} 題，而每份考卷要抽 $mcCount 題
     —— <strong>抽的是全部</strong>。也就是說每位應試者拿到的是同樣的
     ${mc.length} 題，只有順序不同，題目一旦外流就會變成背答案。</p>
  <p class="note">要讓「隨機抽取」真的有意義，題庫至少得比考卷大上一截
     （例如 40 題以上）。<strong>如果您能提供幾題方向相近的題目與正解，
     那會是這份覆核最有價值的產出。</strong>寫在下面或另紙皆可。</p>
  <div class="review"><div class="line"></div><div class="line"></div>
  <div class="line"></div><div class="line"></div><div class="line"></div>
  <div class="line"></div></div>
</div>''');
  }

  b.writeln('''
<div class="q">
  <p class="qh">有沒有「該考而沒考」的題目？</p>
  <div class="review"><div class="line"></div><div class="line"></div>
  <div class="line"></div><div class="line"></div></div>
</div>
<div class="q">
  <p class="qh">以這份題庫作為「可以帶別人訓練」的門檻，您認為足夠嗎？
     若不足夠，還需要什麼？（例如實體證照、實作評量）</p>
  <div class="review"><div class="line"></div><div class="line"></div>
  <div class="line"></div><div class="line"></div></div>
</div>

<h2>四、這一版對第一版做了什麼</h2>
<table class="chg">
  <tr><th>原題號</th><th>處理</th><th>理由</th></tr>
  <tr><td>mc01</td><td>改寫</td><td>原正解指定「臀中肌啟動」，屬流行說法且證據不一致；改為不指定特定肌群</td></tr>
  <tr><td>mc02</td><td>保留（重寫選項）</td><td>題意正確，但三個誤答原本誇張到沒有人會選</td></tr>
  <tr><td class="del">mc03</td><td class="del">刪除</td><td>考「新手每週幾次」—— 具體處方數值，與出題原則矛盾</td></tr>
  <tr><td>mc04</td><td>改寫</td><td>原正解寫死每週 0.5–1% 的速率；改為聚焦「這個期限從哪來」</td></tr>
  <tr><td>mc05</td><td>保留（重寫選項）</td><td>考的是漸進超負荷的原則而非數值，符合出題方向</td></tr>
  <tr><td>mc06</td><td>保留（重寫選項）</td><td>同 mc02</td></tr>
  <tr><td>mc07</td><td>改寫</td><td>合併原 mc18 的伸展時機；靜態伸展對表現的影響有學派討論，不以它為唯一判準</td></tr>
  <tr><td>mc08</td><td>保留（重寫選項）</td><td>原誤答含「加咖啡因硬上」「取消他的會員資格」</td></tr>
  <tr><td>mc09</td><td>保留（重寫選項）</td><td>局部瘦身迷思，專業共識明確</td></tr>
  <tr><td class="del">mc10</td><td class="del">刪除</td><td>考預備次數與力竭的配置 —— 處方細節，學派差異大</td></tr>
  <tr><td>mc11</td><td>改寫</td><td>原正解「立即停止該組」有歧義：槓已離地時中途放下可能更危險</td></tr>
  <tr><td class="del">mc12</td><td class="del">刪除</td><td>考組間休息秒數 —— 處方細節</td></tr>
  <tr><td>mc13</td><td>保留（重寫選項）</td><td>高血壓轉介，題意正確</td></tr>
  <tr><td>mc14</td><td>保留（重寫選項）</td><td>痠痛與成效脫鉤，專業共識明確</td></tr>
  <tr><td>mc15</td><td>保留（重寫選項）</td><td>測「會不會把紀錄當成事實」，與安全有關</td></tr>
  <tr><td>mc16</td><td>保留（重寫選項）</td><td>未成年訓練；互動界線另由 mc24–mc26 補齊</td></tr>
  <tr><td>mc17</td><td>保留（重寫選項）</td><td>列為必答題；正解改為強調「不改善就求援」的門檻</td></tr>
  <tr><td class="del">mc18</td><td class="del">併入 mc07</td><td>與 mc07 高度重疊，且靜態伸展的效果有爭議</td></tr>
  <tr><td>mc19</td><td>保留（重寫選項）</td><td>測「會不會先檢討自己的安排」</td></tr>
  <tr><td class="del">mc20</td><td class="del">拆解</td><td>執業範圍只考一題太薄，拆成醫療（mc39–mc41）與營養（mc42–mc44）兩條界線</td></tr>
  <tr><td>mc21–mc50</td><td>新增</td><td>補六個高風險主題：急症辨識、未成年互動界線、飲食失調、身體評論、心理警訊、利益衝突</td></tr>
  <tr><td>sa01–sa03</td><td>改寫</td><td>原題無評分細則，人工審核等於各憑印象；三題全部補上通過要素、不通過條件與追問範例</td></tr>
  <tr><td>sa04–sa09</td><td>新增</td><td>擴充至 9 題；其中 sa06、sa07 綁定應試者自己的訓練紀錄</td></tr>
</table>

<h2>五、這份測驗仍然驗不到的事</h2>
<div class="box">
  <p><strong>以下是我們認為即使改完也無法靠這份測驗把關的，列在這裡是為了
     不讓它們被「已經考過試了」蓋過去。</strong>也請您評估是否還有遺漏。</p>
  <p><strong>1. 實作能力。</strong>會不會看動作、糾得動姿勢、在現場反應得過來
     —— 這份測驗全部驗不到。它只驗得到「知不知道該怎麼做」。</p>
  <p><strong>2. 代答。</strong>sa06 與 sa07 綁定應試者自己的訓練紀錄，
     管理員可以與帳號對照，但其餘題目仍然可以請人代寫或由 AI 產生。
     追問範例是目前唯一的辨識手段，而它需要管理員真的去追問。</p>
  <p><strong>3. 通過之後的行為。</strong>測驗量的是通過那一刻的認知。
     一個人答對「不得索取未成年學員的照片」，不代表他不會做。
     這一項應由產品機制承擔（見下）。</p>
  <p><strong>4. 人工審核的一致性。</strong>我們寫了評分細則，但兩位審核者
     是否真的會得到同一個結果，只有實際跑過才知道。
     建議上線初期讓同一份答案由兩人各自評一次，比對結果。</p>
  <p><strong>5. 題庫外流。</strong>45 題抽 20 題確實讓背答案變難，
     但沒有讓它不可能。必答題固定入卷這件事更是如此 ——
     它是安全上的必要，同時是外流時的弱點。</p>
</div>
<div class="box">
  <p><strong>建議改由產品機制承擔的部分</strong></p>
  <p>這些事情靠考試擋不住，但靠系統設計可以：</p>
  <p>· <strong>平台內溝通與紀錄保存</strong> —— 讓私下聯繫不是選項，
     而不是靠教官自律。</p>
  <p>· <strong>未成年帳號的結構性限制</strong> —— 例如禁止傳送圖片給教官、
     監護人可檢視互動紀錄。規則寫在程式裡，比寫在考卷上可靠。</p>
  <p>· <strong>學員端的檢舉與評分</strong> —— 通過之後的行為要有回饋路徑，
     而且那個路徑要真的有人處理。</p>
  <p>· <strong>資格的有效期與複訓</strong> —— 目前通過就是永久。
     指引會更新，而通過三年前的測驗不代表現在還知道。</p>
</div>

<h2>覆核人資料</h2>
<div class="q">
  <p>姓名：<span style="display:inline-block;width:200px;border-bottom:1px solid #999">　</span></p>
  <p>專業背景／證照：<span style="display:inline-block;width:320px;border-bottom:1px solid #999">　</span></p>
  <p>日期：<span style="display:inline-block;width:200px;border-bottom:1px solid #999">　</span></p>
</div>

</body>
</html>
''');
  return b.toString();
}
