import type { Page } from '@playwright/test'

interface StubOverride {
  method: string
  url: string
  body: unknown
  status: number
  delayMs?: number
}

/**
 * Stub any HTTP method for a given MSW URL pattern.
 * Uses addInitScript so the override is applied before page load.
 */
export async function stubApiMethod(
  page: Page,
  method: string,
  url: string,
  body: unknown,
  status = 200
): Promise<void> {
  await page.addInitScript((override: StubOverride) => {
    const w = window as any
    w.__mswOverrides = w.__mswOverrides ?? []
    w.__mswOverrides.push(override)
  }, { method, url, body, status })
}

/**
 * Stub all HTTP methods for a given MSW URL pattern.
 */
export async function stubApi(
  page: Page,
  url: string,
  body: unknown,
  status = 200
): Promise<void> {
  await stubApiMethod(page, 'ALL', url, body, status)
}

/**
 * Stub with artificial delay (for testing loading states).
 */
export async function stubApiWithDelay(
  page: Page,
  url: string,
  body: unknown,
  delayMs: number,
  status = 200
): Promise<void> {
  await page.addInitScript((override: StubOverride) => {
    const w = window as any
    w.__mswOverrides = w.__mswOverrides ?? []
    w.__mswOverrides.push(override)
  }, { method: 'ALL', url, body, status, delayMs })
}
