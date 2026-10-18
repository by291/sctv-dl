export type NavigationTab = '/' | '/history' | '/downloads' | '/settings'

export function navigationTab(path: string): NavigationTab {
  if (path === '/history' || path === '/downloads' || path === '/settings') {
    return path
  }

  return '/'
}
