export function validateClientApiEnvironment(legacyBase: unknown, clientBase: unknown): void {
  if (typeof legacyBase === 'string' && legacyBase && legacyBase !== '/api' && !clientBase) {
    throw new Error(
      'VITE_API_BASE targets the legacy raw API. Set VITE_CLIENT_API_BASE to a normalized client API before rebuilding.',
    )
  }
}
