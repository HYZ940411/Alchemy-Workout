'use client'

import { useEffect, useState } from 'react'

export function MSWProvider({ children }: { children: React.ReactNode }) {
  const [ready, setReady] = useState(false)

  useEffect(() => {
    if (process.env.NEXT_PUBLIC_MOCK_API !== 'true') {
      setReady(true)
      return
    }

    import('@/mocks/browser')
      .then(({ initMocks }) => initMocks())
      .catch(() => {})
      .finally(() => setReady(true))
  }, [])

  if (!ready) return null
  return <>{children}</>
}
