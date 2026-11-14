export type NavigationTab = '/' | '/history' | '/downloads' | '/settings'

// Map a route path to the primary tab that owns it.
export function navigationTab(path: string): NavigationTab {
  if (path === '/history' || path === '/downloads' || path === '/settings') {
    return path
  }

  return '/'
}
