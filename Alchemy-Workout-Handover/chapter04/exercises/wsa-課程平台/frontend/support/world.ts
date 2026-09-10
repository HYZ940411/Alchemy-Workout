import { World, IWorldOptions } from '@cucumber/cucumber'
import { Browser, BrowserContext, Page, chromium } from '@playwright/test'
// Worker adds Page Object imports here:

export class AppWorld extends World {
  browser!: Browser
  context!: BrowserContext
  page!: Page

  // Worker adds Page Object properties here:

  constructor(options: IWorldOptions) {
    super(options)
  }
}
