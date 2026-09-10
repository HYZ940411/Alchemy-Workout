'use client'

import { useEffect } from 'react'

interface ToastProps {
  message: string
  onClose: () => void
  duration?: number
}

/**
 * Toast notification component.
 * Worker should use this in pages via useState to manage toast state.
 *
 * Usage:
 *   const [toast, setToast] = useState<string | null>(null)
 *   {toast && <Toast message={toast} onClose={() => setToast(null)} />}
 */
export function Toast({ message, onClose, duration = 5000 }: ToastProps) {
  useEffect(() => {
    const timer = setTimeout(onClose, duration)
    return () => clearTimeout(timer)
  }, [onClose, duration])

  return (
    <div
      data-testid="toast"
      role="alert"
      style={{
        position: 'fixed',
        bottom: '1rem',
        right: '1rem',
        padding: '0.75rem 1.5rem',
        backgroundColor: '#333',
        color: '#fff',
        borderRadius: '0.5rem',
        zIndex: 9999,
      }}
    >
      {message}
    </div>
  )
}
