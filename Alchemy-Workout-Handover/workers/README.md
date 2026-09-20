# 健金術 AI 代理（Cloudflare Worker）

`[BE-08]`。存在的唯一理由是**金鑰不能放在前端**——Flutter Web 建置出來的
`main.dart.js` 會原封不動送到每一位訪客手上。

原設計是 Firebase Cloud Functions，但那需要 Blaze 方案（綁信用卡）。
Cloudflare Workers 免費方案不需要，是同一個問題的另一種解法。
代價是 callable function 免費附送的身分驗證要自己做（`src/auth.ts`）。

## 部署

```bash
cd workers
npm install
npx wrangler login                    # 瀏覽器授權，不用信用卡

# 金鑰。這個指令會在終端機提示你貼上，只存在 Cloudflare，不進版控
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
