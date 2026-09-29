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
  <p><strong>這批題目由 AI 起草，尚未經過體適能專業人士審閱。</strong>
     我們需要您判斷的是：這些題目與標示的正解，是否符合您的專業認知；
     有沒有哪一題的「正解」其實有爭議，或有更該問而沒問的。</p>
</div>

<div class="box">
  <p><strong>測驗怎麼計分</strong></p>
  <p>每位應試者自題庫<strong>隨機抽取</strong> $mcCount 題選擇題（不固定題目，
     避免題庫外流後變成背答案），加上 $saCount 題簡答題。</p>
  <p>及格採<strong>雙門檻</strong>：選擇題答對率須達 <strong>$mcPass%</strong>，
     <strong>且</strong>簡答題須由管理員人工審核全數通過。
     不採總分制 —— 總分制下選擇題滿分的人可以簡答全錯仍然及格，
     人工審核就形同虛設。</p>
</div>

<div class="box">
  <p><strong>出題方向（這是我們的判斷，也請您一併評估）</strong></p>
  <p>題目刻意集中在<strong>安全、轉介時機與執業範圍</strong>
     —— 那是教官做錯會實際傷到學員的地方。</p>
  <p>訓練處方的細節（組數次數的最適配置等）<strong>刻意不出題</strong>：
     那有學派差異，出成單選題只會考出「有沒有背過我們這一套」，
     而不是「懂不懂」。<strong>如果您認為這個取捨不對，請直接說。</strong></p>
</div>

<div class="box">
  <p><strong>怎麼給意見</strong></p>
  <p>每題下方留了空白欄。可以直接在紙上寫，或在任何地方寫下「題號 + 意見」
     都可以（例如「mc07 正解應為 3」）。<strong>題號在每題標題的右側。</strong></p>
  <p>覺得沒問題的題目不必寫任何東西。</p>
</div>
''');

  b.writeln('<h2>一、選擇題（題庫共 ${mc.length} 題，每份考卷抽 $mcCount 題）</h2>');
  for (var i = 0; i < mc.length; i++) {
    final q = mc[i];
    b.writeln('<div class="q">');
    b.writeln('<p class="qh">${i + 1}. ${_e(q.text)}'
        '<span class="qid">［${_e(q.id)}］</span></p>');
    b.writeln('<ol class="opt" type="A">');
    for (var j = 0; j < q.options.length; j++) {
      final cls = j == q.answerIndex ? ' class="ans"' : '';
      b.writeln('<li$cls>${_e(q.options[j])}</li>');
    }
    b.writeln('</ol>');
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
    b.writeln('<div class="review">覆核意見／什麼樣的回答該算不通過'
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
