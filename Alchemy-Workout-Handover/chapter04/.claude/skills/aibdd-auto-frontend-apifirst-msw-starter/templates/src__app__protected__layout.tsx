import { Sidebar } from '@/components/Sidebar'
import { TopBar } from '@/components/TopBar'

export default function ProtectedLayout({
  children,
}: {
  children: React.ReactNode
}) {
  return (
    <div style={{ display: 'flex', minHeight: '100vh' }}>
      <Sidebar />
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column' }}>
        <TopBar />
        <main style={{ flex: 1, padding: '1rem' }}>{children}</main>
      </div>
    </div>
  )
}
