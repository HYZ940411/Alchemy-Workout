import 'package:flutter/material.dart';

/// 語意色票（UI 設計規格書 §4.1）
///
/// 【必須】畫面只引用語意名稱，不直接寫色碼。
class C {
  // 背景
  static const bgPage = Color(0xFFF9F9F9);
  static const bgSurface = Color(0xFFFFFFFF);

  // 文字
  static const textPrimary = Color(0xFF1C1C1E);
  static const textSecondary = Color(0xFF6E6E73);
  static const textOnAccent = Color(0xFF1C1C1E); // 橘黃、薄荷底上的文字
  static const textOnDark = Color(0xFFFFFFFF);
  static const textDisabled = Color(0xFFA1A1A1);

  // 線條
  static const lineDivider = Color(0xFFE5E5EA);
  static const lineTrack = Color(0xFFE5E5EA);

  // 動作
  static const actionPrimary = Color(0xFFF5A623);
  static const actionPrimaryPressed = Color(0xFFE49B23);
  static const actionPrimaryDisabled = Color(0xFFF7D8A3);
  /// v0.6：由近黑 #1C1C1E 改為品牌深藍 —— 全案除 CTA 外幾乎只剩金色，視覺疲勞。
  /// 對 bg/surface 13.10:1。
  static const actionOutline = Color(0xFF16324F);

  /// 品牌深藍，供大面積或強調用（與 actionOutline 同值，語意不同）。
  static const accentDeep = Color(0xFF16324F);

  /// v0.8：輔助色已移除（案 2 裁決 —— 依設計稿，資訊沿用中性色）。
  /// 保留別名指向 text/secondary，使既有呼叫端不必逐一改寫；
  /// 語意上「資訊」不再有專屬顏色，一律以中性色 ＋ 圖示表達。
  static const accentInfo = textSecondary;

  /// 等級色階（v0.8 —— 使用者裁決「甲：一眼認得出的紅橙黃綠青藍」）
  ///
  /// 色相順序由使用者指定：S 紅 → A 橙 → B 黃 → C 綠 → D 青 → E 深藍。
  ///
  /// **本色階帶有三項已知且經裁決接受的例外**，不是疏漏：
  ///
  /// 一、B（#C9A227）對 bg/page 僅 2.30，低於 §4.3 的 3.0 底線。
  ///     成因：在近白底上，「看得出是黃色」與「達到 3:1」無法兼得。
  ///     補救：見 [gradeNeedsOutline] —— 對比不足者一律加 1px 細框，
  ///     形狀由邊框界定，與案 4 的淺薄荷日曆格同一套做法。
  ///
  /// 二、色盲（protan／deutan）全配對最小 ΔE 5.0，低於 6.0 底線
  ///     （最差為 deutan 下的 C 綠 ↔ A 橙）。
  ///     補救：**每一處使用等級色的地方必須同時出現等級字母**，
  ///     顏色不得為唯一訊號。此為本色階成立的必要條件，非建議。
  ///
  /// 三、與語意色距離偏近：S ↔ 錯誤紅 ΔE 9.3、A ↔ 錯誤紅 11.0、
  ///     B ↔ CTA 金 7.3。三者靠出現位置區分 ——
  ///     等級色只出現在進度條、雷達圖與等級徽章；
  ///     CTA 金只出現在按鈕填色，錯誤紅只出現在錯誤文字與未讀數徽章。
  ///
  /// 正常視覺全配對最小 ΔE 13.7（B ↔ A）。
  static const gradeS = Color(0xFFB3122E); // 紅
  static const gradeA = Color(0xFFD2691E); // 橙
  static const gradeB = Color(0xFFC9A227); // 黃
  static const gradeC = Color(0xFF2E9E3E); // 綠
  static const gradeD = Color(0xFF0097A7); // 青
  static const gradeE = Color(0xFF1A4FA0); // 深藍

  /// 由低到高，索引即等級序。
  static const gradeScale = <Color>[gradeE, gradeD, gradeC, gradeB, gradeA, gradeS];

  static const _gradeOrder = ['E', 'D', 'C', 'B', 'A', 'S'];

  /// 等級 → 填色
  static Color gradeFill(String grade) {
    final i = _gradeOrder.indexOf(grade);
    return i < 0 ? gradeE : gradeScale[i];
  }

  /// 等級 → 該填色上應使用的前景色（依實測對比擇一，非憑感覺）
  /// E 白 7.9／D 深 4.8／C 深 4.9／B 深 7.0／A 深 4.7／S 白 6.9
  static Color gradeOn(String grade) {
    const dark = {'D', 'C', 'B', 'A'};
    return dark.contains(grade) ? textOnAccent : textOnDark;
  }

  /// 該階對 bg/page 的對比是否不足 3.0 —— 為真者其填色須加 1px 細框，
  /// 否則色塊本身的邊界看不出來。目前僅 B 為真。
  static bool gradeNeedsOutline(String grade) => grade == 'B';

  /// 任一填色上應使用的前景色 —— **取兩者中對比較高的那個**。
  ///
  /// 不用明度門檻：本色票的橘黃 #F5A623 明度 0.47 落在 0.5 以下，
  /// 門檻法會判給白字（2.3:1），但實際上墨字有 9.3:1。
  /// 直接比對比才不會在色票調整後又悄悄挑錯。
  static Color onFill(Color fill) =>
      _contrast(textOnAccent, fill) >= _contrast(textOnDark, fill)
          ? textOnAccent
          : textOnDark;

  static double _contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  // 狀態
  static const statusSuccess = Color(0xFF3DDC97);

  /// 成功色的淡底（v0.8 依設計稿加入）——「這格還救得回來」。
  /// 對頁底僅 1.11，本身看不出邊界，故**必須搭配虛線框**才成立。
  static const statusSuccessTint = Color(0xFFCEF6E5);
  static const statusWarning = Color(0xFFF5A623); // 與 CTA 同色，靠情境區分
  static const statusError = Color(0xFFDC2626);

  // 效果
  static const overlay = Color(0x801C1C1E); // 黑 50%
  static const press = Color(0x141C1C1E); // 疊 8%
  static const skeletonBase = Color(0xFFE8E8ED);
  static const skeletonShine = Color(0xFFF7F7F9);

  // 導覽
  static const navActive = Color(0xFF16324F);
  static const navInactive = Color(0xFF6E6E73);

  /// 【必須】全 App 只用這一種陰影（§5.8）
  static const shadow = <BoxShadow>[
    BoxShadow(
      color: Color(0x141C1C1E),
      offset: Offset(0, 2),
      blurRadius: 8,
    ),
  ];
}

/// 間距系統（§3）—— 以 4px 為基本單位，不得使用表外數值。
class S {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const base = 16.0; // 頁面左右邊界
  static const lg = 24.0;
  static const xl = 32.0;
  static const xxl = 48.0;

  /// 【必須】可捲動內容的最底部必須預留至少 50px（§1.2、§8.19 R-34）
  static const scrollBottom = 50.0;
}

/// 圓角總表（§5.9）
class R {
  static const inset = 4.0; // 進度條、骨架屏文字條
  static const child = 8.0; // 卡片內帶背景／圖片的子元件、Badge
  static const control = 12.0; // 按鈕、輸入框、步進器、選項鍵列、Toast
  static const card = 16.0; // 卡片、選項卡片、價目卡、訊息泡泡、小彈窗
  static const dialogM = 20.0;
  static const dialogL = 24.0;
  static const sheet = 24.0;
  static const switchTrack = 14.0;
}

/// 尺寸常數
class Sz {
  static const buttonMinHeight = 48.0;
  static const listRowSingle = 56.0;
  static const listRowDouble = 72.0;
  static const tapTarget = 44.0; // 【必須】所有可點擊元件 ≥ 44×44
  static const iconDefault = 24.0;
  static const iconDense = 20.0;
  static const iconEmphasis = 32.0;
  static const avatarList = 32.0;
  static const avatarProfile = 88.0;
  static const navBarHeight = 44.0;
  static const tabBarContent = 60.0;
  static const trainButtonDiameter = 44.0;
  static const progressHeight = 8.0;
  static const switchW = 48.0;
  static const switchH = 28.0;
}

const kAnim = Duration(milliseconds: 150);
const kAnimProgress = Duration(milliseconds: 200);
