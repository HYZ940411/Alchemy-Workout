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

# --- 相對強度係數（2026-10-17 使用者逐類裁決；紀錄在「動作權重盤點.md」）------------
#
# 以前這裡是一張關鍵字 → 係數的草稿表（槓鈴臥推 ＝ 1.0，其餘憑訓練學常識）。
# 同一個關鍵字不分器材給同一個係數，結果是：啞鈴／壺鈴／彈力繩的重量對不上、
# 徒手動作一組就到頂 999、同一部位的新手分數落差十倍以上。
#
# 現在改成「每一類有一個新手標準」：**體重 70 kg 的新手，舒服做完 10 下，落在固定分數**。
#   · 有重量的動作（槓鈴／啞鈴／機械／繩索／壺鈴）：C 級，約 294 分
#   · 徒手動作：C 級，約 294 分（同類動作分數相同，想更高靠外加負重）
#   · 彈力繩：約 150 分（D+ 下緣）
#   · 13 個沒拿東西的徒手孤立動作（徒手前平舉、手臂繞圈等）：約 50 分（E+）
# 係數 ＝ 「達到該分數所需的 重量 × 係數」÷ 該類新手標準重量。
#
# 次數上限 10 下沒動（規格決策）。基準值／映射係數 2026-10-19 重新校準為 19.54／14.33（原 27.6／23.6，
# 使用者裁決：槓鈴臥推 70 kg × 8 下該是 A 級、S 級下緣約 1.5 倍體重），**新手標準 294 不變**；
# 外加負重照原公式加進去（等效重量 ＝ 體重 × 體重係數 ＋ 外加負重）。
#
# 這張表的驗收在 test/weight_baseline_test.dart：它自己獨立分類、用真的 measuredScore 算，
# 誰調了這裡的數字，都會在那邊看到每一類變成多少分。

#: 達到目標分數所需的「重量 × 係數」（體重 70 kg 男性、10 下，measuredScore 反解到整分）。
#: **隨基準值／映射係數重新校準**：下面三個是 19.54／14.33 之下的值（原 27.6／23.6 下為 40.0／33.9／29.67）。
WK_C = 40.0       # 294 分（新舊參數下剛好都是 40.0，新手標準不變）
WK_BAND = 29.96   # 150 分
WK_LOW = 22.99    # 50 分
#: 標準情境的體重。徒手動作的新手標準重量 ＝ 這個體重 × 體重係數。
STD_BODYWEIGHT = 70.0


def bodyweight_factor(name):
    """鏡像 fitness-app/lib/domain/models.dart 的 Exercise.bodyweightFactor。
    兩邊不一致，test/weight_baseline_test.dart 的分數會偏掉而變紅。"""
    return 1.0 if '引體向上' in name else 0.6


#: 沒拿東西的徒手孤立動作（使用者裁決：給很少的分，不改標有氧）。
#: 名稱須與 normalise_name 之後完全一致；main() 結尾會檢查每一個都有對到。
LOW_GROUP = {
    '肘臂繞圈', '手臂繞圈', '前平舉', '上舉', '合掌上舉', '站姿反手上提', '臥姿反向飛鳥',
    '交互拳擊', '二頭肌屈臂', '二頭肌彎舉(抬腿)', '側臥二頭肌彎舉', '跪姿三頭肌伸展', '側平舉',
}
#: 器材欄不是「無器材」、但其實是徒手的動作。
BODYWEIGHT_FORCE = {'椅子坐站'}
#: 部位歸錯的動作（使用者裁決）：匯入規則把「全身」一律歸腿，另有一個被歸到肩。
DIM_FIX = {
    '架上推舉 · 槓鈴': 'shoulders',
    '火箭推 · 槓鈴': 'shoulders',
    '火箭推 · 壺鈴': 'shoulders',
    '繩索髖屈伸': 'legs',
}

#: 新手標準重量（公斤；啞鈴為每手）。鍵：動作型態 → 器材群。
NOVICE_WEIGHT = {
    '複合推': {'槓': 40, '啞': 16, '器': 35, '繩': 20},  # 啞 14→16：啞鈴／槓鈴 ＝ 0.4（2026-10-19）
    '飛鳥夾胸': {'啞': 8, '器': 25, '繩': 10},
    '仰臥上拉': {'槓': 20, '啞': 14},
    '划船': {'槓': 40, '啞': 16, '器': 35, '繩': 35},
    '下拉上拉': {'槓': 20, '啞': 14, '器': 40, '繩': 40},
    '聳肩': {'槓': 50, '啞': 20, '器': 50, '繩': 40},  # 啞 16→20：同上
    '硬舉': {'槓': 60, '啞': 24, '器': 50},  # 啞 16→24：兩手各一顆，啞鈴／槓鈴 ＝ 0.4（2026-10-19）
    '背伸展躬身': {'槓': 30, '器': 30},
    '肩後束小肌群': {'啞': 4, '器': 10, '繩': 8},
    '深蹲': {'槓': 50, '啞': 18, '器': 40, '繩': 30},  # 啞 14→18：高腳杯式一顆，0.35
    '腿推': {'器': 100},
    '弓步單腿': {'槓': 30, '啞': 12, '器': 20, '繩': 15},  # 啞 10→12：兩手各一顆，0.4
    '臀橋臀推': {'槓': 60, '啞': 24, '器': 60, '繩': 30},  # 啞 16→24：一顆放髖部，0.4
    '提踵': {'槓': 40, '啞': 16, '器': 40},  # 啞 12→16：兩手各一顆，0.4
    '腿孤立': {'啞': 5, '器': 30, '繩': 15},
    '全身爆發': {'槓': 30, '啞': 12},
    '負重行走': {'槓': 40, '啞': 16},
    '肩推': {'槓': 30, '啞': 12, '器': 25, '繩': 15},  # 啞 10→12：同上
    '平舉': {'槓': 15, '啞': 5, '器': 10, '繩': 8},
    '二頭彎舉': {'槓': 20, '啞': 8, '器': 15, '繩': 15},
    '三頭肌': {'槓': 20, '啞': 8, '器': 25, '繩': 20},
    '腕彎舉': {'槓': 15, '啞': 6, '繩': 15},
    '核心捲腹抬腿': {'啞': 8, '繩': 30},
    '核心轉體側彎': {'槓': 20, '啞': 8, '器': 30, '繩': 20},
}
#: 壺鈴：一般 12 kg，下列動作例外（鍵為動作名稱去掉器材後綴）。
KETTLEBELL_DEFAULT = 12
KETTLEBELL_WEIGHT = {
    '硬舉': 16, '直腿硬舉': 16, '單腳硬舉': 16, '農夫走路': 16,
    '上舉': 8, '風車': 8, '仰臥起坐': 8,
    '側平舉': 4,
}


def equipment_group(eq):
    """器材集合 → 群代號。彈力繩優先（「引體向上 · 彈力帶」同時掛了機械式器材）。"""
    for key, g in (('彈力繩', '帶'), ('壺鈴', '壺'), ('槓鈴', '槓'), ('啞鈴', '啞'),
                   ('繩索（滑輪）', '繩'), ('機械式器材', '器')):
        if key in eq:
            return g
    return '徒'


def weighted_pattern(name, dim):
    """有重量的動作 → 動作型態（NOVICE_WEIGHT 的鍵）。對不到就丟例外，不默默給預設值。"""
    n = name
    if re.search(r'抓舉|挺舉|上搏|瞬發|甩壺|甩鈴|土耳其|借力', n):
        return '全身爆發'
    if re.search(r'負重行走|農夫走路', n):
        return '負重行走'
    if dim == 'back':
        if re.search(r'划船', n): return '划船'
        if re.search(r'下拉|上拉|引體|滑輪下壓', n): return '下拉上拉'
        if re.search(r'聳肩', n): return '聳肩'
        if re.search(r'硬舉', n): return '硬舉'
        if re.search(r'背部伸展|躬身|超人', n): return '背伸展躬身'
        return '肩後束小肌群'
    if dim == 'chest':
        if re.search(r'上拉', n): return '仰臥上拉'
        if re.search(r'飛鳥|夾胸|擴胸', n): return '飛鳥夾胸'
        return '複合推'
    if dim == 'shoulders':
        if re.search(r'反向.*飛鳥|臉拉|外旋|外琁|內轉|後划|划舉|繞圈|上提', n): return '肩後束小肌群'
        if re.search(r'平舉', n): return '平舉'
        if re.search(r'划船', n): return '划船'
        return '肩推'
    if dim == 'arms':
        if re.search(r'腕彎舉', n): return '腕彎舉'
        if re.search(r'集中推舉|三頭|下壓', n): return '三頭肌'
        return '二頭彎舉'
    if dim == 'core':
        if re.search(r'捲腹|仰臥起坐|抬腿|抬膝|提膝|V字|Ｖ字|由下而上伸展', n): return '核心捲腹抬腿'
        return '核心轉體側彎'
    if dim == 'legs':
        if re.search(r'腿部推蹬|腿部推蹲|推蹬|小腿推蹬', n): return '腿推'
        if re.search(r'提踵|提腫', n): return '提踵'
        if re.search(r'臀橋|臀推|臀腿|蛙式|提髖', n): return '臀橋臀推'
        if re.search(r'硬舉', n): return '硬舉'
        if re.search(r'弓箭步|分腿|登階|保加利亞', n): return '弓步單腿'
        if re.search(r'深蹲|前蹲|哈克|坐站|蹲', n): return '深蹲'
        return '腿孤立'
    raise ValueError(f'無法分類：{name}（{dim}）')


def calibrated_intensity(name, dim, eq, bodyweight):
    """相對強度係數：讓「體重 70 kg 新手做 10 下」剛好落在該類的目標分數。"""
    if bodyweight:
        f = bodyweight_factor(name)
        if name in LOW_GROUP:
            target = WK_LOW
        elif '彈力繩' in eq:
            target = WK_BAND
        else:
            target = WK_C
        return round(target / (STD_BODYWEIGHT * f), 4)
    g = equipment_group(eq)
    if g == '壺':
        w = KETTLEBELL_WEIGHT.get(name.split(' · ')[0], KETTLEBELL_DEFAULT)
    else:
        table = NOVICE_WEIGHT[weighted_pattern(name, dim)]
        if g not in table:
            raise ValueError(f'沒有新手標準重量：{name}（{dim}，器材群 {g}）')
        w = table[g]
    return round(WK_C / w, 4)


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
    '側平舉': ('lateral', 2.60, 60, True),
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
    seen_low = set()
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

        if name in DIM_FIX:
            dim = DIM_FIX[name]
            if dim not in dims:  # 原有的訓練部位（分頁篩選用）保留，只補上改正後的
                dims = dims + [dim]
            report['部位歸錯，已改正'].append(f'{name}　→　{dim}')

        ov = OVERRIDES.get(name) if suffix == '' else None
        if ov:
            OVERRIDES.pop(name)
        bodyweight = bool((ov[3] if ov else any(a in BODYWEIGHT_HINT for a in atoms(r['器材'])))
                          or '彈力繩' in eq or name in BODYWEIGHT_FORCE or name in LOW_GROUP)
        if name in LOW_GROUP:
            seen_low.add(name)
        auto = calibrated_intensity(name, dim, eq, bodyweight)
        out.append({
            'parts': dims,
            'id': ov[0] if ov else f'p{i:03d}{suffix}',
            'intensity': auto,
            'rest': ov[2] if ov else None,
            'name': name,
            'dim': dim,
            'equipment': sorted(eq),
            'accessories': sorted(acc),
            'bodyweight': bodyweight,
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

    if seen_low != LOW_GROUP:
        print(f'錯誤：LOW_GROUP 有動作對不到 CSV：{sorted(LOW_GROUP - seen_low)}')
        return 1

    # **對不到就停下來，不要默默產出。**
    # 校準值查不到時，動作會退回流水號 ID 並遺失休息秒數 ——
    # 產出看起來正常、測試也不會紅，但 App 裡 ex('squat') 那類
    # 硬引用會全部指向不存在的動作。留白會被看見，錯的不會。
    if OVERRIDES:
        for left in OVERRIDES:
            report['示範動作對不到 CSV 的動作'].append(left)
        print('錯誤：以下校準值對不到 CSV 的動作名稱，產出已中止：')
        for left in OVERRIDES:
            print(f'  · {left}')
        print('請確認 OVERRIDES 的鍵與 normalise_name 正規化後的名稱一致。')
        return 1
    write_dart(out)
    write_guides(out)
    write_report(out, report)
    print(f'轉出 {len(out)} 個動作')

    # [BE-12] 同一批資料的第二個出口：上傳 Firestore 的 exercises 集合。
    # 預設只產生 .g.dart（離線後備／測試夾具）；帶 --upload 才寫雲端。
    if '--upload' in sys.argv:
        from firestore_upload import get_db, upsert
        docs = {e['id']: exercise_doc(e) for e in out}
        upsert(get_db(), 'exercises', docs)


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


def equipment_display(e):
    """器材顯示字串：配件用「＋」接在器材品項後面，與品項本身分開 ——
    「繩索（滑輪）」本身就帶括號，用括號標配件會分不出來。"""
    eq = ' · '.join(e['equipment'])
    if e['accessories']:
        eq += ' ＋ ' + '、'.join(e['accessories'])
    return eq


def exercise_doc(e):
    """Firestore exercises/{id} 的文件形狀（[BE-12]）。

    **必須與 fitness-app/lib/data/platform_data.dart 的 exerciseFromDoc 相符。**
    parts 只在複選時存（單一部位者由 Dart 的 tabs getter 退回 dim），與下面
    write_dart 的產生邏輯一致 —— 確保雲端內容與打包在本地的後備完全對齊。
    """
    doc = {
        'name': e['name'],
        'dim': e['dim'],  # cardio 為 None，其餘為 'chest' 等字串
        'parts': e['parts'] if len(e['parts']) > 1 else [],
        'relativeIntensity': float(e['intensity']),
        'isBodyweight': bool(e['bodyweight']),
        'type': 'cardio' if e.get('cardio') else 'strength',
        'equipment': equipment_display(e),
    }
    if e['rest'] is not None:
        doc['defaultRestSeconds'] = e['rest']
    return doc


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
        eq = equipment_display(e)
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


# ---------------------------------------------------------------------------
# OVERRIDES 的鍵要跟著 normalise_name 走
# ---------------------------------------------------------------------------
#
# OVERRIDES 是手寫的，鍵沿用 CSV 的原始寫法（'深蹲 -槓鈴'）；
# 而迴圈裡的 name 已經過 normalise_name 正規化（'深蹲 · 槓鈴'）。
# 兩邊格式不同，16 筆校準值就會全部查不到 —— 而且**不會報錯**，
# 只是靜靜退回流水號 pNNN，連帶遺失休息秒數與相對強度。
#
# 這正是實際發生過的事：normalise_name 是後來才加的，加的時候
# 沒有一併改這些鍵，於是重跑腳本產出的 .g.dart 與版控裡那份對不上，
# 而 15 個被程式碼以 ex('squat') 硬引用的友善 ID 全部消失。
#
# 在這裡統一轉一次，日後再改分隔符也不會再踩到。
OVERRIDES = {normalise_name(k): v for k, v in OVERRIDES.items()}

# 同一個道理，這兩份名單也是手寫的、也用原始寫法。
# 只有帶器材後綴的條目會受影響（徒手動作沒有分隔符，正規化前後一樣），
# 所以漏掉時只會錯個一兩筆 —— 更難發現，不是更無害。
MOBILITY = {normalise_name(k) for k in MOBILITY}
CONDITIONING = {normalise_name(k) for k in CONDITIONING}


if __name__ == '__main__':
    sys.exit(main())
