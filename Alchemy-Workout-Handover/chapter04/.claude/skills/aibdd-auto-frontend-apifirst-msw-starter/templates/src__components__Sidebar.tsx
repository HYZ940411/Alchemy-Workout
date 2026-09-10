'use client'

/**
 * Sidebar navigation component.
 * Worker should populate navItems based on flow-map pages.
 */
export function Sidebar() {
  return (
    <aside data-testid="sidebar" style={{ width: 240, borderRight: '1px solid #eee', padding: '1rem' }}>
      <nav data-testid="sidebar-nav">
        {/* Worker fills navigation links from flow-map pages */}
      </nav>
    </aside>
  )
}
