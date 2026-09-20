# 健金術 AI 代理（Cloudflare Worker）

`[BE-08]`。存在的唯一理由是**金鑰不能放在前端**——Flutter Web 建置出來的
`main.dart.js` 會原封不動送到每一位訪客手上。

原設計是 Firebase Cloud Functions，但那需要 Blaze 方案（綁信用卡）。
Cloudflare Workers 免費方案不需要，是同一個問題的另一種解法。
代價是 callable function 免費附送的身分驗證要自己做（`src/auth.ts`）。

## 部署

### 在 Codespaces（沒有瀏覽器）

`wrangler login` 走 OAuth —— 它開瀏覽器、然後在**容器內部的**
`localhost:8976` 等回呼。Codespaces 兩個條件都不成立，必定逾時。
改用 API token：

1. https://dash.cloudflare.com/profile/api-tokens → Create Token
2. 選 **Edit Cloudflare Workers** 範本 → Continue → Create Token
3. 複製那串（只會顯示一次）

```bash
cd workers
npm install
export CLOUDFLARE_API_TOKEN='貼在這裡'    # 不要寫進任何檔案

# 金鑰。會在終端機提示你貼上，只存在 Cloudflare，不進版控
npx wrangler secret put GEMINI_API_KEY

npx wrangler deploy
```

帳號不只一個時 wrangler 會要你指定，再加：

```bash
export CLOUDFLARE_ACCOUNT_ID='dash 網址 /accounts/ 後面那一段'
```

### 在有瀏覽器的機器上

```bash
cd workers && npm install
npx wrangler login
npx wrangler secret put GEMINI_API_KEY
npx wrangler deploy
```

部署完會給你一個網址，形如 `https://alchemy-workout-ai.<你的帳號>.workers.dev`。
把它填到 `fitness-app/lib/main.dart` 注入 `HttpAiSuggestionSource` 的那一行。

## 本機試跑

```bash
echo 'GEMINI_API_KEY="你的金鑰"' > .dev.vars   # 已在 .gitignore
npx wrangler dev
```

## 安全性

| 關卡 | 做法 |
|---|---|
| 金鑰 | Cloudflare secret，不在程式碼、不在版控、前端拿不到 |
| 誰能呼叫 | 驗 Firebase ID token（簽章＋`aud`＋`iss`＋`exp` 四項全驗） |
| 從哪裡呼叫 | CORS 限定 `ALLOWED_ORIGIN`，**不要改成 `*`** |
| 模型輸出 | `clamp()` 逐項對照使用者送上來的課表，對不上就丟棄 |

送上去的資料**只有動作名稱與逐組目標**，不含 uid、身高體重或任何身分資訊。
