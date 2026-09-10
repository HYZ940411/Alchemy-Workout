#!/usr/bin/env python3
"""把「健身動作資料庫」CSV 轉成 App 可直接讀的資料。

輸出兩份：
  fitness-app/lib/mock/platform_exercises.g.dart  結構化欄位（名稱、肌群、器材）
  fitness-app/assets/data/exercise_guides.json    教學文字（準備工作 / 要領 / 提示）

分開的理由：清單頁只需要結構化欄位，且它們要能同步取用（現行 kExercises 是 const）；
教學文字很長且只有動作詳情頁用得到，做成資產延遲載入。

映射不上的每一筆都寫進 tools/import_report.md，不靜默吞掉。
"""
import csv, json, pathlib, re, sys
from collections import Counter, defaultdict

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / '健身動作資料庫-1.csv'

# --- 器材：CSV 的 33 種原子品項 → 模型〈器材設定 Aggregate〉的 8 品項 -------------
EQUIPMENT = {
    '無器材': '徒手',
    '槓鈴': '槓鈴',
    '啞鈴': '啞鈴',
    '壺鈴': '壺鈴',
    '握把彈力帶': '彈力繩',
    '滑輪機': '繩索（滑輪）',
    # 史密斯架歸機械式而非槓鈴：使用者若以「我家有槓鈴」篩選，
    # 不該篩出需要固定機台的動作。兩者的可練場所同為健身房，推導不受影響。
    '史密斯架': '機械式器材',
}
# 各式固定機台一律歸「機械式器材」
MACHINE = [
    '腿部推蹬機', '多功能臀部訓練機', '屈腿訓練機', '軀幹旋轉訓練機', '腿部伸展機',
    '槓桿深蹲訓練機', '坐姿划船機', '坐姿臀部訓練機', '側平舉訓練機',
    '傳教士彎舉訓練機', '二頭肌屈臂訓練機', '哈克深蹲機', '反向過度伸展機',
    '三頭肌伸展訓練機', '上拉訓練機', '上斜胸推機', '肩上推舉訓練機', '胸推機',
    '站姿提踵訓練機',
    # 模型的 8 品項沒有「單槓」。歸機械式器材會低估可得性（家用單槓很常見），
    # 歸徒手則高估（徒手在模型裡代表到處都能練）。此處取前者，待裁決。
    '引體向上單槓',
]
EQUIPMENT.update({m: '機械式器材' for m in MACHINE})

# 配件不屬於模型的器材值域，另存一欄，不參與器材比對。
ACCESSORIES = {'平板椅', '上斜板凳', '下斜板凳', '傳教士板凳', '椅子', '踏板'}

# --- 部位：CSV 的 11 大類 → 模型六維 -----------------------------------------
DIM = {
    '胸部': 'chest', '背部': 'back', '腿部': 'legs',
    '肩膀': 'shoulders', '手臂': 'arms', '腹部': 'core',
    '腰部': 'core',        # 下背與腰屬核心，不另立維度
    '髖關節': 'legs',
    '足部': 'legs',
}
# 對不上六維者，需裁決。暫定值只為讓資料進得來，全數列入報告。
# 全身動作（奧林匹克舉重與負重行走）歸腿 —— 下肢主導。
# conditioning 的 4 筆已在上面走有氧路徑，不會落到這裡。
UNRESOLVED_DIM = {'全身': 'legs'}

BODYWEIGHT_HINT = ('無器材',)

# --- 不進六維的兩類（2026-09-02 裁決）--------------------------------------
# 活動度／呼吸／伸展：做了不會長肌力，計入六維會汙染其語意
# （承模型「不採折算至既有六維…雷達圖日後無法解讀」的既有立場）。
# 沿用有氧的既有機制：不觸發「能力值已提升」，但仍計經驗值、金幣、連續訓練天數。
MOBILITY = {
    '仰臥腹式呼吸',
    '仰臥腹式呼吸＋吐氣時肋骨回收',
    '仰臥下巴內收(chin tuck)',
    '貓牛式',
    '開書式胸椎旋轉（側躺）',
    '胸椎伸展（跪姿手肘撐地、胸口向地再回）',
    '四足跪肩胛前推/後收（Scapular push-up）',
    '牆上滑手（Wall slide，保持肋骨不外翻）',
    '俯臥 Y / T（小幅度、肩胛下沉外旋）',
    '桌緣/牆面推牆（Incline push-up）＋頂端「加一點肩胛前推」',
    '骨盆前後傾找中立位',
    '跪姿髖屈肌伸展（骨盆保持中立）',
    '短足（Short-foot，足弓輕收、腳趾放鬆）',
    '90/90 髖旋轉（坐姿換腳）',
    '腳趾瑜伽（大腳趾抬/其餘抬）',
    '踝背屈動態（膝蓋往腳趾方向、腳跟不離地）',
    '蛙式髖關節伸展',
    '蛙式髖關節伸展-史密斯架',
}
# 體能訓練（conditioning）：性質接近有氧，非最大肌力。
CONDITIONING = {'波比跳', '開合跳', '高抬腿', '砸球'}

# --- 主要肌群：依動作型態的關鍵字判定 ------------------------------------------
# 「重點部位」的多值**是固定分類序**（手臂 < 肩膀 < 背部 < 腰部 < 腹部 < 腿部），
# 在 155 筆跨多類的動作裡從未出現反向順序 —— 也就是說它不是「主要部位在前」，
# 取第一個會把窄距臥推判成手臂。單值者直接用該值；多值者改由動作名稱判定。
PATTERNS = [
    ('shoulders', r'反向.*飛鳥|臉拉|肘關節|划舉|合掌上舉|蝦型'),
    ('chest', r'臥推|胸推|飛鳥|夾胸|伏地挺身|推胸|擴胸|握推'),
    ('back', r'划船|下拉|引體|上拉|聳肩|硬舉|背伸展|反向飛鳥|屈體|躬身|超人|暴力上槓'),
    # 後三角與旋轉肌的動作原本被判成背或胸 —— 反向飛鳥、臉拉、肘關節內外轉
    # 皆為肩部細節動作，須排在 chest/back 之前。
    ('shoulders', r'反向.*飛鳥|臉拉|肘關節|划舉|合掌上舉|蝦型|'
                  r'肩推|過頭推|肩上推|側平舉|前平舉|直立划船|阿諾|上挺|火箭推|推舉'),
    ('arms', r'彎舉|屈臂|三頭|二頭|臂屈伸|下壓|撐體|腕|前臂|拳擊'),
    ('legs', r'深蹲|蹲|腿推|腿舉|推蹬|弓步|跨步|分腿|提踵|腿彎舉|腿伸展|臀推|臀橋|'
             r'外展|內收|登階|走路|行走|踢|髖'),
    ('core', r'捲腹|棒式|仰臥起坐|側彎|轉體|舉腿|抗旋|死蟲|鳥狗|登山者|V字|摺刀|提髖'),
]
# 關鍵字判不出來時的退路：大肌群優先。命中者一律標為待複核。
FALLBACK = ['legs', 'back', 'chest', 'shoulders', 'arms', 'core']

# --- 相對強度係數 -----------------------------------------------------------
# 模型：每個動作的估算 1RM × 相對強度係數 → 該肌群的標準化 1RM。
# 基準值 27.6 與映射係數 23.6 是由**槓鈴臥推**反解出來的，六維共用同一組，
# 所以係數必須全部相對於臥推（＝1.0），而不是各肌群各自取 1.0 ——
# 深蹲若也給 1.0，練到 1.5 倍體重的人腿部會直接觸頂 999。
#
# 取值 ＝ 臥推 1RM ÷ 該動作 1RM（訓練學常識的常見比值）。
# 模型將本表列為 [待決策 Partial]「由內容團隊於上線前補齊，非上線阻擋」，
# 故此處為初始草稿，上線後以自家資料校準。
INTENSITY = [
    # 胸
    (r'上斜.*(臥推|握推|胸推)', 1.18),
    (r'下斜.*(臥推|握推|胸推)', 0.95),
    (r'(臥推|握推|胸推).*\(窄距\)|窄距.*(臥推|握推)', 1.18),
    (r'(臥推|握推|胸推).*\(寬距\)|寬距.*(臥推|握推)', 0.95),
    (r'飛鳥|夾胸|擴胸', 2.00),
    (r'伏地挺身|推牆', 1.30),
    (r'臥推|握推|胸推', 1.00),
    # 背
    (r'硬舉高拉|直腿硬舉|羅馬尼亞硬舉', 0.77),
    (r'硬舉', 0.62),
    (r'聳肩', 0.67),
    (r'滑輪下拉|高位下拉|上拉', 0.95),
    (r'引體向上|反向引體', 1.10),
    (r'划船', 0.95),
    (r'背伸展|躬身|超人', 1.50),
    # 腿
    (r'腿部推蹬|腿推', 0.42),
    (r'哈克深蹲|槓桿深蹲', 0.55),
    (r'前蹲|過頭深蹲', 0.87),
    (r'弓步|弓箭步|跨步|分腿|保加利亞|登階|單腿', 1.25),
    (r'深蹲|坐站', 0.72),
    (r'提踵|提腫', 0.55),
    (r'臀推|臀橋', 0.55),
    (r'腿部伸展|腿伸展', 1.10),
    (r'腿部彎舉|腿彎舉|屈腿', 1.40),
    (r'外展|內收|髖|消防栓', 2.00),
    # 肩
    (r'側平舉|前平舉|反向.*飛鳥', 3.60),
    (r'臉拉|肘關節|外旋|內轉|繞圈', 3.60),
    (r'直立划船|划舉', 2.20),
    (r'上舉|肩推|過頭推|阿諾|上挺|火箭推|推舉', 1.35),
    # 手
    (r'錘式彎舉|集中彎舉|傳教士彎舉|反向彎舉', 2.60),
    (r'腕彎舉|前臂', 3.20),
    (r'彎舉|屈臂', 2.10),
    (r'三頭肌下壓|下壓', 1.90),
    (r'仰臥.*三頭|過頭.*三頭|三頭.*伸展', 2.20),
    (r'撐體|臂屈伸', 1.15),
    # 核心
    (r'棒式|側棒式|空心|L-Sit|死蟲|鳥狗|登山者', 1.60),
    (r'捲腹|仰臥起坐|舉腿|抬腿|抬膝|提膝|摺刀|V字|鐘擺|碰槓|摸腳踝', 2.40),
    (r'側彎|轉體|抗旋', 2.20),
    # 全身（奧林匹克舉重與負重行走）
    (r'抓舉|挺舉|上搏|瞬發|借力|甩壺|甩鈴|土耳其', 0.85),
    (r'負重行走|農夫走路', 0.60),
]
# 關鍵字都不中時，依所屬肌群給一個中間值。落到這裡的會列進報告。
INTENSITY_FALLBACK = {
    'chest': 1.30, 'back': 1.10, 'legs': 0.80,
    'shoulders': 2.00, 'arms': 2.20, 'core': 2.00,
}


def intensity_for(name, dim):
    for pat, v in INTENSITY:
        if re.search(pat, name):
            return v, False
    return INTENSITY_FALLBACK.get(dim, 1.0), True


# --- 既有的 16 個示範動作 --------------------------------------------------
# CSV 沒有「相對強度係數」與「預設組間休息秒數」——前者是能力值的輸入，
# 後者是模型明訂的動作層級屬性。既有這 16 個是照模型調過的，
# 匯入時把它們接到對應的真實動作上，保留調好的值，避免出現概念重複的兩筆。
OVERRIDES = {
    '板凳臥推-槓鈴': ('bench', 1.00, 150, False),
    '板凳臥推。啞鈴': ('db_press', 1.05, 120, False),
    '上斜板凳臥推 -槓鈴': ('incline', 1.10, 120, False),
    '三頭肌撐體': ('dip', 1.15, 90, True),
    '屈體划船 -槓鈴': ('row', 1.00, 120, False),
    '引體向上': ('pullup', 1.10, 120, True),
    '滑輪下拉-滑輪機': ('latpull', 0.95, 90, False),
    '深蹲 -槓鈴': ('squat', 0.72, 180, False),
    '硬舉 -槓鈴': ('deadlift', 0.62, 180, False),
    '腿部推蹬-器械': ('legpress', 0.42, 120, False),
    '上舉 -槓鈴': ('ohp', 1.35, 120, False),
    '側平舉': ('lateral', 2.60, 60, False),
    '集中彎舉。啞鈴': ('curl', 2.10, 60, False),
    '三頭肌下壓-滑輪機': ('pushdown', 1.90, 60, False),
    '棒式': ('plank', 1.60, 60, True),
    '捲腹': ('crunch', 2.40, None, True),
}


def atoms(field):
    return [x.strip() for x in field.split(',') if x.strip()]


def main():
    rows = list(csv.DictReader(SRC.open(encoding='utf-8-sig')))

    out, report = [], defaultdict(list)
    seen_names = Counter()
    unmapped_eq, unmapped_part = Counter(), Counter()

    for i, r in enumerate(rows):
        name = normalise_name(r['動作名稱'])
        if not name or not r['重點部位'].strip():
            report['空白紀錄'].append(f'第 {i + 2} 行：{r}')
            continue

        # 名稱重複者保留全部，以序號區分，不靜默去重
        seen_names[name] += 1
        suffix = '' if seen_names[name] == 1 else f'_{seen_names[name]}'
        if seen_names[name] > 1:
            report['名稱重複'].append(name)

        eq, acc = set(), set()
        for a in atoms(r['器材']):
            if a in ACCESSORIES:
                acc.add(a)
            elif a in EQUIPMENT:
                eq.add(EQUIPMENT[a])
            else:
                unmapped_eq[a] += 1
        if not eq:
            eq = {'徒手'}

        if name in MOBILITY or name in CONDITIONING:
            kind = '活動度／呼吸／伸展' if name in MOBILITY else '體能訓練'
            report[f'{kind} → 標為有氧，不進六維'].append(name)
            ov0 = OVERRIDES.pop(name, None)
            out.append({
                'id': ov0[0] if ov0 else f'p{i:03d}',
                'intensity': 0.0, 'rest': None, 'name': name,
                'dim': None, 'cardio': True, 'parts': [],
                'equipment': sorted({EQUIPMENT[a] for a in atoms(r['器材'])
                                     if a in EQUIPMENT} or {'徒手'}),
                'accessories': sorted({a for a in atoms(r['器材'])
                                       if a in ACCESSORIES}),
                'bodyweight': False, 'needsReview': False,
                'rawParts': r['重點部位'].strip(),
                'setup': r['準備工作'].strip(), 'howto': r['動作要領'].strip(),
                'tips': r['關鍵提示'].strip(),
            })
            continue

        groups = []
        for p in atoms(r['重點部位']):
            g = p.split('：')[0]
            if g not in groups:
                groups.append(g)
        dims = []
        for g in groups:
            d = DIM.get(g) or UNRESOLVED_DIM.get(g)
            if d is None:
                unmapped_part[g] += 1
            elif d not in dims:
                dims.append(d)
        if not dims:
            continue

        needs_review = False
        for g in groups:
            if g in UNRESOLVED_DIM:
                report['全身動作 → 歸腿（下肢主導）'].append(name)

        if len(dims) == 1:
            dim = dims[0]
        else:
            dim = None
            for d, pat in PATTERNS:
                if re.search(pat, name):
                    # 關鍵字判出的維度須落在原始部位集合內才採信。
                    dim = d if d in dims else None
                    break
            if dim is None:
                dim = next(d for d in FALLBACK if d in dims)
                needs_review = True
                report['跨多維且關鍵字判不出（取大肌群，待複核）'].append(
                    f'{name}　→　{dim}　（原始：{r["重點部位"]}）')
            else:
                report['跨多維，由動作名稱判定'].append(
                    f'{name}　→　{dim}　（原始：{r["重點部位"]}）')

        ov = OVERRIDES.get(name) if suffix == '' else None
        if ov:
            OVERRIDES.pop(name)
        auto, used_fallback = intensity_for(name, dim)
        if not ov:
            if used_fallback:
                report['相對強度係數：關鍵字未命中，用該維預設值'].append(
                    f'{name}　→　{auto}')
        elif abs(ov[1] - auto) > 0.15:
            report['相對強度係數：既有校準值與草稿差距大（以既有值為準）'].append(
                f'{name}　既有 {ov[1]}　草稿 {auto}')
        out.append({
            'parts': dims,
            'id': ov[0] if ov else f'p{i:03d}{suffix}',
            'intensity': ov[1] if ov else auto,
            'rest': ov[2] if ov else None,
            'name': name,
            'dim': dim,
            'equipment': sorted(eq),
            'accessories': sorted(acc),
            'bodyweight': (ov[3] if ov
                           else any(a in BODYWEIGHT_HINT for a in atoms(r['器材']))),
            'needsReview': needs_review,
            'rawParts': r['重點部位'].strip(),
            'setup': r['準備工作'].strip(),
            'howto': r['動作要領'].strip(),
            'tips': r['關鍵提示'].strip(),
        })

    for k, v in unmapped_eq.items():
        report['器材映射不到'].append(f'{k}（{v} 筆）')
    for k, v in unmapped_part.items():
        report['部位映射不到'].append(f'{k}（{v} 筆）')

    for left in OVERRIDES:
        report['示範動作對不到 CSV 的動作'].append(left)
    write_dart(out)
    write_guides(out)
    write_report(out, report)
    print(f'轉出 {len(out)} 個動作')


def dart_str(s):
    return "'" + s.replace('\\', r'\\').replace("'", r"\'").replace('$', r'\$') + "'"


def normalise_name(raw):
    """動作名稱裡「動作名 ＋ 器材」的分隔符統一為「 · 」。

    來源 CSV 用了四種寫法：'-'（220）、'。'（74）、' -'（68）、'  -'（5）。
    全形句號那 74 個在畫面上讀起來像句子結束 ——「板凳臥推。啞鈴」不是一個
    名字；四種混用在課表內容頁一眼就看得出來。分隔符取「 · 」，與 App 既有的
    排版一致（「4 動作 · 13 組」）。

    **只換器材前面的那一個**：以器材詞錨定，不是見到連字號就換。
    名稱裡另有四筆的連字號屬英文詞本身（Scapular push-up、Short-foot、
    地面 L-Sit 嘗試），一律替換會把它們改壞。
    """
    n = (raw or '').strip()
    n = _SEP_RE.sub(' · ', n)
    return re.sub(r'  +', ' ', n).strip()


#: 分隔符後面接的器材詞。CSV 全部 362 個分隔符後面只會是這七個之一。
EQUIPMENT_SUFFIX = ('槓鈴', '啞鈴', '彈力帶', '滑輪機', '器械', '史密斯架', '壺鈴')
_SEP_RE = re.compile(
    r'\s*[-。]\s*(?=(?:' + '|'.join(EQUIPMENT_SUFFIX) + r'))')


def write_dart(items):
    p = ROOT / 'fitness-app/lib/mock/platform_exercises.g.dart'
    lines = [
        '// 由 tools/import_exercises.py 產生，請勿手改。',
        '// 來源：健身動作資料庫-1.csv（531 筆）',
        '',
        "import '../domain/ability.dart';",
        "import '../domain/models.dart';",
        '',
        '/// 平台動作庫。唯讀，隨 App 打包 —— 訓練紀錄流程明訂離線可用，',
        '/// 而這份資料使用者不會寫入，放在本地比放遠端合適。',
        'const kPlatformExercises = <Exercise>[',
    ]
    for e in items:
        # 配件用「＋」接在後面，與器材品項本身分開 ——
        # 「繩索（滑輪）」本身就帶括號，用括號標配件會分不出來。
        eq = ' · '.join(e['equipment'])
        if e['accessories']:
            eq += ' ＋ ' + '、'.join(e['accessories'])
        lines.append('  Exercise(')
        lines.append(f"    id: {dart_str(e['id'])},")
        lines.append(f"    name: {dart_str(e['name'])},")
        if e.get('cardio'):
            lines.append('    dim: null,')
            lines.append('    type: ExerciseType.cardio,')
        else:
            lines.append(f"    dim: Dim.{e['dim']},")
            # 訓練部位為複選，服務分頁與篩選；單一部位者省略，由 tabs 退回 dim。
            if len(e['parts']) > 1:
                joined = ', '.join(f'Dim.{d}' for d in e['parts'])
                lines.append(f'    parts: {{{joined}}},')
        lines.append(f"    relativeIntensity: {e['intensity']},")
        if e['bodyweight']:
            lines.append('    isBodyweight: true,')
        if e['rest'] is not None:
            lines.append(f"    defaultRestSeconds: {e['rest']},")
        lines.append(f"    equipment: {dart_str(eq)},")
        lines.append('  ),')
    lines.append('];')
    p.write_text('\n'.join(lines) + '\n')


def write_guides(items):
    p = ROOT / 'fitness-app/assets/data/exercise_guides.json'
    p.parent.mkdir(parents=True, exist_ok=True)
    data = {
        e['id']: {'setup': e['setup'], 'howto': e['howto'], 'tips': e['tips']}
        for e in items if e['setup'] or e['howto'] or e['tips']
    }
    p.write_text(json.dumps(data, ensure_ascii=False, indent=0))


def cjk(s):
    return sum(1 for c in s if '一' <= c <= '鿿') / max(1, len(s))


def write_report(items, report):
    p = ROOT / 'tools/import_report.md'
    en = [e for e in items if e['howto'] and cjk(e['howto']) < 0.2]
    L = ['# 動作資料庫匯入報告', '',
         f'- 轉出 **{len(items)}** 個動作',
         f'- 教學文字為英文者 **{len(en)}** 筆（佔 {len(en) * 100 // max(1, len(items))}%）',
         '']
    for k in sorted(report):
        v = report[k]
        L.append(f'## {k}（{len(v)} 筆）')
        L.append('')
        L += [f'- {x}' for x in v[:60]]
        if len(v) > 60:
            L.append(f'- …另有 {len(v) - 60} 筆')
        L.append('')
    p.write_text('\n'.join(L))


if __name__ == '__main__':
    sys.exit(main())
