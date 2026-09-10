import { Before, After, setWorldConstructor, setDefaultTimeout } from '@cucumber/cucumber'
import { chromium } from '@playwright/test'
import { AppWorld } from './world'
// Worker adds Page Object imports here:

setWorldConstructor(AppWorld)
setDefaultTimeout(30000)

Before(async function (this: AppWorld) {
  this.browser = await chromium.launch({ headless: true })
  this.context = await this.browser.newContext({ baseURL: process.env.BASE_URL ?? 'http://localhost:3000' })
  this.page = await this.context.newPage()

  // Worker adds Page Object instantiation here:
})

After(async function (this: AppWorld) {
  await this.browser?.close()
})
